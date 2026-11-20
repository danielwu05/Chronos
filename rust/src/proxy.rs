//! Selective TLS/HTTP filtering proxy (`127.0.0.1:4546`) for Chronos Focus.
//!
//! Only target distraction hosts, user-configured rule domains, and (when Global
//! Detox is enabled) general non-pinned HTML hosts are TLS-intercepted using an
//! automatically generated local Root CA (`~/.local/share/chronos/ca/`). Everything
//! else — CDNs, video streams, auth providers, certificate-pinned sites, and OCSP
//! responders — is spliced via raw TCP passthrough with zero TLS inspection.

use std::collections::{HashMap, HashSet};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Once};
use std::time::{SystemTime, UNIX_EPOCH};

use flate2::read::{DeflateDecoder, GzDecoder};
use openssl::asn1::{Asn1Integer, Asn1Time};
use openssl::bn::BigNum;
use openssl::hash::MessageDigest;
use openssl::nid::Nid;
use openssl::pkey::{PKey, Private};
use openssl::rsa::Rsa;
use openssl::x509::extension::{
    AuthorityKeyIdentifier, BasicConstraints, ExtendedKeyUsage, KeyUsage, SubjectAlternativeName,
    SubjectKeyIdentifier,
};
use openssl::x509::{X509Builder, X509NameBuilder, X509};
use parking_lot::{Mutex, RwLock};
use rustls::pki_types::pem::PemObject;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer, ServerName};
use rustls::{ClientConfig, RootCertStore, ServerConfig};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio_rustls::{TlsAcceptor, TlsConnector};

use crate::{db, engine, steam_api};

pub const PROXY_DEFAULT_PORT: u16 = 4546;
const MAX_HTML_BODY_BYTES: usize = 8 * 1024 * 1024;
const FOCUS_CORE_JS: &str = include_str!("../../chronos_extension/focus_filters_core.js");
const FOCUS_HUD_PANEL_JS: &str = include_str!("../../chronos_extension/focus_hud_panel.js");
const FOCUS_I18N_JS: &str = include_str!("../../chronos_extension/i18n.js");

static CRYPTO_INIT: Once = Once::new();
static PROXY_STARTED: AtomicBool = AtomicBool::new(false);

fn ensure_crypto_provider() {
    CRYPTO_INIT.call_once(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
    });
}

/// Domains whose main HTML responses hold feed/shorts/comments UI that Chronos filters.
const CORE_DISTRACTION_DOMAINS: &[&str] = &[
    "youtube.com",
    "youtu.be",
    "youtube-nocookie.com",
    "instagram.com",
    "tiktok.com",
    "reddit.com",
    "x.com",
    "twitter.com",
    "linkedin.com",
];

/// Game store and launcher community domains filtered when Launcher Filters are active.
const LAUNCHER_STORE_DOMAINS: &[&str] = &[
    "store.steampowered.com",
    "steamcommunity.com",
    "store.epicgames.com",
    "gog.com",
    "itch.io",
    "lutris.net",
];

/// Domains always spliced directly without MITM (video streaming, CDNs, auth, PKI, browser services).
const ALWAYS_PASSTHROUGH_SUFFIXES: &[&str] = &[
    "localhost",
    "127.0.0.1",
    "::1",
    "mozilla.org",
    "mozilla.com",
    "mozilla.net",
    "firefox.com",
    "accounts.google.com",
    "clients1.google.com",
    "clients2.google.com",
    "clients4.google.com",
    "update.googleapis.com",
    "safebrowsing.googleapis.com",
    "pki.goog",
    "googlevideo.com",
    "ytimg.com",
    "ggpht.com",
    "gstatic.com",
    // Google APIs / map tiles / user content: never top-level pages, and intercepting
    // them breaks Maps/Street View streams.
    "googleapis.com",
    "googleusercontent.com",
    "google-analytics.com",
    "googletagmanager.com",
    "doubleclick.net",
    "cdninstagram.com",
    "fbcdn.net",
    "tiktokcdn.com",
    "tiktokv.com",
    "twimg.com",
    "redd.it",
    "redditstatic.com",
    "redditmedia.com",
    "licdn.com",
    "digicert.com",
    "letsencrypt.org",
    "sectigo.com",
    "globalsign.com",
    "steamloopback.host",
    "login.steampowered.com",
    "api.steampowered.com",
    "checkout.steampowered.com",
    "steam-chat.com",
    "steamserver.net",
    "steamcontent.com",
    "steamusercontent.com",
    "steamstatic.com",
    "akamaihd.net",
    "media.steampowered.com",
    "valvesoftware.com",
    "valve.net",
    "cloudfront.net",
    "epicgames-download1.akamaized.net",
    "gog-statics.com",
    "img.itch.zone",
];

fn host_matches_suffix(host: &str, suffix: &str) -> bool {
    let h = host.trim().trim_end_matches('.').to_ascii_lowercase();
    let s = suffix.trim().trim_end_matches('.').to_ascii_lowercase();
    h == s || h.ends_with(&format!(".{s}"))
}

pub(crate) fn known_domains_for_app(app_lower: &str) -> &'static [&'static str] {
    if app_lower.contains("youtube") {
        &["youtube.com", "youtu.be"]
    } else if app_lower.contains("instagram") {
        &["instagram.com"]
    } else if app_lower.contains("tiktok") {
        &["tiktok.com"]
    } else if app_lower.contains("reddit") {
        &["reddit.com", "old.reddit.com"]
    } else if app_lower == "x" || app_lower.contains("twitter") {
        &["x.com", "twitter.com"]
    } else if app_lower.contains("linkedin") {
        &["linkedin.com"]
    } else if app_lower.contains("twitch") {
        &["twitch.tv"]
    } else if app_lower.contains("netflix") {
        &["netflix.com"]
    } else if app_lower.contains("facebook") {
        &["facebook.com"]
    } else if app_lower.contains("discord") {
        &["discord.com"]
    } else if app_lower.contains("spotify") {
        &["open.spotify.com"]
    } else {
        &[]
    }
}

/// Configuration for the proxy runtime (defaults come from user environment).
#[derive(Clone, Debug)]
pub struct ProxyConfig {
    pub bind_addr: String,
    pub ca_dir: PathBuf,
    pub host_map: HashMap<String, String>,
    pub extra_upstream_ca_pem: Option<Vec<u8>>,
}

impl ProxyConfig {
    pub fn from_env() -> Self {
        let ca_dir = if let Ok(custom) = std::env::var("CHRONOS_CA_DIR") {
            PathBuf::from(custom)
        } else {
            let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
            PathBuf::from(home).join(".local/share/chronos/ca")
        };

        let mut host_map = HashMap::new();
        if let Ok(raw_map) = std::env::var("CHRONOS_TEST_HOST_MAP") {
            for entry in raw_map.split(',') {
                if let Some((k, v)) = entry.split_once('=') {
                    let key = k.trim().to_ascii_lowercase();
                    let val = v.trim().to_string();
                    if !key.is_empty() && !val.is_empty() {
                        host_map.insert(key, val);
                    }
                }
            }
        }

        let extra_upstream_ca_pem = std::env::var("CHRONOS_EXTRA_CA_PEM")
            .ok()
            .and_then(|p| std::fs::read(p).ok());

        let bind_addr = std::env::var("CHRONOS_PROXY_BIND")
            .unwrap_or_else(|_| format!("127.0.0.1:{}", crate::profile::proxy_port()));

        Self {
            bind_addr,
            ca_dir,
            host_map,
            extra_upstream_ca_pem,
        }
    }
}

/// Manages the local Root CA and mints short-lived SNI leaf certificates on demand.
pub struct CertAuthority {
    ca_cert: X509,
    ca_cert_der: Vec<u8>,
    ca_key: PKey<Private>,
    leaf_key: PKey<Private>,
    leaf_key_pkcs8: Vec<u8>,
    cache: Mutex<HashMap<String, Arc<ServerConfig>>>,
}

impl CertAuthority {
    /// Loads existing CA material from `ca_dir` or generates and persists a fresh Root CA.
    pub fn load_or_create(ca_dir: &Path) -> Result<Self, String> {
        ensure_crypto_provider();
        std::fs::create_dir_all(ca_dir)
            .map_err(|e| format!("Failed creating CA directory {:?}: {e}", ca_dir))?;

        let crt_path = ca_dir.join("chronos-proxy-ca.crt");
        let key_path = ca_dir.join("chronos-proxy-ca.key");

        let (ca_cert, ca_key) = match (std::fs::read(&crt_path), std::fs::read(&key_path)) {
            (Ok(crt_bytes), Ok(key_bytes)) => {
                match (X509::from_pem(&crt_bytes), PKey::private_key_from_pem(&key_bytes)) {
                    (Ok(cert), Ok(key)) => (cert, key),
                    _ => Self::generate_and_save_ca(&crt_path, &key_path)?,
                }
            }
            _ => Self::generate_and_save_ca(&crt_path, &key_path)?,
        };

        let ca_cert_der = ca_cert
            .to_der()
            .map_err(|e| format!("Failed encoding CA DER: {e}"))?;

        let leaf_rsa = Rsa::generate(2048).map_err(|e| format!("Leaf RSA gen failed: {e}"))?;
        let leaf_key =
            PKey::from_rsa(leaf_rsa).map_err(|e| format!("Leaf PKey wrap failed: {e}"))?;
        let leaf_key_pkcs8 = leaf_key
            .private_key_to_pkcs8()
            .map_err(|e| format!("Leaf PKCS8 failed: {e}"))?;

        Ok(Self {
            ca_cert,
            ca_cert_der,
            ca_key,
            leaf_key,
            leaf_key_pkcs8,
            cache: Mutex::new(HashMap::new()),
        })
    }

    fn generate_and_save_ca(crt_path: &Path, key_path: &Path) -> Result<(X509, PKey<Private>), String> {
        let rsa = Rsa::generate(2048).map_err(|e| format!("CA RSA gen failed: {e}"))?;
        let key = PKey::from_rsa(rsa).map_err(|e| format!("CA PKey failed: {e}"))?;

        let mut name_builder = X509NameBuilder::new().map_err(|e| e.to_string())?;
        name_builder
            .append_entry_by_nid(Nid::ORGANIZATIONNAME, "Chronos Focus")
            .map_err(|e| e.to_string())?;
        name_builder
            .append_entry_by_nid(Nid::COMMONNAME, "Chronos Local Focus CA")
            .map_err(|e| e.to_string())?;
        let name = name_builder.build();

        let mut serial_bn = BigNum::new().map_err(|e| e.to_string())?;
        serial_bn
            .rand(64, openssl::bn::MsbOption::MAYBE_ZERO, false)
            .map_err(|e| e.to_string())?;
        let serial = Asn1Integer::from_bn(&serial_bn).map_err(|e| e.to_string())?;

        let not_before = Asn1Time::days_from_now(0).map_err(|e| e.to_string())?;
        let not_after = Asn1Time::days_from_now(3650).map_err(|e| e.to_string())?;

        let mut builder = X509Builder::new().map_err(|e| e.to_string())?;
        builder.set_version(2).map_err(|e| e.to_string())?;
        builder.set_serial_number(&serial).map_err(|e| e.to_string())?;
        builder.set_subject_name(&name).map_err(|e| e.to_string())?;
        builder.set_issuer_name(&name).map_err(|e| e.to_string())?;
        builder.set_pubkey(&key).map_err(|e| e.to_string())?;
        builder.set_not_before(&not_before).map_err(|e| e.to_string())?;
        builder.set_not_after(&not_after).map_err(|e| e.to_string())?;

        let bc = BasicConstraints::new()
            .critical()
            .ca()
            .pathlen(0)
            .build()
            .map_err(|e| e.to_string())?;
        builder.append_extension(bc).map_err(|e| e.to_string())?;

        let ku = KeyUsage::new()
            .critical()
            .key_cert_sign()
            .crl_sign()
            .build()
            .map_err(|e| e.to_string())?;
        builder.append_extension(ku).map_err(|e| e.to_string())?;

        let ski = {
            let ctx = builder.x509v3_context(None, None);
            SubjectKeyIdentifier::new()
                .build(&ctx)
                .map_err(|e| e.to_string())?
        };
        builder.append_extension(ski).map_err(|e| e.to_string())?;

        builder
            .sign(&key, MessageDigest::sha256())
            .map_err(|e| e.to_string())?;
        let cert = builder.build();

        let crt_pem = cert.to_pem().map_err(|e| e.to_string())?;
        let key_pem = key.private_key_to_pem_pkcs8().map_err(|e| e.to_string())?;

        std::fs::write(crt_path, &crt_pem)
            .map_err(|e| format!("Failed writing CA cert {:?}: {e}", crt_path))?;
        std::fs::write(key_path, &key_pem)
            .map_err(|e| format!("Failed writing CA key {:?}: {e}", key_path))?;

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = std::fs::set_permissions(crt_path, std::fs::Permissions::from_mode(0o644));
            let _ = std::fs::set_permissions(key_path, std::fs::Permissions::from_mode(0o600));
        }

        Ok((cert, key))
    }

    pub fn server_config_for_host(&self, host: &str) -> Result<Arc<ServerConfig>, String> {
        let norm = host.trim().trim_end_matches('.').to_ascii_lowercase();
        if norm.is_empty() {
            return Err("Empty TLS host".to_string());
        }
        {
            let guard = self.cache.lock();
            if let Some(cfg) = guard.get(&norm) {
                return Ok(Arc::clone(cfg));
            }
        }

        let leaf_der = self.mint_leaf_der(&norm)?;
        let certs = vec![
            CertificateDer::from(leaf_der),
            CertificateDer::from(self.ca_cert_der.clone()),
        ];
        let key = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(self.leaf_key_pkcs8.clone()));

        let mut cfg = ServerConfig::builder()
            .with_no_client_auth()
            .with_single_cert(certs, key)
            .map_err(|e| format!("rustls ServerConfig build error for {norm}: {e}"))?;
        cfg.alpn_protocols = vec![b"http/1.1".to_vec()];

        let arc = Arc::new(cfg);
        let mut guard = self.cache.lock();
        guard.insert(norm, Arc::clone(&arc));
        Ok(arc)
    }

    fn mint_leaf_der(&self, host: &str) -> Result<Vec<u8>, String> {
        let mut name_builder = X509NameBuilder::new().map_err(|e| e.to_string())?;
        name_builder
            .append_entry_by_nid(Nid::COMMONNAME, host)
            .map_err(|e| e.to_string())?;
        let subject_name = name_builder.build();

        let mut serial_bn = BigNum::new().map_err(|e| e.to_string())?;
        serial_bn
            .rand(64, openssl::bn::MsbOption::MAYBE_ZERO, false)
            .map_err(|e| e.to_string())?;
        let serial = Asn1Integer::from_bn(&serial_bn).map_err(|e| e.to_string())?;

        let not_before = Asn1Time::from_unix(
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs() as i64
                - 86400,
        )
        .map_err(|e| e.to_string())?;
        let not_after = Asn1Time::days_from_now(90).map_err(|e| e.to_string())?;

        let mut builder = X509Builder::new().map_err(|e| e.to_string())?;
        builder.set_version(2).map_err(|e| e.to_string())?;
        builder.set_serial_number(&serial).map_err(|e| e.to_string())?;
        builder
            .set_subject_name(&subject_name)
            .map_err(|e| e.to_string())?;
        builder
            .set_issuer_name(self.ca_cert.subject_name())
            .map_err(|e| e.to_string())?;
        builder
            .set_pubkey(&self.leaf_key)
            .map_err(|e| e.to_string())?;
        builder
            .set_not_before(&not_before)
            .map_err(|e| e.to_string())?;
        builder
            .set_not_after(&not_after)
            .map_err(|e| e.to_string())?;

        let bc = BasicConstraints::new()
            .build()
            .map_err(|e| e.to_string())?;
        builder.append_extension(bc).map_err(|e| e.to_string())?;

        let ku = KeyUsage::new()
            .critical()
            .digital_signature()
            .key_encipherment()
            .build()
            .map_err(|e| e.to_string())?;
        builder.append_extension(ku).map_err(|e| e.to_string())?;

        let eku = ExtendedKeyUsage::new()
            .server_auth()
            .build()
            .map_err(|e| e.to_string())?;
        builder.append_extension(eku).map_err(|e| e.to_string())?;

        let (san_ext, aki_ext, ski_ext) = {
            let ctx = builder.x509v3_context(Some(&self.ca_cert), None);
            let mut san = SubjectAlternativeName::new();
            if host.parse::<std::net::IpAddr>().is_ok() {
                san.ip(host);
            } else {
                san.dns(host);
                let labels: Vec<&str> = host.split('.').collect();
                if labels.len() >= 3 {
                    let parent = labels[1..].join(".");
                    san.dns(&parent);
                    san.dns(&format!("*.{parent}"));
                } else {
                    san.dns(&format!("*.{host}"));
                }
            }
            let san_ext = san.build(&ctx).map_err(|e| e.to_string())?;
            let aki_ext = AuthorityKeyIdentifier::new()
                .keyid(true)
                .issuer(false)
                .build(&ctx)
                .map_err(|e| e.to_string())?;
            let ski_ext = SubjectKeyIdentifier::new()
                .build(&ctx)
                .map_err(|e| e.to_string())?;
            (san_ext, aki_ext, ski_ext)
        };
        builder.append_extension(san_ext).map_err(|e| e.to_string())?;
        builder.append_extension(ski_ext).map_err(|e| e.to_string())?;
        builder.append_extension(aki_ext).map_err(|e| e.to_string())?;

        builder
            .sign(&self.ca_key, MessageDigest::sha256())
            .map_err(|e| e.to_string())?;
        builder.build().to_der().map_err(|e| e.to_string())
    }
}

struct ProxyState {
    config: ProxyConfig,
    ca: CertAuthority,
    upstream_tls: TlsConnector,
    pinned_bypass: RwLock<HashSet<String>>,
}

impl ProxyState {
    fn new(config: ProxyConfig) -> Result<Self, String> {
        ensure_crypto_provider();
        let ca = CertAuthority::load_or_create(&config.ca_dir)?;
        let mut root_store = RootCertStore::empty();
        for cert in rustls_native_certs::load_native_certs().certs {
            let _ = root_store.add(cert);
        }
        if let Some(ref pem_bytes) = config.extra_upstream_ca_pem {
            let mut cursor = std::io::Cursor::new(pem_bytes);
            for cert in rustls_pki_types::CertificateDer::pem_reader_iter(&mut cursor)
                .filter_map(Result::ok)
            {
                let _ = root_store.add(cert);
            }
        }
        let mut client_cfg = ClientConfig::builder()
            .with_root_certificates(root_store)
            .with_no_client_auth();
        client_cfg.alpn_protocols = vec![b"http/1.1".to_vec()];

        Ok(Self {
            config,
            ca,
            upstream_tls: TlsConnector::from(Arc::new(client_cfg)),
            pinned_bypass: RwLock::new(HashSet::new()),
        })
    }

    fn resolve_upstream_addr(&self, host: &str, port: u16) -> String {
        let clean = host.trim().trim_matches(['[', ']']);
        let lower = clean.to_ascii_lowercase();
        if let Some(mapped) = self.config.host_map.get(&lower) {
            return mapped.clone();
        }
        if clean.contains(':') {
            format!("[{clean}]:{port}")
        } else {
            format!("{clean}:{port}")
        }
    }
}

/// Runs the Chronos filtering proxy listener until terminated.
pub async fn run_proxy_server(config: ProxyConfig) -> Result<(), String> {
    let state = Arc::new(ProxyState::new(config.clone())?);
    let listener = TcpListener::bind(&config.bind_addr)
        .await
        .map_err(|e| format!("Failed binding proxy on {}: {e}", config.bind_addr))?;
    loop {
        let Ok((stream, _addr)) = listener.accept().await else {
            continue;
        };
        let state_ref = Arc::clone(&state);
        tokio::spawn(async move {
            let _ = handle_client(stream, state_ref).await;
        });
    }
}

/// Ensures the background Chronos filtering proxy daemon is bound and running.
/// Safe to call multiple times from `setup_database` or initialization hooks.
pub fn ensure_proxy_running() {
    if PROXY_STARTED.swap(true, Ordering::SeqCst) {
        return;
    }
    std::thread::Builder::new()
        .name("chronos-proxy".to_string())
        .spawn(move || {
            let rt = match tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .enable_all()
                .build()
            {
                Ok(rt) => rt,
                Err(_) => {
                    PROXY_STARTED.store(false, Ordering::SeqCst);
                    return;
                }
            };
            let config = ProxyConfig::from_env();
            rt.block_on(async move {
                if run_proxy_server(config).await.is_err() {
                    PROXY_STARTED.store(false, Ordering::SeqCst);
                }
            });
        })
        .ok();
}

pub fn is_proxy_running() -> bool {
    PROXY_STARTED.load(Ordering::SeqCst)
}

/// Starts a bindable proxy instance on `config.bind_addr` (returning bound address for tests).
pub async fn spawn_proxy_for_test(config: ProxyConfig) -> Result<std::net::SocketAddr, String> {
    let state = Arc::new(ProxyState::new(config.clone())?);
    let listener = TcpListener::bind(&config.bind_addr)
        .await
        .map_err(|e| format!("Bind failed: {e}"))?;
    let addr = listener.local_addr().map_err(|e| e.to_string())?;
    tokio::spawn(async move {
        loop {
            let Ok((stream, _)) = listener.accept().await else {
                continue;
            };
            let st = Arc::clone(&state);
            tokio::spawn(async move {
                let _ = handle_client(stream, st).await;
            });
        }
    });
    Ok(addr)
}

/// Collects all site/domain/app patterns configured in rules (`SITE`, `KEYWORD`, `SITE_GROUP`, `GROUP`).
pub(crate) fn extract_rule_patterns(item: &engine::SiteStatusItem) -> Vec<String> {
    let target_type = item.target_type.to_ascii_uppercase();
    if target_type != "SITE"
        && target_type != "KEYWORD"
        && target_type != "SITE_GROUP"
        && target_type != "GROUP"
    {
        return Vec::new();
    }
    let (apps, sites) = engine::parse_group_pattern_rich(&item.pattern);
    let mut patterns = Vec::new();
    for s in sites {
        let c = s.trim().to_ascii_lowercase();
        if !c.is_empty() {
            patterns.push(c);
        }
    }
    for app in apps {
        for raw in [&app.name, &app.exec] {
            let app_l = raw.trim().to_ascii_lowercase();
            if app_l.is_empty() {
                continue;
            }
            patterns.push(app_l.clone());
            for d in known_domains_for_app(&app_l) {
                patterns.push((*d).to_string());
            }
        }
    }
    if patterns.is_empty() && (target_type == "SITE" || target_type == "KEYWORD" || target_type == "SITE_GROUP") {
        patterns.push(item.entity_id.to_ascii_lowercase());
    }
    patterns.sort();
    patterns.dedup();
    patterns
}

/// Checks whether [target] or [title] matches any user-configured whitelist group.
pub(crate) fn is_whitelisted_target(target: &str, title: &str) -> bool {
    // YouTube videos of a whitelisted content type (under its daily cap) stay reachable
    // even when the YouTube rule is exhausted/blocked.
    if let Some(yt) = crate::youtube::parse_youtube_url(target) {
        if crate::youtube::exempt_type_for(&yt).is_some() {
            return true;
        }
    }
    let target_l = target.to_ascii_lowercase();
    let title_l = title.to_ascii_lowercase();
    for wg in db::get_all_whitelist_groups() {
        let (apps, sites) = engine::parse_group_pattern_rich(&wg.items);
        for s in sites {
            let pat = s.trim().to_ascii_lowercase();
            if !pat.is_empty() && (target_l.contains(&pat) || (!title_l.is_empty() && title_l.contains(&pat))) {
                return true;
            }
        }
        for app in apps {
            for raw in [&app.name, &app.exec] {
                let pat = raw.trim().to_ascii_lowercase();
                if !pat.is_empty() && (target_l.contains(&pat) || (!title_l.is_empty() && title_l.contains(&pat))) {
                    return true;
                }
            }
        }
    }
    false
}

pub(crate) fn is_never_pinned_bypass_host(host_lower: &str) -> bool {
    CORE_DISTRACTION_DOMAINS
        .iter()
        .any(|s| host_matches_suffix(host_lower, s))
        || LAUNCHER_STORE_DOMAINS
            .iter()
            .any(|s| host_matches_suffix(host_lower, s))
}

/// Determines whether a host should undergo selective TLS interception.
pub fn should_intercept_host(
    host: &str,
    filters: &db::FocusFilters,
    site_rules: &[engine::SiteStatusItem],
    pinned_bypass: &HashSet<String>,
) -> bool {
    let clean = host.trim().trim_end_matches('.').to_ascii_lowercase();
    if clean.is_empty() {
        return false;
    }
    if ALWAYS_PASSTHROUGH_SUFFIXES
        .iter()
        .any(|s| host_matches_suffix(&clean, s))
    {
        return false;
    }
    if clean.starts_with("ocsp.") || clean.starts_with("crl.") {
        return false;
    }
    // Google Maps tile/imagery hosts (khms0.google.com, mt1.google.com, ...).
    if let Some(first) = clean.strip_suffix(".google.com") {
        if ["khms", "khm", "mt", "kh"].iter().any(|p| {
            first.strip_prefix(p).is_some_and(|rest| !rest.is_empty() && rest.chars().all(|c| c.is_ascii_digit()))
        }) {
            return false;
        }
    }
    if CORE_DISTRACTION_DOMAINS
        .iter()
        .any(|s| host_matches_suffix(&clean, s))
    {
        return true;
    }
    if pinned_bypass.contains(&clean) {
        return false;
    }
    if crate::adult::should_intercept_host(&clean) {
        return true;
    }
    let has_launcher_rules = filters.launcher_filter_enabled
        && (!filters.launcher_blocked_tags.is_empty() || !filters.launcher_blocked_names.is_empty());
    if has_launcher_rules
        && LAUNCHER_STORE_DOMAINS
            .iter()
            .any(|s| host_matches_suffix(&clean, s))
    {
        return true;
    }
    for rule in site_rules {
        for pat in extract_rule_patterns(rule) {
            if !pat.is_empty() && (clean.contains(&pat) || host_matches_suffix(&clean, &pat)) {
                return true;
            }
        }
    }
    // Detox-only interception (CSS on every page) skips Google: intercepting
    // www.google.com breaks Maps/Street View rendering.
    if is_google_web_host(&clean) {
        return false;
    }
    filters.global_grayscale || filters.global_block_notifications
}

/// google.com / google.com.br / maps.google.* (Search, Maps, Street View pages).
fn is_google_web_host(host: &str) -> bool {
    let h = host.strip_prefix("www.").unwrap_or(host);
    let h = h.strip_prefix("maps.").unwrap_or(h);
    h == "google.com" || h.starts_with("google.com.") || h.starts_with("google.") && h.matches('.').count() <= 2
}

pub(crate) fn find_matching_rule<'a>(
    target: &str,
    title: &str,
    site_rules: &'a [engine::SiteStatusItem],
) -> Option<&'a engine::SiteStatusItem> {
    let target_l = target.to_ascii_lowercase();
    let title_l = title.to_ascii_lowercase();
    for rule in site_rules {
        for pat in extract_rule_patterns(rule) {
            if !pat.is_empty()
                && (target_l.contains(&pat) || (!title_l.is_empty() && title_l.contains(&pat)))
            {
                return Some(rule);
            }
        }
    }
    None
}

pub(crate) fn find_blocked_rule<'a>(
    full_url: &str,
    site_rules: &'a [engine::SiteStatusItem],
) -> Option<&'a engine::SiteStatusItem> {
    if is_whitelisted_target(full_url, "") {
        return None;
    }
    let target = full_url.to_ascii_lowercase();
    for rule in site_rules {
        if !rule.is_blocked {
            continue;
        }
        for pat in extract_rule_patterns(rule) {
            if !pat.is_empty() && target.contains(&pat) {
                return Some(rule);
            }
        }
    }
    None
}

/// Computes URL-level redirects matching `focus_filters_core.js` `getRedirectTarget`.
pub fn check_focus_redirect(host: &str, path_and_query: &str, f: &db::FocusFilters) -> Option<String> {
    let h = host.to_ascii_lowercase();
    let path = path_and_query.split('?').next().unwrap_or(path_and_query);

    if h.contains("youtube.com") || h == "youtu.be" || h.ends_with(".youtu.be") {
        if f.yt_block_shorts && (path == "/shorts" || path.starts_with("/shorts/")) {
            return Some(format!("https://{host}/"));
        }
        if f.yt_educational_mode && (path == "/feed/trending" || path == "/feed/explore") {
            return Some(format!("https://{host}/"));
        }
    }
    if h.contains("instagram.com") {
        if f.ig_block_reels && (path.starts_with("/reels") || path.starts_with("/reel/")) {
            return Some(format!("https://{host}/"));
        }
        if f.ig_block_feed && path.starts_with("/explore") {
            return Some(format!("https://{host}/"));
        }
    }
    None
}

pub(crate) fn focus_filters_json_value(f: &db::FocusFilters) -> serde_json::Value {
    serde_json::json!({
        "blockShorts": false,
        "grayscaleMode": f.global_grayscale,
        "educationalOnly": false,
        "blockFeed": false,
        "blockComments": false,
        "blockNotifications": f.global_block_notifications,
        "ytBlockShorts": f.yt_block_shorts,
        "ytEducationalMode": f.yt_educational_mode,
        "ytBlockSidebar": f.yt_block_sidebar,
        "ytBlockComments": f.yt_block_comments,
        "ytShowOnlyEnabled": f.yt_show_only_enabled,
        "ytShowOnlyTypes": f.yt_show_only_types,
        "igBlockReels": f.ig_block_reels,
        "igBlockFeed": f.ig_block_feed,
        "igBlockComments": f.ig_block_comments,
        "ttBlockFeed": f.tt_block_feed,
        "rdBlockFeed": f.rd_block_feed,
        "rdBlockComments": f.rd_block_comments,
        "twBlockFeed": f.tw_block_feed,
        "twBlockTrends": f.tw_block_trends,
        "rdBlockNsfw": f.rd_block_nsfw,
        "twBlockSensitive": f.tw_block_sensitive,
        "liBlockFeed": f.li_block_feed,
        "globalGrayscale": f.global_grayscale,
        "globalBlockNotifications": f.global_block_notifications,
        "hudAlpha": db::clamp_hud_alpha(f.hud_alpha),
        "hudHideToEye": f.hud_hide_to_eye,
        "hudScale": db::clamp_hud_scale(f.hud_scale),
        "launcherFilterEnabled": f.launcher_filter_enabled,
        "launcherBlockedTags": f.launcher_blocked_tags,
        "launcherBlockedNames": f.launcher_blocked_names,
    })
}

/// Builds initial critical `<style>` CSS mirroring `focus_filters_core.js` so HTML
/// already renders filtered on first byte before scripts execute (zero FOUC).
pub fn build_initial_css(host: &str, f: &db::FocusFilters) -> String {
    let h = host.to_ascii_lowercase();
    let mut css = String::new();

    if f.global_grayscale {
        css.push_str(
            ":root.chronos-grayscale, html.chronos-grayscale { filter: grayscale(100%) !important; -webkit-filter: grayscale(100%) !important; }\n\
             html.chronos-grayscale :fullscreen, html.chronos-grayscale video { filter: grayscale(100%) !important; -webkit-filter: grayscale(100%) !important; }\n",
        );
    }

    if f.global_block_notifications {
        css.push_str(
            "ytd-notification-topbar-button-renderer, .notification-badge-count, [aria-label*=\"notificações não lidas\" i], [aria-label*=\"unread notifications\" i] { display: none !important; visibility: hidden !important; }\n",
        );
    }

    if h.contains("youtube.com") || h.contains("youtu.be") {
        if f.yt_block_shorts {
            css.push_str(
                "ytd-rich-section-renderer:has(a[href*=\"/shorts/\"]), ytd-rich-shelf-renderer[is-shorts], ytd-reel-shelf-renderer, grid-shelf-view-model:has(a[href*=\"/shorts/\"]), ytm-shorts-lockup-view-model, ytm-shorts-lockup-view-model-v2, ytd-guide-entry-renderer:has(a[href^=\"/shorts\"]), ytd-mini-guide-entry-renderer:has(a[href^=\"/shorts\"]), ytd-video-renderer:has(a[href*=\"/shorts/\"]), ytd-grid-video-renderer:has(a[href*=\"/shorts/\"]), yt-tab-shape[tab-title=\"Shorts\"], a[href^=\"/shorts\"] { display: none !important; }\n",
            );
        }
        if f.yt_educational_mode {
            css.push_str(
                "ytd-browse[page-subtype=\"home\"] #contents.ytd-rich-grid-renderer, ytd-browse[page-subtype=\"home\"] ytd-rich-grid-renderer, #chips-wrapper.ytd-feed-filter-chip-bar-renderer, ytd-feed-filter-chip-bar-renderer { display: none !important; }\n",
            );
        }
        if f.yt_block_sidebar {
            css.push_str(
                "#related, ytd-watch-next-secondary-results-renderer, #secondary-inner #related, .ytp-endscreen-content, .ytp-ce-element, .html5-endscreen { display: none !important; }\n",
            );
        }
        if f.yt_block_comments {
            css.push_str("#comments, ytd-comments { display: none !important; }\n");
        }
    } else if h.contains("instagram.com") {
        if f.ig_block_reels {
            css.push_str("a[href*=\"/reels\"], nav a[href=\"/reels/\"] { display: none !important; }\n");
        }
        if f.ig_block_feed {
            css.push_str("main div[role=\"feed\"], a[href=\"/explore/\"], a[href*=\"/explore/\"] { display: none !important; }\n");
        }
        if f.ig_block_comments {
            css.push_str("ul._a9ym, article section + div ul { display: none !important; }\n");
        }
    } else if h.contains("tiktok.com") && f.tt_block_feed {
        css.push_str("[data-e2e=\"recommend-list-item-container\"], [data-e2e=\"feed-video\"] { display: none !important; }\n");
    } else if h.contains("reddit.com") {
        if f.rd_block_feed {
            css.push_str("shreddit-feed, div[data-testid=\"frontpage-feed\"] { display: none !important; }\n");
        }
        if f.rd_block_comments {
            css.push_str("shreddit-comment-tree, #comment-tree, .commentarea { display: none !important; }\n");
        }
    } else if h.contains("x.com") || h.contains("twitter.com") {
        if f.tw_block_feed {
            css.push_str("[aria-label=\"Timeline: Your Home Timeline\"], [aria-label=\"Timeline: Página Inicial\"], [data-testid=\"primaryColumn\"] section[role=\"region\"] { display: none !important; }\n");
        }
        if f.tw_block_trends {
            css.push_str("[data-testid=\"sidebarColumn\"] [aria-label=\"Timeline: Trending now\"], [data-testid=\"trend\"] { display: none !important; }\n");
        }
    } else if h.contains("linkedin.com") && f.li_block_feed {
        css.push_str("main.scaffold-layout__main div[data-finite-scroll-hotkey-context=\"FEED\"] { display: none !important; }\n");
    }

    css
}

/// Generates a random hex nonce string safe for HTML attributes and CSP directives.
fn generate_nonce() -> String {
    let mut bn = BigNum::new().unwrap_or_else(|_| BigNum::from_u32(42).unwrap());
    let _ = bn.rand(96, openssl::bn::MsbOption::MAYBE_ZERO, false);
    format!("chronos_{}", bn.to_hex_str().map(|s| s.to_string()).unwrap_or_else(|_| "nonce".into()))
}

fn csp_allows_inline_without_nonce(tokens: &[String]) -> bool {
    let mut has_unsafe_inline = false;
    let mut has_nonce_or_hash_or_dynamic = false;
    for tok in tokens {
        let lower = tok.to_ascii_lowercase();
        if lower == "'unsafe-inline'" {
            has_unsafe_inline = true;
        } else if lower.starts_with("'nonce-")
            || lower.starts_with("'sha256-")
            || lower.starts_with("'sha384-")
            || lower.starts_with("'sha512-")
            || lower == "'strict-dynamic'"
        {
            has_nonce_or_hash_or_dynamic = true;
        }
    }
    has_unsafe_inline && !has_nonce_or_hash_or_dynamic
}

fn find_directive_idx(dirs: &[(String, Vec<String>)], target: &str) -> Option<usize> {
    dirs.iter().position(|(n, _)| n.eq_ignore_ascii_case(target))
}

fn ensure_nonce_for_csp_kind(
    dirs: &mut Vec<(String, Vec<String>)>,
    specific_elem: &str,
    specific: &str,
    nonce_tok: &str,
) {
    let default_idx = find_directive_idx(dirs, "default-src");
    let specific_idx =
        find_directive_idx(dirs, specific_elem).or_else(|| find_directive_idx(dirs, specific));
    let Some(eff_idx) = specific_idx.or(default_idx) else {
        return;
    };
    if csp_allows_inline_without_nonce(&dirs[eff_idx].1) {
        return;
    }
    if specific_idx.is_none() {
        let mut tokens: Vec<String> = dirs[eff_idx]
            .1
            .iter()
            .filter(|t| !t.eq_ignore_ascii_case("'none'"))
            .cloned()
            .collect();
        tokens.push(nonce_tok.to_string());
        dirs.push((specific.to_string(), tokens));
    } else {
        let tokens = &mut dirs[eff_idx].1;
        tokens.retain(|t| !t.eq_ignore_ascii_case("'none'"));
        if !tokens.iter().any(|t| t == nonce_tok) {
            tokens.push(nonce_tok.to_string());
        }
    }
}

/// Injects `'nonce-<nonce>'` (and `'self'` to `connect-src`) into a CSP header value
/// without ever invalidating an existing `'unsafe-inline'` directive on host pages.
pub fn patch_csp_header(csp: &str, nonce: &str) -> String {
    let nonce_tok = format!("'nonce-{nonce}'");
    csp.split(',')
        .map(|policy| {
            let mut dirs: Vec<(String, Vec<String>)> = policy
                .split(';')
                .filter_map(|d| {
                    let trimmed = d.trim();
                    if trimmed.is_empty() {
                        return None;
                    }
                    let mut parts = trimmed.split_whitespace();
                    let name = parts.next()?.to_string();
                    let tokens = parts.map(|s| s.to_string()).collect::<Vec<_>>();
                    Some((name, tokens))
                })
                .collect();

            ensure_nonce_for_csp_kind(&mut dirs, "script-src-elem", "script-src", &nonce_tok);
            ensure_nonce_for_csp_kind(&mut dirs, "style-src-elem", "style-src", &nonce_tok);

            if let Some(c_idx) = find_directive_idx(&dirs, "connect-src") {
                let tokens = &mut dirs[c_idx].1;
                tokens.retain(|t| !t.eq_ignore_ascii_case("'none'"));
                if !tokens
                    .iter()
                    .any(|t| t.eq_ignore_ascii_case("'self'") || t == "*")
                {
                    tokens.push("'self'".to_string());
                }
            } else if let Some(d_idx) = find_directive_idx(&dirs, "default-src") {
                let needs_connect = !dirs[d_idx]
                    .1
                    .iter()
                    .any(|t| t.eq_ignore_ascii_case("'self'") || t == "*");
                if needs_connect {
                    let mut tokens: Vec<String> = dirs[d_idx]
                        .1
                        .iter()
                        .filter(|t| !t.eq_ignore_ascii_case("'none'"))
                        .cloned()
                        .collect();
                    tokens.push("'self'".to_string());
                    dirs.push(("connect-src".to_string(), tokens));
                }
            }

            dirs.into_iter()
                .map(|(name, tokens)| {
                    if tokens.is_empty() {
                        name
                    } else {
                        format!("{name} {}", tokens.join(" "))
                    }
                })
                .collect::<Vec<_>>()
                .join("; ")
        })
        .collect::<Vec<_>>()
        .join(", ")
}

/// Injects initial CSS + shared `focus_filters_core.js` runtime safely into an HTML page.
/// A complete page (has `<html>`, `<head>` or `<body>` near the start) rather than a fragment.
pub fn is_full_html_document(html: &str) -> bool {
    let head: String = html.chars().take(4096).collect::<String>().to_ascii_lowercase();
    head.contains("<!doctype html") || head.contains("<html") || head.contains("<head") || head.contains("<body")
}

pub fn inject_html(html: &str, host: &str, filters: &db::FocusFilters, nonce: &str) -> String {
    let initial_css = build_initial_css(host, filters);
    let safe_core_js = FOCUS_CORE_JS.replace("</", "<\\/");
    let safe_panel_js = FOCUS_HUD_PANEL_JS.replace("</", "<\\/");
    let safe_i18n_js = FOCUS_I18N_JS.replace("</", "<\\/");
    let filters_json = serde_json::to_string(&focus_filters_json_value(filters))
        .unwrap_or_else(|_| "{}".to_string())
        .replace("</", "<\\/");
    let (primary_lang, steam_lang) = (
        db::get_primary_language(),
        db::get_steam_language_and_country().0,
    );
    let tag_display_map_json = serde_json::to_string(&steam_api::translate_tags_for_display(
        &filters.launcher_blocked_tags,
        steam_lang,
    ))
    .unwrap_or_else(|_| "{}".to_string())
    .replace("</", "<\\/");
    let ac_active_js = if db::try_get_conn().is_some() && crate::engine::get_anti_cheat_state().is_active {
        "true"
    } else {
        "false"
    };
    let primary_lang_json = serde_json::to_string(&primary_lang)
        .unwrap_or_else(|_| "\"pt-BR\"".to_string())
        .replace("</", "<\\/");

    let runtime_js = format!(
        r#"(function() {{
  if (window.__chronosProxyRuntime) return;
  window.__chronosProxyRuntime = true;
  try {{
    {safe_core_js}
    {safe_i18n_js}
    {safe_panel_js}
    var core = window.ChronosFocusCore;
    var hudFactory = window.ChronosHudPanel;
    if (!core) return;
    var host = (window.location.hostname || '').toLowerCase();
    var currentFilters = {filters_json};
    var currentTagDisplayMap = {tag_display_map_json};
    var currentPrimaryLanguage = {primary_lang_json};
    if (window.ChronosI18n) window.ChronosI18n.setLang(currentPrimaryLanguage);
    var currentAntiCheatActive = {ac_active_js};
    var sseConnected = false;
    var styleId = 'chronos-focus-css';
    var hud = null;
    function ensureStyle() {{
      var el = document.getElementById(styleId);
      if (!el) {{
        el = document.createElement('style');
        el.id = styleId;
        el.setAttribute('nonce', '{nonce}');
        (document.head || document.documentElement).appendChild(el);
      }}
      return el;
    }}
    function launcherFilterOpts() {{
      return {{
        document: document,
        location: window.location,
        url: window.location.href,
        host: host,
        tagDisplayMap: currentTagDisplayMap,
        primaryLanguage: currentPrimaryLanguage,
        resolveItems: function(items, done, metaOpts) {{
          fetch('/__chronos_api__/launchers/resolve', {{
            method: 'POST',
            headers: {{ 'Content-Type': 'application/json' }},
            body: JSON.stringify({{ items: items }}),
            cache: 'no-store',
            credentials: 'omit',
            keepalive: Boolean(metaOpts && metaOpts.keepalive)
          }})
            .then(function(r) {{ return r.ok ? r.json() : {{ success: false, results: [] }}; }})
            .then(function(d) {{ done(d); }})
            .catch(function() {{ done({{ success: false, results: [] }}); }});
        }},
        onBlockPage: function(info) {{
          var target = '/__chronos_api__/launchers/blocked?site=' +
            encodeURIComponent((info && info.title) || document.title || host) +
            '&reason=' + encodeURIComponent((info && info.reason) || 'Filtro de launcher ativo') +
            '&url=' + encodeURIComponent(window.location.href);
          window.location.replace(target);
        }}
      }};
    }}
    function applyAll(nextFilters, nextTagMap, nextLang, nextAntiCheatActive) {{
      currentFilters = core.normalizeFilters(nextFilters || currentFilters);
      if (nextTagMap && typeof nextTagMap === 'object') currentTagDisplayMap = nextTagMap;
      if (typeof nextLang === 'string' && nextLang) currentPrimaryLanguage = nextLang;
      if (typeof nextAntiCheatActive === 'boolean') currentAntiCheatActive = nextAntiCheatActive;
      var curPath = window.location.pathname || '/';
      core.syncHtmlAttributes(currentFilters, host, curPath, document.documentElement);
      var redirectUrl = core.getRedirectTarget(currentFilters, host, curPath, window.location.origin);
      if (redirectUrl && redirectUrl !== window.location.href) {{
        window.location.replace(redirectUrl);
        return;
      }}
      var css = core.buildFocusCss(currentFilters, host, curPath);
      var st = ensureStyle();
      if (st.textContent !== css) st.textContent = css;
      if (window.ChronosLauncherDomFilter) {{
        window.ChronosLauncherDomFilter.apply(currentFilters, launcherFilterOpts());
      }}
      if (window.ChronosYoutubeTypeFilter) {{
        window.ChronosYoutubeTypeFilter.apply(currentFilters, {{
          document: document,
          location: window.location,
          classifyItems: function(items, done) {{
            fetch('/__chronos_api__/youtube/classify', {{
              method: 'POST',
              headers: {{ 'Content-Type': 'application/json' }},
              body: JSON.stringify({{ items: items }}),
              cache: 'no-store',
              credentials: 'omit'
            }})
              .then(function(r) {{ return r.ok ? r.json() : {{ success: false, results: [] }}; }})
              .then(function(d) {{ done(d); }})
              .catch(function() {{ done({{ success: false, results: [] }}); }});
          }},
          skipShort: function() {{
            var b = document.querySelector('#navigation-button-down button');
            if (b) {{ b.click(); return; }}
            document.dispatchEvent(new KeyboardEvent('keydown', {{ key: 'ArrowDown', code: 'ArrowDown', keyCode: 40, bubbles: true }}));
          }}
        }});
      }}
      if (hud) hud.syncFilters(currentFilters, currentTagDisplayMap, currentPrimaryLanguage, currentAntiCheatActive);
    }}
    applyAll(currentFilters, currentTagDisplayMap, currentPrimaryLanguage, currentAntiCheatActive);

    if (hudFactory) {{
      hud = hudFactory.create({{
        source: 'proxy',
        nonce: '{nonce}',
        antiCheatActive: currentAntiCheatActive,
        getAntiCheatActive: function() {{ return currentAntiCheatActive; }},
        getHost: function() {{ return (window.location.hostname || '').toLowerCase(); }},
        getInitialFilters: function() {{ return currentFilters; }},
        getTagDisplayMap: function() {{ return currentTagDisplayMap; }},
        getPrimaryLanguage: function() {{ return currentPrimaryLanguage; }},
        onApplyFilters: function(f) {{ applyAll(f, currentTagDisplayMap, currentPrimaryLanguage, currentAntiCheatActive); }},
        onSaveFilters: function(nextFilters, done) {{
          fetch('/__chronos_api__/focus-filters', {{
            method: 'POST',
            headers: {{ 'Content-Type': 'application/json' }},
            body: JSON.stringify(nextFilters),
            cache: 'no-store',
            credentials: 'omit'
          }})
            .then(function(r) {{ return r.json().catch(function() {{ return null; }}); }})
            .then(function(d) {{
              if (d && typeof d.antiCheatActive === 'boolean') {{
                currentAntiCheatActive = d.antiCheatActive;
              }} else if (d && d.antiCheatLocked) {{
                currentAntiCheatActive = true;
              }}
              if (d && d.success && d.focusFilters) {{
                done({{
                  success: true,
                  antiCheatActive: currentAntiCheatActive,
                  filters: d.focusFilters,
                  tagDisplayMap: d.tagDisplayMap || null,
                  primaryLanguage: d.primaryLanguage || null
                }});
              }} else {{
                done({{
                  success: false,
                  antiCheatActive: currentAntiCheatActive,
                  antiCheatLocked: Boolean(d && d.antiCheatLocked),
                  message: (d && d.message) || 'Falha ao salvar filtros',
                  filters: (d && d.focusFilters) || null,
                  tagDisplayMap: (d && d.tagDisplayMap) || null,
                  primaryLanguage: (d && d.primaryLanguage) || null
                }});
              }}
            }})
            .catch(function() {{
              done({{ success: false }});
            }});
        }},
        onRequestStatus: function(done) {{
          fetch('/__chronos_api__/status', {{ cache: 'no-store', credentials: 'omit' }})
            .then(function(r) {{ return r.ok ? r.json() : null; }})
            .then(function(d) {{
              if (!d) {{
                done(null);
                return;
              }}
              if (d.tagDisplayMap) currentTagDisplayMap = d.tagDisplayMap;
              if (d.primaryLanguage) currentPrimaryLanguage = d.primaryLanguage;
              done({{
                isConnected: true,
                antiCheatActive: Boolean(d.antiCheatActive),
                focusFilters: d.focusFilters,
                tagDisplayMap: d.tagDisplayMap || currentTagDisplayMap,
                primaryLanguage: d.primaryLanguage || currentPrimaryLanguage,
                sites: d.sites
              }});
            }})
            .catch(function() {{
              done(null);
            }});
        }},
        onFetchPopularTags: function(done) {{
          fetch('/__chronos_api__/launchers/tags', {{ cache: 'no-store', credentials: 'omit' }})
            .then(function(r) {{ return r.ok ? r.json() : null; }})
            .then(function(d) {{ done(d); }})
            .catch(function() {{ done(null); }});
        }},
        onSearchLauncherAutocomplete: function(kind, query, done) {{
          var url = '/__chronos_api__/launchers/autocomplete?kind=' +
            encodeURIComponent(kind || 'tag') +
            '&q=' + encodeURIComponent(query || '');
          fetch(url, {{ cache: 'no-store', credentials: 'omit' }})
            .then(function(r) {{ return r.ok ? r.json() : null; }})
            .then(function(d) {{ done(d); }})
            .catch(function() {{ done(null); }});
        }}
      }});
    }}

    function pollFilters() {{
      if (document.hidden) return;
      if (hud && (hud.isSaving() || Date.now() < hud.getSuppressPollUntil())) return;
      fetch('/__chronos_api__/focus-filters', {{ cache: 'no-store', credentials: 'omit' }})
        .then(function(r) {{ return r.ok ? r.json() : null; }})
        .then(function(d) {{
          if (!d || (!d.focusFilters && typeof d.antiCheatActive !== 'boolean')) return;
          if (hud && (hud.isSaving() || Date.now() < hud.getSuppressPollUntil())) return;
          applyAll(d.focusFilters || currentFilters, d.tagDisplayMap, d.primaryLanguage, d.antiCheatActive);
        }})
        .catch(function() {{}});
      if (hud) hud.pollIfPanelOpen();
    }}
    function startSse() {{
      if (typeof EventSource === 'undefined') return;
      try {{
        var es = new EventSource('/__chronos_api__/events');
        es.onopen = function() {{ sseConnected = true; }};
        es.addEventListener('chronos_update', function(ev) {{
          try {{
            var d = JSON.parse(ev.data || '{{}}');
            if (!d || (!d.focusFilters && typeof d.antiCheatActive !== 'boolean')) return;
            if (hud && (hud.isSaving() || Date.now() < hud.getSuppressPollUntil())) return;
            applyAll(d.focusFilters || currentFilters, d.tagDisplayMap, d.primaryLanguage, d.antiCheatActive);
            if (hud) hud.pollIfPanelOpen();
          }} catch (_) {{}}
        }});
        es.onerror = function() {{ sseConnected = false; }};
      }} catch (_) {{ sseConnected = false; }}
    }}
    startSse();
    function sendHeartbeat() {{
      if (document.hidden) return;
      fetch('/__chronos_api__/heartbeat', {{
        method: 'POST',
        headers: {{ 'Content-Type': 'application/json' }},
        body: JSON.stringify({{ url: window.location.href, title: document.title || '' }}),
        keepalive: true
      }}).then(function(r) {{ return r.ok ? r.json() : null; }})
        .then(function(d) {{
          if (!d) return;
          if (d.blocked && d.blockedUrl) {{
            window.location.replace(d.blockedUrl);
            return;
          }}
          if (hud) {{
            hud.updateRule(d.matched && d.rule ? d.rule : null);
          }}
        }})
        .catch(function() {{}});
    }}
    var origPush = history.pushState;
    history.pushState = function() {{
      var res = origPush.apply(this, arguments);
      setTimeout(function() {{ applyAll(currentFilters); sendHeartbeat(); }}, 40);
      return res;
    }};
    var origReplace = history.replaceState;
    history.replaceState = function() {{
      var res = origReplace.apply(this, arguments);
      setTimeout(function() {{ applyAll(currentFilters); sendHeartbeat(); }}, 40);
      return res;
    }};
    window.addEventListener('popstate', function() {{ setTimeout(function() {{ applyAll(currentFilters); sendHeartbeat(); }}, 40); }}, true);
    window.addEventListener('yt-navigate-finish', function() {{ setTimeout(function() {{ applyAll(currentFilters); sendHeartbeat(); }}, 50); }}, true);
    var rafPending = false;
    var observer = new MutationObserver(function() {{
      if (rafPending) return;
      rafPending = true;
      requestAnimationFrame(function() {{
        rafPending = false;
        core.syncHtmlAttributes(currentFilters, host, window.location.pathname || '/', document.documentElement);
        if (window.ChronosLauncherDomFilter) {{
          window.ChronosLauncherDomFilter.apply(currentFilters, launcherFilterOpts());
        }}
        if (hud) hud.ensureMounted();
      }});
    }});
    if (document.documentElement) {{
      observer.observe(document.documentElement, {{ childList: true, subtree: true }});
    }}
    if (document.readyState === 'loading') {{
      document.addEventListener('DOMContentLoaded', function() {{
        if (window.ChronosLauncherDomFilter) {{
          window.ChronosLauncherDomFilter.apply(currentFilters, launcherFilterOpts());
        }}
        if (hud) hud.ensureMounted();
        sendHeartbeat();
      }}, {{ once: true }});
    }} else {{
      if (window.ChronosLauncherDomFilter) {{
        window.ChronosLauncherDomFilter.apply(currentFilters, launcherFilterOpts());
      }}
      if (hud) hud.ensureMounted();
      sendHeartbeat();
    }}
    setInterval(function() {{
      if (!sseConnected) pollFilters();
    }}, 2500);
    setInterval(pollFilters, 8000);
    setInterval(function() {{
      sendHeartbeat();
      if (!document.hidden && window.ChronosLauncherDomFilter) {{
        window.ChronosLauncherDomFilter.apply(currentFilters, launcherFilterOpts());
      }}
    }}, 1500);
  }} catch (_) {{}}
}})();"#,
    );

    let injection = format!(
        "<style id=\"chronos-focus-css\" nonce=\"{nonce}\">{initial_css}</style><script nonce=\"{nonce}\">{runtime_js}</script>"
    );

    if let Some(pos) = find_head_close_pos(html) {
        let mut out = String::with_capacity(html.len() + injection.len());
        out.push_str(&html[..pos]);
        out.push_str(&injection);
        out.push_str(&html[pos..]);
        out
    } else {
        format!("{injection}{html}")
    }
}

fn find_head_close_pos(html: &str) -> Option<usize> {
    let lower = html.to_ascii_lowercase();
    let mut search_from = 0;
    while let Some(idx) = lower[search_from..].find("<head") {
        let start = search_from + idx;
        let after = start + 5;
        let next_byte = lower.as_bytes().get(after).copied();
        if matches!(next_byte, Some(b'>') | Some(b' ') | Some(b'\t') | Some(b'\r') | Some(b'\n')) {
            if let Some(gt_rel) = lower[after..].find('>') {
                return Some(after + gt_rel + 1);
            }
        }
        search_from = after;
    }
    None
}

pub(crate) struct ParsedHttpHead {
    pub(crate) method_or_status: String,
    pub(crate) target_or_reason: String,
    pub(crate) is_request: bool,
    pub(crate) status_code: u16,
    pub(crate) headers: Vec<(String, String)>,
    pub(crate) body_start: Vec<u8>,
}

pub(crate) async fn read_http_head<R: AsyncRead + Unpin>(stream: &mut R) -> Result<Option<ParsedHttpHead>, String> {
    let mut buf = Vec::with_capacity(4096);
    let mut temp = [0u8; 4096];
    let header_end = loop {
        if let Some(pos) = find_double_crlf(&buf) {
            break pos;
        }
        if buf.len() > 64 * 1024 {
            return Err("HTTP header too large".to_string());
        }
        let n = stream.read(&mut temp).await.map_err(|e| e.to_string())?;
        if n == 0 {
            if buf.is_empty() {
                return Ok(None);
            }
            return Err("Unexpected EOF before header end".to_string());
        }
        buf.extend_from_slice(&temp[..n]);
    };

    let head_bytes = &buf[..header_end];
    let body_start = buf[header_end..].to_vec();
    let mut headers_arr = [httparse::EMPTY_HEADER; 128];

    // Distinguish request vs response lines cleanly.
    if head_bytes.starts_with(b"HTTP/") {
        let mut res = httparse::Response::new(&mut headers_arr);
        match res.parse(head_bytes) {
            Ok(httparse::Status::Complete(_)) => {
                let headers = res
                    .headers
                    .iter()
                    .map(|h| (h.name.to_string(), String::from_utf8_lossy(h.value).to_string()))
                    .collect();
                Ok(Some(ParsedHttpHead {
                    method_or_status: format!("HTTP/1.{}", res.version.unwrap_or(1)),
                    target_or_reason: res.reason.unwrap_or("").to_string(),
                    is_request: false,
                    status_code: res.code.unwrap_or(200),
                    headers,
                    body_start,
                }))
            }
            _ => Err("Invalid HTTP response head".to_string()),
        }
    } else {
        let mut req = httparse::Request::new(&mut headers_arr);
        match req.parse(head_bytes) {
            Ok(httparse::Status::Complete(_)) => {
                let headers = req
                    .headers
                    .iter()
                    .map(|h| (h.name.to_string(), String::from_utf8_lossy(h.value).to_string()))
                    .collect();
                Ok(Some(ParsedHttpHead {
                    method_or_status: req.method.unwrap_or("GET").to_string(),
                    target_or_reason: req.path.unwrap_or("/").to_string(),
                    is_request: true,
                    status_code: 0,
                    headers,
                    body_start,
                }))
            }
            _ => Err("Invalid HTTP request head".to_string()),
        }
    }
}

fn find_double_crlf(data: &[u8]) -> Option<usize> {
    data.windows(4)
        .position(|w| w == b"\r\n\r\n")
        .map(|i| i + 4)
}

pub(crate) fn get_header<'a>(headers: &'a [(String, String)], name: &str) -> Option<&'a str> {
    headers
        .iter()
        .find(|(k, _)| k.eq_ignore_ascii_case(name))
        .map(|(_, v)| v.as_str())
}

pub(crate) async fn read_body_bytes<R: AsyncRead + Unpin>(
    stream: &mut R,
    initial: &[u8],
    headers: &[(String, String)],
    allow_eof: bool,
    max_bytes: usize,
) -> Result<(Vec<u8>, Vec<u8>), String> {
    let is_chunked = get_header(headers, "transfer-encoding")
        .map(|v| v.to_ascii_lowercase().contains("chunked"))
        .unwrap_or(false);
    let content_len: Option<usize> = get_header(headers, "content-length")
        .and_then(|v| v.trim().parse::<usize>().ok());

    if is_chunked {
        return read_chunked_body(stream, initial, max_bytes).await;
    }

    if let Some(len) = content_len {
        if len > max_bytes {
            return Err("Body exceeds cap".to_string());
        }
        let mut out = Vec::with_capacity(len);
        let take = std::cmp::min(len, initial.len());
        out.extend_from_slice(&initial[..take]);
        let leftover = initial[take..].to_vec();
        while out.len() < len {
            let mut chunk = vec![0u8; std::cmp::min(16384, len - out.len())];
            let n = stream.read(&mut chunk).await.map_err(|e| e.to_string())?;
            if n == 0 {
                break;
            }
            out.extend_from_slice(&chunk[..n]);
        }
        return Ok((out, leftover));
    }

    if !allow_eof {
        return Ok((Vec::new(), initial.to_vec()));
    }

    let mut out = Vec::new();
    out.extend_from_slice(initial);
    let mut temp = [0u8; 8192];
    loop {
        let n = match stream.read(&mut temp).await {
            Ok(0) => break,
            Ok(n) => n,
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(e) => return Err(e.to_string()),
        };
        if out.len() + n > max_bytes {
            return Err("EOF body exceeds cap".to_string());
        }
        out.extend_from_slice(&temp[..n]);
    }
    Ok((out, Vec::new()))
}

async fn read_chunked_body<R: AsyncRead + Unpin>(
    stream: &mut R,
    initial: &[u8],
    max_bytes: usize,
) -> Result<(Vec<u8>, Vec<u8>), String> {
    let mut raw = initial.to_vec();
    let mut out = Vec::new();
    let mut temp = [0u8; 8192];

    loop {
        let crlf_pos = loop {
            if let Some(pos) = raw.windows(2).position(|w| w == b"\r\n") {
                break pos;
            }
            let n = stream.read(&mut temp).await.map_err(|e| e.to_string())?;
            if n == 0 {
                return Err("EOF reading chunk size".to_string());
            }
            raw.extend_from_slice(&temp[..n]);
        };

        let size_line = String::from_utf8_lossy(&raw[..crlf_pos]).to_string();
        raw.drain(..crlf_pos + 2);
        let hex_part = size_line.split(';').next().unwrap_or("0").trim();
        let chunk_len = usize::from_str_radix(hex_part, 16)
            .map_err(|_| format!("Invalid chunk hex size: {hex_part}"))?;

        if chunk_len == 0 {
            // Drain trailer CRLF.
            while raw.len() < 2 {
                let n = stream.read(&mut temp).await.map_err(|e| e.to_string())?;
                if n == 0 {
                    break;
                }
                raw.extend_from_slice(&temp[..n]);
            }
            if raw.starts_with(b"\r\n") {
                raw.drain(..2);
            }
            break;
        }

        if out.len() + chunk_len > max_bytes {
            return Err("Chunked body exceeds cap".to_string());
        }
        while raw.len() < chunk_len + 2 {
            let n = stream.read(&mut temp).await.map_err(|e| e.to_string())?;
            if n == 0 {
                return Err("EOF inside chunk data".to_string());
            }
            raw.extend_from_slice(&temp[..n]);
        }
        out.extend_from_slice(&raw[..chunk_len]);
        raw.drain(..chunk_len + 2);
    }

    Ok((out, raw))
}

fn is_navigation_document_request(headers: &[(String, String)]) -> bool {
    if let Some(dest) = get_header(headers, "sec-fetch-dest") {
        return dest.eq_ignore_ascii_case("document");
    }
    get_header(headers, "accept")
        .map(|a| a.to_ascii_lowercase().contains("text/html"))
        .unwrap_or(false)
}

pub(crate) fn update_active_tab_from_proxy(url: &str, title: &str) {
    let clean_url = url.trim();
    if clean_url.is_empty() || clean_url.contains(&crate::profile::api_host()) {
        return;
    }
    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64;

    // Preserve a fresher browser-extension heartbeat (< 1500ms old) if one already exists.
    if let Ok(existing) = std::fs::read_to_string("/tmp/chronos_active_tab.json") {
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&existing) {
            let ts = v.get("timestamp_ms").and_then(|t| t.as_i64()).unwrap_or(0);
            let source = v.get("source").and_then(|s| s.as_str()).unwrap_or("extension");
            if source != "proxy" && (now_ms - ts).abs() < 1500 {
                return;
            }
        }
    }

    crate::local_api::record_focused_browser_tab(clean_url, title, "proxy");
}

pub(crate) fn urlencoding_component(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for b in input.bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~') {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

pub(crate) async fn send_simple_response<W: AsyncWrite + Unpin>(
    stream: &mut W,
    status: &str,
    content_type: &str,
    extra_headers: &[(&str, &str)],
    body: &[u8],
) -> Result<(), String> {
    let mut head = format!(
        "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nCache-Control: no-store\r\nContent-Length: {}\r\n",
        body.len()
    );
    for (k, v) in extra_headers {
        head.push_str(&format!("{k}: {v}\r\n"));
    }
    head.push_str("Connection: close\r\n\r\n");
    stream
        .write_all(head.as_bytes())
        .await
        .map_err(|e| e.to_string())?;
    if !body.is_empty() {
        stream.write_all(body).await.map_err(|e| e.to_string())?;
    }
    stream.flush().await.map_err(|e| e.to_string())?;
    Ok(())
}

async fn connect_upstream_tls(
    state: &ProxyState,
    host: &str,
    port: u16,
) -> Result<tokio_rustls::client::TlsStream<TcpStream>, String> {
    let upstream_addr = state.resolve_upstream_addr(host, port);
    let tcp_up = tokio::time::timeout(
        std::time::Duration::from_secs(12),
        TcpStream::connect(&upstream_addr),
    )
    .await
    .map_err(|_| format!("Upstream connect timeout ({upstream_addr})"))?
    .map_err(|e| format!("Upstream connect failed ({upstream_addr}): {e}"))?;

    let server_name =
        ServerName::try_from(host.to_string()).map_err(|_| format!("Invalid SNI host: {host}"))?;
    tokio::time::timeout(
        std::time::Duration::from_secs(12),
        state.upstream_tls.connect(server_name, tcp_up),
    )
    .await
    .map_err(|_| format!("Upstream TLS handshake timeout ({host})"))?
    .map_err(|e| format!("Upstream TLS handshake failed ({host}): {e}"))
}

enum LazyUpstream<U> {
    Connected(U),
    LazyHttps {
        state: Arc<ProxyState>,
        host: String,
        port: u16,
    },
    None,
}

async fn send_bad_gateway<W: AsyncWrite + Unpin>(client: &mut W, detail: &str) {
    let msg = format!("502 Bad Gateway: {detail}\n");
    let _ = send_simple_response(
        client,
        "502 Bad Gateway",
        "text/plain; charset=utf-8",
        &[],
        msg.as_bytes(),
    )
    .await;
}

async fn handle_client(mut client: TcpStream, state: Arc<ProxyState>) -> Result<(), String> {
    let Some(req) = read_http_head(&mut client).await? else {
        return Ok(());
    };
    if !req.is_request {
        return Ok(());
    }

    if req.method_or_status.eq_ignore_ascii_case("CONNECT") {
        let (host, port) = parse_host_port(&req.target_or_reason, 443);
        let upstream_addr = state.resolve_upstream_addr(&host, port);

        let filters = db::get_focus_filters();
        let rules = engine::get_all_site_rules_status();
        let intercept = {
            let bypass_guard = state.pinned_bypass.read();
            port == 443 && should_intercept_host(&host, &filters, &rules, &bypass_guard)
        };

        if !intercept {
            let Ok(Ok(mut upstream)) = tokio::time::timeout(
                std::time::Duration::from_secs(12),
                TcpStream::connect(&upstream_addr),
            )
            .await
            else {
                send_bad_gateway(&mut client, &format!("Passthrough unreachable: {upstream_addr}")).await;
                return Ok(());
            };
            client
                .write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                .await
                .map_err(|e| e.to_string())?;
            client.flush().await.map_err(|e| e.to_string())?;
            let _ = tokio::io::copy_bidirectional(&mut client, &mut upstream).await;
            return Ok(());
        }

        client
            .write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            .await
            .map_err(|e| e.to_string())?;
        client.flush().await.map_err(|e| e.to_string())?;

        let server_cfg = state.ca.server_config_for_host(&host)?;
        let acceptor = TlsAcceptor::from(server_cfg);
        let client_tls = match acceptor.accept(client).await {
            Ok(s) => s,
            Err(err) => {
                // If an unexpected non-filtered site rejects our CA (e.g. pinning), auto-bypass it cleanly.
                // Never poison core distraction or launcher store domains used by Firefox/browser filtering.
                let host_l = host.to_ascii_lowercase();
                if !is_never_pinned_bypass_host(&host_l) {
                    state.pinned_bypass.write().insert(host_l);
                }
                return Err(format!("Client TLS handshake failed for {host}: {err}"));
            }
        };

        let upstream = LazyUpstream::LazyHttps {
            state: Arc::clone(&state),
            host: host.clone(),
            port,
        };
        return proxy_http_loop_lazy(client_tls, upstream, &host, "https", true).await;
    }

    // Plain HTTP proxy request (e.g. GET http://example.com/... or HEAD https://github.com/...)
    let (is_https, host, port, origin_path) =
        parse_plain_proxy_target(&req.target_or_reason, &req.headers);

    if is_https {
        let mut upstream = match connect_upstream_tls(&state, &host, port).await {
            Ok(u) => u,
            Err(err) => {
                send_bad_gateway(&mut client, &err).await;
                return Ok(());
            }
        };
        if let Err(err) = process_single_http_exchange_conn(
            &mut client,
            &mut upstream,
            req,
            &host,
            "https",
            &origin_path,
        )
        .await
        {
            send_bad_gateway(&mut client, &err).await;
        }
        return Ok(());
    }

    let upstream_addr = state.resolve_upstream_addr(&host, port);
    let mut upstream = match tokio::time::timeout(
        std::time::Duration::from_secs(12),
        TcpStream::connect(&upstream_addr),
    )
    .await
    {
        Ok(Ok(u)) => u,
        Ok(Err(e)) => {
            send_bad_gateway(&mut client, &format!("Plain HTTP connect failed ({upstream_addr}): {e}")).await;
            return Ok(());
        }
        Err(_) => {
            send_bad_gateway(&mut client, &format!("Plain HTTP connect timeout ({upstream_addr})")).await;
            return Ok(());
        }
    };

    if let Err(err) = process_single_http_exchange_conn(
        &mut client,
        &mut upstream,
        req,
        &host,
        "http",
        &origin_path,
    )
    .await
    {
        send_bad_gateway(&mut client, &err).await;
    }
    Ok(())
}

fn parse_plain_proxy_target(
    full_target: &str,
    headers: &[(String, String)],
) -> (bool, String, u16, String) {
    let split_abs = |rest: &str, default_port: u16| -> (String, u16, String) {
        let (hp, p) = match rest.find('/') {
            Some(idx) => (&rest[..idx], &rest[idx..]),
            None => (rest, "/"),
        };
        let (h, po) = parse_host_port(hp, default_port);
        (h, po, p.to_string())
    };
    if full_target.len() >= 8 && full_target[..8].eq_ignore_ascii_case("https://") {
        let (h, po, p) = split_abs(&full_target[8..], 443);
        (true, h, po, p)
    } else if full_target.len() >= 7 && full_target[..7].eq_ignore_ascii_case("http://") {
        let (h, po, p) = split_abs(&full_target[7..], 80);
        (false, h, po, p)
    } else {
        let host_hdr = get_header(headers, "host").unwrap_or("127.0.0.1");
        let (h, po) = parse_host_port(host_hdr, 80);
        (false, h, po, full_target.to_string())
    }
}

fn parse_host_port(authority: &str, default_port: u16) -> (String, u16) {
    let clean = authority.trim();
    if let Some((h, p)) = clean.rsplit_once(':') {
        if let Ok(port) = p.parse::<u16>() {
            return (h.trim_matches(['[', ']']).to_string(), port);
        }
    }
    (clean.trim_matches(['[', ']']).to_string(), default_port)
}

async fn proxy_http_loop_lazy<C>(
    mut client: C,
    mut upstream: LazyUpstream<tokio_rustls::client::TlsStream<TcpStream>>,
    host: &str,
    scheme: &str,
    _close_after: bool,
) -> Result<(), String>
where
    C: AsyncRead + AsyncWrite + Unpin,
{
    loop {
        let Some(req) = read_http_head(&mut client).await? else {
            let _ = client.shutdown().await;
            return Ok(());
        };
        if !req.is_request {
            let _ = client.shutdown().await;
            return Ok(());
        }
        let path = req.target_or_reason.clone();
        let req_body = read_client_request_body(&mut client, &req).await?;

        if let Some(keep) =
            try_handle_local_or_block_exchange(&mut client, &req, &req_body, host, scheme, &path)
                .await?
        {
            if !keep {
                let _ = client.shutdown().await;
                return Ok(());
            }
            continue;
        }

        // Abre upstream apenas quando a requisição precisa ser encaminhada ao servidor de origem.
        let mut up_tls = match std::mem::replace(&mut upstream, LazyUpstream::None) {
            LazyUpstream::Connected(s) => s,
            LazyUpstream::LazyHttps {
                state,
                host: up_host,
                port,
            } => match connect_upstream_tls(&state, &up_host, port).await {
                Ok(s) => s,
                Err(err) => {
                    send_bad_gateway(&mut client, &err).await;
                    let _ = client.shutdown().await;
                    return Ok(());
                }
            },
            LazyUpstream::None => {
                send_bad_gateway(&mut client, "Upstream session closed").await;
                let _ = client.shutdown().await;
                return Ok(());
            }
        };

        let result = forward_http_exchange_on_stream(
            &mut client,
            &mut up_tls,
            req,
            req_body,
            host,
            &path,
        )
        .await;

        match result {
            Ok(false) => {
                let _ = client.shutdown().await;
                let _ = up_tls.shutdown().await;
                return Ok(());
            }
            Ok(true) => {
                upstream = LazyUpstream::Connected(up_tls);
            }
            Err(err) => {
                send_bad_gateway(&mut client, &err).await;
                let _ = client.shutdown().await;
                let _ = up_tls.shutdown().await;
                return Ok(());
            }
        }
    }
}

async fn process_single_http_exchange_conn<C, U>(
    client: &mut C,
    upstream: &mut U,
    req: ParsedHttpHead,
    host: &str,
    scheme: &str,
    origin_path: &str,
) -> Result<(), String>
where
    C: AsyncRead + AsyncWrite + Unpin,
    U: AsyncRead + AsyncWrite + Unpin,
{
    let req_body = read_client_request_body(client, &req).await?;
    if let Some(_keep) =
        try_handle_local_or_block_exchange(client, &req, &req_body, host, scheme, origin_path)
            .await?
    {
        return Ok(());
    }
    forward_http_exchange_on_stream(client, upstream, req, req_body, host, origin_path).await?;
    Ok(())
}

/// Extracts `(app_id, title_hint, url_tags)` when `origin_path` on `host` points to a single
/// game's store/community/guide/discussion/artwork/agecheck page, tag hub, or search query.
#[cfg(test)]
pub(crate) fn extract_single_game_hint_from_url(
    host: &str,
    origin_path: &str,
) -> Option<(Option<i64>, String, Vec<String>)> {
    let clean_host = host.trim().to_ascii_lowercase();
    let is_launcher_host = LAUNCHER_STORE_DOMAINS
        .iter()
        .any(|s| host_matches_suffix(&clean_host, s));
    if !is_launcher_host {
        return None;
    }

    steam_api::extract_launcher_url_hint(&clean_host, origin_path)
        .map(|(app_id, title_hint, url_tags, _is_search)| (app_id, title_hint, url_tags))
}

async fn check_launcher_page_block(
    host: &str,
    origin_path: &str,
    filters: &db::FocusFilters,
) -> Option<(String, String)> {
    if !filters.launcher_filter_enabled
        || (filters.launcher_blocked_tags.is_empty() && filters.launcher_blocked_names.is_empty())
    {
        return None;
    }
    let clean_host = host.trim().to_ascii_lowercase();
    if !LAUNCHER_STORE_DOMAINS
        .iter()
        .any(|s| host_matches_suffix(&clean_host, s))
    {
        return None;
    }
    let (app_id, title_hint, mut url_tags, is_search) =
        steam_api::extract_launcher_url_hint(&clean_host, origin_path)?;

    if is_search && !title_hint.is_empty() && !steam_api::is_generic_storefront_title(&title_hint) {
        url_tags.push(title_hint.clone());
    }

    if let Some((kind, term)) =
        steam_api::match_game_against_filters(&title_hint, &url_tags, None, filters)
    {
        let display = if !title_hint.is_empty() {
            title_hint
        } else if !url_tags.is_empty() {
            url_tags[0].clone()
        } else {
            host.to_string()
        };
        let reason = if kind == "NOME" {
            format!("Bloqueado pelo filtro de nome \"{term}\"")
        } else {
            let (_, steam_lang) = db::get_steam_language_and_country();
            let disp = steam_api::display_name_for_canonical_tag(&term, steam_lang);
            format!("Bloqueado pela tag \"{disp}\"")
        };
        return Some((display, reason));
    }

    // For search queries (?term=...), avoid false-blocking unrelated searches via #1 storesearch hit;
    // cards inside search results are still filtered individually via DOM + /api/launchers/resolve.
    if app_id.is_none() && (is_search || title_hint.is_empty() || steam_api::is_generic_storefront_title(&title_hint)) {
        return None;
    }

    let meta = tokio::time::timeout(
        std::time::Duration::from_millis(3500),
        steam_api::resolve_game_metadata_async(app_id, &title_hint),
    )
    .await
    .ok()
    .flatten();
    if let Some((kind, term)) =
        steam_api::match_game_against_filters(&title_hint, &url_tags, meta.as_ref(), filters)
    {
        let display = meta
            .as_ref()
            .map(|m| m.title.clone())
            .filter(|t| !t.is_empty())
            .or_else(|| (!title_hint.is_empty()).then_some(title_hint))
            .unwrap_or_else(|| host.to_string());
        let reason = if kind == "NOME" {
            format!("Bloqueado pelo filtro de nome \"{term}\"")
        } else {
            let (_, steam_lang) = db::get_steam_language_and_country();
            let disp = steam_api::display_name_for_canonical_tag(&term, steam_lang);
            let src_label = meta
                .as_ref()
                .map(|m| steam_api::source_display_label(&m.source))
                .unwrap_or("Steam API");
            format!("Bloqueado pela tag \"{disp}\" ({src_label})")
        };
        return Some((display, reason));
    }

    None
}

async fn read_client_request_body<C: AsyncRead + Unpin>(
    client: &mut C,
    req: &ParsedHttpHead,
) -> Result<Vec<u8>, String> {
    if !req.body_start.is_empty()
        || get_header(&req.headers, "content-length").is_some()
        || get_header(&req.headers, "transfer-encoding")
            .map(|v| v.to_ascii_lowercase().contains("chunked"))
            .unwrap_or(false)
    {
        let (body, _) =
            read_body_bytes(client, &req.body_start, &req.headers, false, 16 * 1024 * 1024).await?;
        Ok(body)
    } else {
        Ok(Vec::new())
    }
}

/// Trata rotas virtuais `/__chronos_api__/*`, redirecionamentos de foco e páginas bloqueadas.
/// Retorna `Ok(Some(false))` quando a resposta já foi enviada ao cliente e `Ok(None)` para encaminhar upstream.
async fn try_handle_local_or_block_exchange<C: AsyncRead + AsyncWrite + Unpin>(
    client: &mut C,
    req: &ParsedHttpHead,
    req_body: &[u8],
    host: &str,
    scheme: &str,
    origin_path: &str,
) -> Result<Option<bool>, String> {

    // 1. Virtual Same-Origin API: focus filters GET/POST sync
    if origin_path.starts_with("/__chronos_api__/focus-filters") {
        if req.method_or_status.eq_ignore_ascii_case("POST") {
            if let Ok(serde_json::Value::Object(obj)) =
                serde_json::from_slice::<serde_json::Value>(&req_body)
            {
                if let Some(lang_val) = obj
                    .get("primaryLanguage")
                    .or_else(|| obj.get("language"))
                    .and_then(|v| v.as_str())
                {
                    let _ = db::set_primary_language(lang_val);
                }
                let (ok, anti_cheat_locked, message, updated) =
                    crate::local_api::apply_focus_filters_update(&obj);
                let status = if anti_cheat_locked {
                    "403 Forbidden"
                } else {
                    "200 OK"
                };
                let mut payload = crate::local_api::build_focus_filters_envelope(&updated);
                if let Some(map) = payload.as_object_mut() {
                    map.insert("success".to_string(), serde_json::json!(ok));
                    map.insert(
                        "antiCheatLocked".to_string(),
                        serde_json::json!(anti_cheat_locked),
                    );
                    map.insert("message".to_string(), serde_json::json!(message));
                }
                send_simple_response(
                    client,
                    status,
                    "application/json; charset=utf-8",
                    &[],
                    payload.to_string().as_bytes(),
                )
                .await?;
                return Ok(Some(false));
            }
            send_simple_response(
                client,
                "400 Bad Request",
                "application/json; charset=utf-8",
                &[],
                br#"{"success":false,"error":"Invalid JSON"}"#,
            )
            .await?;
            return Ok(Some(false));
        }

        let filters = db::get_focus_filters();
        let mut payload = crate::local_api::build_focus_filters_envelope(&filters);
        if let Some(map) = payload.as_object_mut() {
            map.insert("success".to_string(), serde_json::json!(true));
        }
        send_simple_response(
            client,
            "200 OK",
            "application/json; charset=utf-8",
            &[],
            payload.to_string().as_bytes(),
        )
        .await?;
        return Ok(Some(false));
    }

    if origin_path.starts_with("/__chronos_api__/events") {
        crate::local_api::write_sse_stream(client).await?;
        return Ok(Some(false));
    }

    // 1a0. Virtual Same-Origin API: YouTube video type classification ("mostrar apenas")
    if origin_path.starts_with("/__chronos_api__/youtube/classify") {
        let payload = crate::youtube::handle_classify_payload(req_body).await;
        send_simple_response(
            client,
            "200 OK",
            "application/json; charset=utf-8",
            &[],
            payload.to_string().as_bytes(),
        )
        .await?;
        return Ok(Some(false));
    }

    // 1a. Virtual Same-Origin API: Steam API game metadata & tag resolution + autocomplete + blocked page
    if origin_path.starts_with("/__chronos_api__/launchers/resolve") {
        match crate::local_api::handle_launchers_resolve_payload(req_body).await {
            Ok(payload) => {
                send_simple_response(
                    client,
                    "200 OK",
                    "application/json; charset=utf-8",
                    &[],
                    payload.to_string().as_bytes(),
                )
                .await?;
            }
            Err(_) => {
                send_simple_response(
                    client,
                    "400 Bad Request",
                    "application/json; charset=utf-8",
                    &[],
                    br#"{"success":false,"error":"Invalid JSON"}"#,
                )
                .await?;
            }
        }
        return Ok(Some(false));
    }

    if origin_path.starts_with("/__chronos_api__/launchers/tags") {
        let (_, query) = crate::local_api::split_path_and_query(origin_path);
        let payload = crate::local_api::handle_launchers_tags_payload_for_lang(
            query.get("lang").map(String::as_str),
        )
        .await;
        send_simple_response(
            client,
            "200 OK",
            "application/json; charset=utf-8",
            &[],
            payload.to_string().as_bytes(),
        )
        .await?;
        return Ok(Some(false));
    }

    if origin_path.starts_with("/__chronos_api__/launchers/autocomplete") {
        let (_, query) = crate::local_api::split_path_and_query(origin_path);
        let kind = query.get("kind").map(String::as_str).unwrap_or("tag");
        let q = query.get("q").map(String::as_str).unwrap_or("");
        let req_lang = query.get("lang").map(String::as_str);
        let payload =
            crate::local_api::handle_launchers_autocomplete_payload(kind, q, req_lang).await;
        send_simple_response(
            client,
            "200 OK",
            "application/json; charset=utf-8",
            &[],
            payload.to_string().as_bytes(),
        )
        .await?;
        return Ok(Some(false));
    }

    if origin_path.starts_with("/__chronos_api__/launchers/blocked") {
        let (_, query) = crate::local_api::split_path_and_query(origin_path);
        let site = query
            .get("site")
            .map(String::as_str)
            .filter(|s| !s.is_empty())
            .unwrap_or("Jogo / Conteúdo Filtrado");
        let reason = query
            .get("reason")
            .map(String::as_str)
            .filter(|s| !s.is_empty())
            .unwrap_or("Bloqueado pelos filtros de Launchers & Jogos");
        let orig_url = query.get("url").map(String::as_str).unwrap_or("");
        let html = crate::local_api::render_launcher_blocked_html(site, reason, orig_url, true);
        send_simple_response(
            client,
            "200 OK",
            "text/html; charset=utf-8",
            &[],
            html.as_bytes(),
        )
        .await?;
        return Ok(Some(false));
    }

    // 1b. Virtual Same-Origin API: live status & site quotas for the inline HUD panel
    if origin_path.starts_with("/__chronos_api__/status") {
        let payload = crate::local_api::build_status_payload();
        send_simple_response(
            client,
            "200 OK",
            "application/json; charset=utf-8",
            &[],
            payload.to_string().as_bytes(),
        )
        .await?;
        return Ok(Some(false));
    }

    // 2. Virtual Same-Origin API: tab heartbeat + rule check
    if origin_path.starts_with("/__chronos_api__/heartbeat") {
        if let Ok(v) = serde_json::from_slice::<serde_json::Value>(req_body) {
            let url = v.get("url").and_then(|s| s.as_str()).unwrap_or("");
            let title = v.get("title").and_then(|s| s.as_str()).unwrap_or("");
            update_active_tab_from_proxy(url, title);
            crate::youtube::warm_classification(url).await;
            if let Some(hit) = crate::adult::check(url, title) {
                let blocked_url = format!(
                    "{}/blocked?url={}&entityId=adult_filter&name={}&reason={}",
                    crate::profile::api_base(),
                    urlencoding_component(url),
                    urlencoding_component("Conteúdo adulto"),
                    urlencoding_component(&crate::adult::blocked_reason(&hit))
                );
                let json = serde_json::json!({"blocked": true, "entityId": "adult_filter", "blockedUrl": blocked_url});
                send_simple_response(client, "200 OK", "application/json; charset=utf-8", &[], json.to_string().as_bytes())
                    .await?;
                return Ok(Some(false));
            }
            let rules = engine::get_all_site_rules_status();
            if let Some(blocked) = find_blocked_rule(url, &rules) {
                let blocked_url = format!(
                    "{}/blocked?url={}&entityId={}&name={}",
                    crate::profile::api_base(),
                    urlencoding_component(url),
                    urlencoding_component(&blocked.entity_id),
                    urlencoding_component(&blocked.display_name)
                );
                let json = serde_json::json!({
                    "blocked": true,
                    "entityId": blocked.entity_id,
                    "blockedUrl": blocked_url
                });
                send_simple_response(
                    client,
                    "200 OK",
                    "application/json; charset=utf-8",
                    &[],
                    json.to_string().as_bytes(),
                )
                .await?;
                return Ok(Some(false));
            }
            if let Some(matched) = find_matching_rule(url, title, &rules) {
                let json = serde_json::json!({
                    "blocked": false,
                    "matched": true,
                    "rule": {
                        "entityId": matched.entity_id,
                        "displayName": matched.display_name,
                        "remainingSeconds": matched.remaining_seconds,
                        "consumedSeconds": matched.consumed_seconds,
                        "dailyQuotaSeconds": matched.daily_quota_seconds,
                        "emergencyTokensRemaining": matched.emergency_tokens_remaining,
                        "targetType": matched.target_type,
                        "pattern": matched.pattern,
                        "isBlocked": matched.is_blocked
                    }
                });
                send_simple_response(
                    client,
                    "200 OK",
                    "application/json; charset=utf-8",
                    &[],
                    json.to_string().as_bytes(),
                )
                .await?;
                return Ok(Some(false));
            }
        }
        send_simple_response(
            client,
            "200 OK",
            "application/json; charset=utf-8",
            &[],
            br#"{"blocked":false,"matched":false}"#,
        )
        .await?;
        return Ok(Some(false));
    }

    let full_url = format!("{scheme}://{host}{origin_path}");
    let is_doc = is_navigation_document_request(&req.headers);

    if is_doc {
        crate::youtube::warm_classification(&full_url).await;
        if let Some(hit) = crate::adult::check(&full_url, "") {
            let location = format!(
                "{}/blocked?url={}&entityId=adult_filter&name={}&reason={}",
                    crate::profile::api_base(),
                urlencoding_component(&full_url),
                urlencoding_component("Conteúdo adulto"),
                urlencoding_component(&crate::adult::blocked_reason(&hit))
            );
            send_simple_response(client, "302 Found", "text/plain", &[("Location", &location)], b"").await?;
            return Ok(Some(false));
        }
        if crate::adult::settings().safe_search {
            if let Some(safe) = crate::adult::safe_search_redirect(&full_url) {
                if crate::adult::settings().enabled {
                    send_simple_response(client, "302 Found", "text/plain", &[("Location", &safe)], b"").await?;
                    return Ok(Some(false));
                }
            }
        }
        let rules = engine::get_all_site_rules_status();
        if let Some(blocked) = find_blocked_rule(&full_url, &rules) {
            let location = format!(
                "{}/blocked?url={}&entityId={}&name={}",
                    crate::profile::api_base(),
                urlencoding_component(&full_url),
                urlencoding_component(&blocked.entity_id),
                urlencoding_component(&blocked.display_name)
            );
            send_simple_response(client, "302 Found", "text/plain", &[("Location", &location)], b"")
                .await?;
            return Ok(Some(false));
        }

        let filters = db::get_focus_filters();
        if let Some(redir) = check_focus_redirect(host, origin_path, &filters) {
            if redir != full_url {
                send_simple_response(client, "302 Found", "text/plain", &[("Location", &redir)], b"")
                    .await?;
                return Ok(Some(false));
            }
        }

        if let Some((title, reason)) =
            check_launcher_page_block(host, origin_path, &filters).await
        {
            let html = crate::local_api::render_launcher_blocked_html(&title, &reason, &full_url, true);
            send_simple_response(
                client,
                "200 OK",
                "text/html; charset=utf-8",
                &[],
                html.as_bytes(),
            )
            .await?;
            return Ok(Some(false));
        }

        update_active_tab_from_proxy(&full_url, host);
    }

    Ok(None)
}

fn decode_body_bytes(raw_body: Vec<u8>, encoding: &str) -> Vec<u8> {
    let mut out = Vec::new();
    if encoding.contains("gzip") {
        GzDecoder::new(&raw_body[..]).read_to_end(&mut out).unwrap_or(0);
    } else if encoding.contains("deflate") {
        DeflateDecoder::new(&raw_body[..]).read_to_end(&mut out).unwrap_or(0);
    } else {
        return raw_body;
    }
    if out.is_empty() {
        raw_body
    } else {
        out
    }
}

/// `GET https://lutris.net/api/games?search=...` is what the Lutris desktop client uses
/// for its online game search (`lutris/api.py::search_games`).
fn is_lutris_api_games_request(host: &str, origin_path: &str) -> bool {
    let h = host.trim().to_ascii_lowercase();
    if !host_matches_suffix(&h, "lutris.net") {
        return false;
    }
    let path_only = origin_path.split(['?', '#']).next().unwrap_or("");
    let p = path_only.trim_end_matches('/');
    p.eq_ignore_ascii_case("/api/games")
}

const LUTRIS_API_RESOLVE_BUDGET_MS: u64 = 2500;

/// Removes Lutris API search results whose title or Steam metadata match the active
/// launcher filters. Unknown Steam AppIDs are batch-resolved within a short budget;
/// anything still unresolved is resolved in the background for the next search.
/// Returns `None` when the payload is not a Lutris games listing or nothing changed.
pub(crate) async fn filter_lutris_api_games_json(
    body: &[u8],
    filters: &db::FocusFilters,
) -> Option<Vec<u8>> {
    if !filters.launcher_filter_enabled
        || (filters.launcher_blocked_tags.is_empty() && filters.launcher_blocked_names.is_empty())
    {
        return None;
    }
    let mut parsed: serde_json::Value = serde_json::from_slice(body).ok()?;
    let results = parsed.get_mut("results")?.as_array_mut()?;

    let steam_appid_of = |item: &serde_json::Value| -> Option<i64> {
        item.get("provider_games")?
            .as_array()?
            .iter()
            .filter(|pg| {
                pg.get("service")
                    .and_then(|s| s.as_str())
                    .is_some_and(|s| s.eq_ignore_ascii_case("steam"))
            })
            .find_map(|pg| {
                pg.get("slug")
                    .and_then(|s| s.as_str())
                    .and_then(|s| s.trim().parse::<i64>().ok())
                    .filter(|&n| n > 0)
            })
    };

    let entries: Vec<(String, Option<i64>)> = results
        .iter()
        .map(|item| {
            let name = item
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim()
                .to_string();
            (name, steam_appid_of(item))
        })
        .collect();

    let mut metas: Vec<Option<steam_api::GameMetadata>> = entries
        .iter()
        .map(|(name, app_id)| {
            steam_api::lookup_cached_only(*app_id, name)
                .filter(|m| !m.all_filter_terms().is_empty() && !steam_api::is_dom_learned_only(m))
        })
        .collect();

    let missing_ids: Vec<i64> = entries
        .iter()
        .zip(&metas)
        .filter(|(_, m)| m.is_none())
        .filter_map(|((_, id), _)| *id)
        .collect();
    if !missing_ids.is_empty() {
        if let Ok(batch) = tokio::time::timeout(
            std::time::Duration::from_millis(LUTRIS_API_RESOLVE_BUDGET_MS),
            steam_api::fetch_batch_by_appids_async(&missing_ids),
        )
        .await
        {
            for ((_, id), meta) in entries.iter().zip(metas.iter_mut()) {
                if meta.is_none() {
                    if let Some(found) = id.and_then(|i| batch.get(&i).cloned()) {
                        *meta = Some(found);
                    }
                }
            }
        }
    }

    for ((name, app_id), meta) in entries.iter().zip(&metas) {
        if meta.is_none() && !name.is_empty() && !steam_api::is_generic_storefront_title(name) {
            let (n, id) = (name.clone(), *app_id);
            tokio::spawn(async move {
                let _ = steam_api::resolve_game_metadata_async(id, &n).await;
            });
        }
    }

    let before = results.len();
    let mut idx = 0usize;
    results.retain(|_| {
        let (name, _) = &entries[idx];
        let keep = steam_api::match_game_against_filters(name, &[], metas[idx].as_ref(), filters).is_none();
        idx += 1;
        keep
    });
    let removed = before - results.len();
    if removed == 0 {
        return None;
    }
    if let Some(count) = parsed.get("count").and_then(|c| c.as_i64()) {
        parsed["count"] = serde_json::json!((count - removed as i64).max(0));
    }
    serde_json::to_vec(&parsed).ok()
}

async fn forward_http_exchange_on_stream<C, U>(
    client: &mut C,
    upstream: &mut U,
    req: ParsedHttpHead,
    req_body: Vec<u8>,
    host: &str,
    origin_path: &str,
) -> Result<bool, String>
where
    C: AsyncRead + AsyncWrite + Unpin,
    U: AsyncRead + AsyncWrite + Unpin,
{
    let is_upgrade = get_header(&req.headers, "upgrade").is_some();

    // 3. Forward request upstream
    let mut up_req = format!("{} {} HTTP/1.1\r\n", req.method_or_status, origin_path);
    let mut has_host = false;
    for (k, v) in &req.headers {
        let kl = k.to_ascii_lowercase();
        if kl == "proxy-connection"
            || kl == "accept-encoding"
            || kl == "if-none-match"
            || kl == "if-modified-since"
            || kl == "content-length"
            || kl == "transfer-encoding"
            || kl == "expect"
            || (kl == "connection" && !is_upgrade)
        {
            continue;
        }
        if kl == "host" {
            has_host = true;
        }
        up_req.push_str(&format!("{k}: {v}\r\n"));
    }
    if !has_host {
        up_req.push_str(&format!("Host: {host}\r\n"));
    }
    up_req.push_str("Accept-Encoding: gzip, deflate, identity\r\n");
    if !req_body.is_empty()
        || matches!(
            req.method_or_status.to_ascii_uppercase().as_str(),
            "POST" | "PUT" | "PATCH"
        )
    {
        up_req.push_str(&format!("Content-Length: {}\r\n", req_body.len()));
    }
    if !is_upgrade {
        up_req.push_str("Connection: close\r\n");
    }
    up_req.push_str("\r\n");

    upstream
        .write_all(up_req.as_bytes())
        .await
        .map_err(|e| format!("Upstream write error: {e}"))?;
    if !req_body.is_empty() {
        upstream
            .write_all(&req_body)
            .await
            .map_err(|e| format!("Upstream body write error: {e}"))?;
    }
    upstream
        .flush()
        .await
        .map_err(|e| format!("Upstream flush error: {e}"))?;

    // 4. Read upstream HTTP response head (nunca fecha em silêncio com 0 bytes!)
    let res = read_http_head(upstream)
        .await
        .map_err(|e| format!("Upstream response read error: {e}"))?
        .ok_or_else(|| "Upstream closed connection without response (prevents ERR_EMPTY_RESPONSE)".to_string())?;

    if res.status_code == 101 {
        let mut raw_head = format!(
            "{} {} {}\r\n",
            res.method_or_status, res.status_code, res.target_or_reason
        );
        for (k, v) in &res.headers {
            raw_head.push_str(&format!("{k}: {v}\r\n"));
        }
        raw_head.push_str("\r\n");
        client
            .write_all(raw_head.as_bytes())
            .await
            .map_err(|e| e.to_string())?;
        if !res.body_start.is_empty() {
            client
                .write_all(&res.body_start)
                .await
                .map_err(|e| e.to_string())?;
        }
        client.flush().await.map_err(|e| e.to_string())?;
        let _ = tokio::io::copy_bidirectional(client, upstream).await;
        return Ok(false);
    }

    let is_head_req = req.method_or_status.eq_ignore_ascii_case("HEAD");
    let has_no_body = is_head_req
        || res.status_code == 204
        || res.status_code == 304
        || (res.status_code >= 100 && res.status_code < 200);

    let content_type = get_header(&res.headers, "content-type")
        .unwrap_or("")
        .to_ascii_lowercase();
    let is_html = res.status_code == 200 && !is_head_req && content_type.contains("text/html");
    let is_lutris_api_games = res.status_code == 200
        && !is_head_req
        && content_type.contains("json")
        && is_lutris_api_games_request(host, origin_path);

    if is_lutris_api_games {
        let (raw_body, _) =
            read_body_bytes(upstream, &res.body_start, &res.headers, true, MAX_HTML_BODY_BYTES).await?;
        let encoding = get_header(&res.headers, "content-encoding")
            .unwrap_or("")
            .to_ascii_lowercase();
        let decoded = decode_body_bytes(raw_body, &encoding);
        let filters = db::get_focus_filters();
        let out_body = filter_lutris_api_games_json(&decoded, &filters)
            .await
            .unwrap_or(decoded);

        let mut out_head = format!(
            "{} {} {}\r\n",
            res.method_or_status, res.status_code, res.target_or_reason
        );
        for (k, v) in &res.headers {
            let kl = k.to_ascii_lowercase();
            if matches!(
                kl.as_str(),
                "content-length" | "content-encoding" | "transfer-encoding" | "connection" | "etag" | "alt-svc"
            ) {
                continue;
            }
            out_head.push_str(&format!("{k}: {v}\r\n"));
        }
        out_head.push_str(&format!("Content-Length: {}\r\n", out_body.len()));
        out_head.push_str("Connection: close\r\n\r\n");
        client
            .write_all(out_head.as_bytes())
            .await
            .map_err(|e| e.to_string())?;
        client.write_all(&out_body).await.map_err(|e| e.to_string())?;
        client.flush().await.map_err(|e| e.to_string())?;
        return Ok(false);
    }

    if has_no_body || !is_html {
        // Stream non-HTML responses untouched so videos/binaries never buffer needlessly.
        let mut raw_head = format!(
            "{} {} {}\r\n",
            res.method_or_status, res.status_code, res.target_or_reason
        );
        for (k, v) in &res.headers {
            if k.eq_ignore_ascii_case("connection") || k.eq_ignore_ascii_case("alt-svc") {
                continue;
            }
            raw_head.push_str(&format!("{k}: {v}\r\n"));
        }
        raw_head.push_str("Connection: close\r\n\r\n");
        client
            .write_all(raw_head.as_bytes())
            .await
            .map_err(|e| e.to_string())?;
        if !has_no_body {
            if !res.body_start.is_empty() {
                client
                    .write_all(&res.body_start)
                    .await
                    .map_err(|e| e.to_string())?;
            }
            let _ = tokio::io::copy(upstream, client).await;
        }
        client.flush().await.map_err(|e| e.to_string())?;
        return Ok(false);
    }

    // 5. Buffer, decode, and inject HTML response
    let (raw_body, _) =
        read_body_bytes(upstream, &res.body_start, &res.headers, true, MAX_HTML_BODY_BYTES).await?;
    let encoding = get_header(&res.headers, "content-encoding")
        .unwrap_or("")
        .to_ascii_lowercase();
    let decoded_bytes = decode_body_bytes(raw_body, &encoding);

    let html_str = String::from_utf8_lossy(&decoded_bytes);
    let filters = db::get_focus_filters();
    let nonce = generate_nonce();
    // Only full documents get the runtime: AJAX HTML fragments (Steam store search,
    // infinite scroll) are executed by jQuery and would each mount another pill.
    let injected_html = if is_full_html_document(&html_str) {
        inject_html(&html_str, host, &filters, &nonce)
    } else {
        html_str.to_string()
    };
    let injected_bytes = injected_html.as_bytes();

    let mut out_head = format!(
        "{} {} {}\r\n",
        res.method_or_status, res.status_code, res.target_or_reason
    );
    for (k, v) in &res.headers {
        let kl = k.to_ascii_lowercase();
        if kl == "content-length"
            || kl == "content-encoding"
            || kl == "transfer-encoding"
            || kl == "connection"
            || kl == "etag"
            || kl == "cache-control"
            || kl == "alt-svc"
        {
            continue;
        }
        if kl == "content-security-policy" {
            let patched = patch_csp_header(v, &nonce);
            out_head.push_str(&format!("{k}: {patched}\r\n"));
            continue;
        }
        out_head.push_str(&format!("{k}: {v}\r\n"));
    }
    out_head.push_str("Cache-Control: no-store, max-age=0\r\n");
    out_head.push_str(&format!("Content-Length: {}\r\n", injected_bytes.len()));
    out_head.push_str("Connection: close\r\n\r\n");

    client
        .write_all(out_head.as_bytes())
        .await
        .map_err(|e| e.to_string())?;
    client
        .write_all(injected_bytes)
        .await
        .map_err(|e| e.to_string())?;
    client.flush().await.map_err(|e| e.to_string())?;
    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    #[test]
    fn test_ca_creation_and_leaf_minting() {
        let temp_dir = std::env::temp_dir().join(format!("chronos_ca_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&temp_dir);

        let ca = CertAuthority::load_or_create(&temp_dir).expect("CA creation failed");
        assert!(temp_dir.join("chronos-proxy-ca.crt").exists());
        assert!(temp_dir.join("chronos-proxy-ca.key").exists());

        // Verify persistence reloads cleanly
        let ca2 = CertAuthority::load_or_create(&temp_dir).expect("CA reload failed");
        assert_eq!(ca.ca_cert_der, ca2.ca_cert_der);

        // Mint leaf cert for YouTube
        let cfg = ca2
            .server_config_for_host("www.youtube.com")
            .expect("Leaf server config failed");
        assert_eq!(cfg.alpn_protocols, vec![b"http/1.1".to_vec()]);

        let _ = std::fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn test_runtime_injected_only_into_full_documents_once() {
        assert!(is_full_html_document("<!DOCTYPE html><html><body>x</body></html>"));
        assert!(is_full_html_document("  <html lang=pt>"));
        assert!(!is_full_html_document("<div class=\"search_result_row\"><script>x()</script></div>"));
        let f = db::FocusFilters::default();
        let out = inject_html("<html><head></head><body></body></html>", "store.steampowered.com", &f, "n1");
        assert!(out.contains("window.__chronosProxyRuntime"), "runtime guards against running twice");
    }

    #[test]
    fn test_maps_and_api_hosts_pass_through_even_with_global_detox() {
        let filters = db::FocusFilters { global_block_notifications: true, ..Default::default() };
        let empty = HashSet::new();
        for h in ["streetviewpixels-pa.googleapis.com", "maps.googleapis.com", "lh3.googleusercontent.com", "khms0.google.com", "mt1.google.com"] {
            assert!(!should_intercept_host(h, &filters, &[], &empty), "{h} must pass through");
        }
        assert!(should_intercept_host("example.com", &filters, &[], &empty), "pages still intercepted for detox");
        for h in ["www.google.com", "www.google.com.br", "maps.google.com", "google.de"] {
            assert!(!should_intercept_host(h, &filters, &[], &empty), "{h}: detox alone must not intercept Google");
        }
    }

    #[test]
    fn test_selective_interception_rules() {
        let mut f = db::FocusFilters::default();
        let pinned = HashSet::new();
        let rules = vec![engine::SiteStatusItem {
            entity_id: "custom-site".to_string(),
            display_name: "Custom Site".to_string(),
            target_type: "SITE".to_string(),
            pattern: "news.ycombinator.com".to_string(),
            daily_quota_seconds: 600,
            consumed_seconds: 0,
            remaining_seconds: 600,
            is_blocked: false,
            emergency_tokens_remaining: 1,
            is_weekend: false,
            weekend_quota_seconds: None,
        }];

        // Core distraction & rule-matched domains intercepted even with global detox OFF
        assert!(should_intercept_host("www.youtube.com", &f, &rules, &pinned));
        assert!(should_intercept_host("news.ycombinator.com", &f, &rules, &pinned));

        // Video CDNs / Mozilla / Auth always bypassed
        assert!(!should_intercept_host("rr2---sn-4g5e.googlevideo.com", &f, &rules, &pinned));
        assert!(!should_intercept_host("addons.mozilla.org", &f, &rules, &pinned));
        assert!(!should_intercept_host("accounts.google.com", &f, &rules, &pinned));

        // Random site NOT intercepted when Global Detox is OFF
        assert!(!should_intercept_host("example.org", &f, &rules, &pinned));

        // Random site intercepted when global grayscale is ON (while CDNs stay bypassed)
        f.global_grayscale = true;
        assert!(should_intercept_host("example.org", &f, &rules, &pinned));
        assert!(!should_intercept_host("i.ytimg.com", &f, &rules, &pinned));

        // Launcher store domains intercepted only when launcher filters are enabled + have rules
        assert!(!should_intercept_host("store.steampowered.com", &db::FocusFilters::default(), &[], &pinned));
        let mut lf = db::FocusFilters::default();
        lf.launcher_filter_enabled = true;
        lf.launcher_blocked_tags = vec!["RPG".to_string()];
        assert!(should_intercept_host("store.steampowered.com", &lf, &[], &pinned));
        assert!(should_intercept_host("steamcommunity.com", &lf, &[], &pinned));
        assert!(should_intercept_host("store.epicgames.com", &lf, &[], &pinned));
        assert!(should_intercept_host("www.gog.com", &lf, &[], &pinned));
        assert!(should_intercept_host("supergiant.itch.io", &lf, &[], &pinned));
        assert!(!should_intercept_host("login.steampowered.com", &lf, &[], &pinned));
        assert!(!should_intercept_host("shared.fastly.steamstatic.com", &lf, &[], &pinned));

        // URL hints for Steam store/guides/discussions/artwork + Epic/GOG/Itch + search
        assert_eq!(
            extract_single_game_hint_from_url("store.steampowered.com", "/app/730/CounterStrike_2/"),
            Some((Some(730), "CounterStrike 2".to_string(), vec![]))
        );
        assert_eq!(
            extract_single_game_hint_from_url("steamcommunity.com", "/app/730/discussions/"),
            Some((Some(730), "".to_string(), vec![]))
        );
        assert_eq!(
            extract_single_game_hint_from_url("steamcommunity.com", "/sharedfiles/filedetails/?id=1&appid=570"),
            Some((Some(570), "".to_string(), vec![]))
        );
        assert_eq!(
            extract_single_game_hint_from_url("store.epicgames.com", "/en-US/p/hades"),
            Some((None, "hades".to_string(), vec![]))
        );
        assert_eq!(
            extract_single_game_hint_from_url("www.gog.com", "/en/game/hollow_knight"),
            Some((None, "hollow knight".to_string(), vec![]))
        );
        assert_eq!(
            extract_single_game_hint_from_url(
                "store.steampowered.com",
                "/login/?redir=app%2F339800%2FHuniePop%2F&snr=1"
            ),
            Some((Some(339800), "HuniePop".to_string(), vec![]))
        );
        assert!(is_never_pinned_bypass_host("store.steampowered.com"));
        assert!(is_never_pinned_bypass_host("steamcommunity.com"));
        assert!(is_never_pinned_bypass_host("www.youtube.com"));
        assert!(!is_never_pinned_bypass_host("example.org"));

        let tag_page_hit = steam_api::run_async_blocking(async {
            let mut f = db::FocusFilters::default();
            f.launcher_filter_enabled = true;
            f.launcher_blocked_tags = vec!["NSFW".to_string()];
            check_launcher_page_block("store.steampowered.com", "/tags/en/Hentai/", &f).await
        });
        assert!(tag_page_hit.is_some(), "Tag hub /tags/en/Hentai/ must be blocked when NSFW is blocked");

        let search_tag_hit = steam_api::run_async_blocking(async {
            let mut f = db::FocusFilters::default();
            f.launcher_filter_enabled = true;
            f.launcher_blocked_tags = vec!["Hentai".to_string()];
            check_launcher_page_block("store.steampowered.com", "/search/?tags=9130", &f).await
        });
        assert!(search_tag_hit.is_some(), "Steam /search/?tags=9130 must be blocked for Hentai tag");
    }

    #[test]
    fn test_csp_patching_and_html_injection() {
        let csp = "default-src 'self'; script-src 'strict-dynamic' https://www.youtube.com; style-src https://s.ytimg.com; connect-src https://api.youtube.com";
        let patched = patch_csp_header(csp, "chronos_test123");
        assert!(patched.contains("'nonce-chronos_test123'"));
        assert!(patched.contains("connect-src https://api.youtube.com 'self'"));

        // Must NOT inject nonce into default-src/style-src when 'unsafe-inline' is active without nonce
        let csp_inline_styles = "default-src 'self' 'unsafe-inline'; script-src 'self'";
        let patched_inline = patch_csp_header(csp_inline_styles, "chronos_test123");
        assert!(
            patched_inline.contains("default-src 'self' 'unsafe-inline';"),
            "default-src was unexpectedly altered: {patched_inline}"
        );
        assert!(
            patched_inline.contains("script-src 'self' 'nonce-chronos_test123'"),
            "script-src missing nonce: {patched_inline}"
        );

        let csp_yt_style = "default-src 'self'; style-src 'unsafe-inline' https://s.ytimg.com";
        let patched_yt = patch_csp_header(csp_yt_style, "chronos_test123");
        assert!(
            patched_yt.contains("style-src 'unsafe-inline' https://s.ytimg.com"),
            "style-src unsafe-inline was invalidated: {patched_yt}"
        );
        assert!(
            patched_yt.contains("script-src 'self' 'nonce-chronos_test123'"),
            "missing synthesized script-src: {patched_yt}"
        );

        let mut f = db::FocusFilters::default();
        f.yt_block_comments = true;
        f.global_grayscale = true;
        let html = "<!doctype html><html><HEAD lang=\"en\"><title>YT</title></HEAD><body></body></html>";
        let out = inject_html(html, "www.youtube.com", &f, "chronos_test123");
        assert!(out.contains("<style id=\"chronos-focus-css\" nonce=\"chronos_test123\">"));
        assert!(out.contains("ytd-comments"));
        assert!(out.contains("chronos-grayscale"));
        assert!(out.contains("ChronosFocusCore"));
        // Inserted directly after <HEAD lang="en">
        let head_end = out.find("<HEAD lang=\"en\">").unwrap() + "<HEAD lang=\"en\">".len();
        assert!(out[head_end..].starts_with("<style id=\"chronos-focus-css\""));
    }

    #[test]
    fn test_focus_filters_legacy_isolation_in_db() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let tmp_dir = std::env::temp_dir().join(format!("chronos_ff_iso_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp_dir);
        std::fs::create_dir_all(&tmp_dir).unwrap();
        let db_path = tmp_dir.join("test.db");
        db::init_db(db_path.to_str().unwrap()).unwrap();

        // Inject dirty legacy booleans directly into SQLite
        {
            let conn = db::get_conn().lock();
            conn.execute(
                "INSERT OR REPLACE INTO app_config (key, value, updated_at_utc) VALUES ('focus_filters', ?1, 0)",
                [r#"{"block_shorts":true,"grayscale_mode":true,"educational_only":true,"block_feed":true,"block_comments":true,"block_notifications":true,"yt_block_shorts":true,"yt_educational_mode":false,"yt_block_sidebar":false,"yt_block_comments":false,"ig_block_reels":true,"ig_block_feed":false,"ig_block_comments":false,"tt_block_feed":true,"rd_block_feed":false,"rd_block_comments":false,"tw_block_feed":false,"tw_block_trends":false,"li_block_feed":false,"global_grayscale":false,"global_block_notifications":false}"#],
            ).unwrap();
        }

        let loaded = db::get_focus_filters();
        assert!(!loaded.block_shorts);
        assert!(!loaded.block_comments);
        assert!(!loaded.block_feed);
        assert!(!loaded.educational_only);
        assert!(!loaded.yt_block_comments);
        assert!(!loaded.yt_educational_mode);
        assert!(!loaded.global_grayscale);
        assert!(!loaded.grayscale_mode);
        assert!(!loaded.global_block_notifications);
        assert!(!loaded.block_notifications);
        let _ = std::fs::remove_dir_all(&tmp_dir);
    }

    #[test]
    fn test_proxy_end_to_end_connect_injection_and_redirect() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let rt = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
        let pid = std::process::id();
        let tmp_dir = std::env::temp_dir().join(format!("chronos_proxy_e2e_{pid}"));
        let db_path = tmp_dir.join("test.db");
        let ca_dir = tmp_dir.join("ca");
        let _ = std::fs::remove_dir_all(&tmp_dir);
        std::fs::create_dir_all(&ca_dir).unwrap();

        db::init_db(db_path.to_str().unwrap()).unwrap();
        let mut f = db::FocusFilters::default();
        f.yt_block_shorts = true;
        f.yt_block_comments = true;
        f.global_grayscale = true;
        db::set_focus_filters(&f);
        engine::save_rule(
            "youtube.com",
            "YouTube",
            3600,
            "SELF_CONTROL",
            "SITE",
            "youtube.com",
            None,
            None,
        )
        .unwrap();

        // Spin up a mock HTTPS origin server with self-signed test cert for www.youtube.com
        let origin_ca = CertAuthority::load_or_create(&tmp_dir.join("origin_ca")).unwrap();
        let origin_cfg = origin_ca.server_config_for_host("www.youtube.com").unwrap();
        let origin_acceptor = TlsAcceptor::from(origin_cfg);
        let origin_listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let origin_addr = origin_listener.local_addr().unwrap();

        tokio::spawn(async move {
            while let Ok((tcp, _)) = origin_listener.accept().await {
                let acc = origin_acceptor.clone();
                tokio::spawn(async move {
                    if let Ok(mut tls) = acc.accept(tcp).await {
                        let mut buf = [0u8; 4096];
                        let _ = tls.read(&mut buf).await;
                        let body = "<html><head><title>YouTube</title></head><body><div id=\"comments\">hi</div></body></html>";
                        let resp = format!(
                            "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Security-Policy: script-src 'strict-dynamic'; style-src 'self'\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                            body.len(),
                            body
                        );
                        let _ = tls.write_all(resp.as_bytes()).await;
                        let _ = tls.flush().await;
                        let _ = tls.shutdown().await;
                    }
                });
            }
        });

        let origin_ca_pem = std::fs::read(tmp_dir.join("origin_ca/chronos-proxy-ca.crt")).unwrap();
        let mut host_map = HashMap::new();
        host_map.insert("www.youtube.com".to_string(), origin_addr.to_string());

        let proxy_cfg = ProxyConfig {
            bind_addr: "127.0.0.1:0".to_string(),
            ca_dir: ca_dir.clone(),
            host_map,
            extra_upstream_ca_pem: Some(origin_ca_pem),
        };
        let proxy_addr = spawn_proxy_for_test(proxy_cfg).await.unwrap();

        // Build client TLS connector trusting proxy's generated CA
        let proxy_ca_pem = std::fs::read(ca_dir.join("chronos-proxy-ca.crt")).unwrap();
        let mut root_store = RootCertStore::empty();
        let mut cur = std::io::Cursor::new(&proxy_ca_pem);
        for c in rustls_pki_types::CertificateDer::pem_reader_iter(&mut cur).filter_map(Result::ok) {
            root_store.add(c).unwrap();
        }
        let client_tls_cfg = ClientConfig::builder()
            .with_root_certificates(root_store)
            .with_no_client_auth();
        let client_connector = TlsConnector::from(Arc::new(client_tls_cfg));

        // 1. Test /watch HTML injection + CSP nonce patching
        let mut stream = TcpStream::connect(proxy_addr).await.unwrap();
        stream
            .write_all(b"CONNECT www.youtube.com:443 HTTP/1.1\r\nHost: www.youtube.com:443\r\n\r\n")
            .await
            .unwrap();
        let mut connect_buf = [0u8; 256];
        let n = stream.read(&mut connect_buf).await.unwrap();
        assert!(std::str::from_utf8(&connect_buf[..n]).unwrap().contains("200 Connection Established"));

        let mut tls_stream = client_connector
            .connect(ServerName::try_from("www.youtube.com".to_string()).unwrap(), stream)
            .await
            .unwrap();
        tls_stream
            .write_all(b"GET /watch?v=test HTTP/1.1\r\nHost: www.youtube.com\r\nAccept: text/html\r\n\r\n")
            .await
            .unwrap();
        let mut resp_bytes = Vec::new();
        tls_stream.read_to_end(&mut resp_bytes).await.unwrap();
        let resp_str = String::from_utf8_lossy(&resp_bytes);
        assert!(resp_str.contains("200 OK"));
        assert!(resp_str.contains("'nonce-chronos_"));
        assert!(resp_str.contains("chronos-focus-css"));
        assert!(resp_str.contains("ytd-comments"));
        assert!(resp_str.contains("chronos-grayscale"));

        // 2. Test /shorts/abc focus redirect (302 -> /)
        let mut stream2 = TcpStream::connect(proxy_addr).await.unwrap();
        stream2
            .write_all(b"CONNECT www.youtube.com:443 HTTP/1.1\r\nHost: www.youtube.com:443\r\n\r\n")
            .await
            .unwrap();
        let _ = stream2.read(&mut connect_buf).await.unwrap();
        let mut tls_stream2 = client_connector
            .connect(ServerName::try_from("www.youtube.com".to_string()).unwrap(), stream2)
            .await
            .unwrap();
        tls_stream2
            .write_all(b"GET /shorts/abc HTTP/1.1\r\nHost: www.youtube.com\r\nAccept: text/html\r\n\r\n")
            .await
            .unwrap();
        let mut redir_bytes = Vec::new();
        tls_stream2.read_to_end(&mut redir_bytes).await.unwrap();
        let redir_str = String::from_utf8_lossy(&redir_bytes);
        assert!(redir_str.contains("302 Found"));
        assert!(redir_str.contains("Location: https://www.youtube.com/"));

        // 3. Test virtual /__chronos_api__/focus-filters
        let mut stream3 = TcpStream::connect(proxy_addr).await.unwrap();
        stream3
            .write_all(b"CONNECT www.youtube.com:443 HTTP/1.1\r\nHost: www.youtube.com:443\r\n\r\n")
            .await
            .unwrap();
        let _ = stream3.read(&mut connect_buf).await.unwrap();
        let mut tls_stream3 = client_connector
            .connect(ServerName::try_from("www.youtube.com".to_string()).unwrap(), stream3)
            .await
            .unwrap();
        tls_stream3
            .write_all(b"GET /__chronos_api__/focus-filters HTTP/1.1\r\nHost: www.youtube.com\r\n\r\n")
            .await
            .unwrap();
        let mut api_bytes = Vec::new();
        tls_stream3.read_to_end(&mut api_bytes).await.unwrap();
        let api_str = String::from_utf8_lossy(&api_bytes);
        assert!(api_str.contains("\"ytBlockComments\":true"));
        assert!(api_str.contains("\"globalGrayscale\":true"));
        assert!(resp_str.contains("chronos-focus-hud"));

        // 4. Test virtual /__chronos_api__/heartbeat returning HUD remainingSeconds
        let mut stream4 = TcpStream::connect(proxy_addr).await.unwrap();
        stream4
            .write_all(b"CONNECT www.youtube.com:443 HTTP/1.1\r\nHost: www.youtube.com:443\r\n\r\n")
            .await
            .unwrap();
        let _ = stream4.read(&mut connect_buf).await.unwrap();
        let mut tls_stream4 = client_connector
            .connect(ServerName::try_from("www.youtube.com".to_string()).unwrap(), stream4)
            .await
            .unwrap();
        let hb_body = r#"{"url":"https://www.youtube.com/watch?v=test","title":"YouTube"}"#;
        let hb_req = format!(
            "POST /__chronos_api__/heartbeat HTTP/1.1\r\nHost: www.youtube.com\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
            hb_body.len(),
            hb_body
        );
        tls_stream4.write_all(hb_req.as_bytes()).await.unwrap();
        let mut hb_bytes = Vec::new();
        tls_stream4.read_to_end(&mut hb_bytes).await.unwrap();
        let hb_str = String::from_utf8_lossy(&hb_bytes);
        assert!(hb_str.contains("\"matched\":true"));
        assert!(hb_str.contains("\"remainingSeconds\""));
        assert!(hb_str.contains("\"displayName\":\"YouTube\""));

        // 5. Test POST /__chronos_api__/focus-filters persists changes & GET /__chronos_api__/status returns sites
        let mut stream5 = TcpStream::connect(proxy_addr).await.unwrap();
        stream5
            .write_all(b"CONNECT www.youtube.com:443 HTTP/1.1\r\nHost: www.youtube.com:443\r\n\r\n")
            .await
            .unwrap();
        let _ = stream5.read(&mut connect_buf).await.unwrap();
        let mut tls_stream5 = client_connector
            .connect(ServerName::try_from("www.youtube.com".to_string()).unwrap(), stream5)
            .await
            .unwrap();
        let post_filters = r#"{"ytBlockShorts":true,"globalGrayscale":false,"ytEducationalMode":true}"#;
        let post_req = format!(
            "POST /__chronos_api__/focus-filters HTTP/1.1\r\nHost: www.youtube.com\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
            post_filters.len(),
            post_filters
        );
        tls_stream5.write_all(post_req.as_bytes()).await.unwrap();
        let mut post_bytes = Vec::new();
        tls_stream5.read_to_end(&mut post_bytes).await.unwrap();
        let post_str = String::from_utf8_lossy(&post_bytes);
        assert!(post_str.contains("\"success\":true"));
        assert!(post_str.contains("\"ytEducationalMode\":true"));
        assert!(post_str.contains("\"globalGrayscale\":false"));
        assert!(db::get_focus_filters().yt_educational_mode);
        assert!(!db::get_focus_filters().global_grayscale);

        let mut stream6 = TcpStream::connect(proxy_addr).await.unwrap();
        stream6
            .write_all(b"CONNECT www.youtube.com:443 HTTP/1.1\r\nHost: www.youtube.com:443\r\n\r\n")
            .await
            .unwrap();
        let _ = stream6.read(&mut connect_buf).await.unwrap();
        let mut tls_stream6 = client_connector
            .connect(ServerName::try_from("www.youtube.com".to_string()).unwrap(), stream6)
            .await
            .unwrap();
        tls_stream6
            .write_all(b"GET /__chronos_api__/status HTTP/1.1\r\nHost: www.youtube.com\r\n\r\n")
            .await
            .unwrap();
        let mut st_bytes = Vec::new();
        tls_stream6.read_to_end(&mut st_bytes).await.unwrap();
        let st_str = String::from_utf8_lossy(&st_bytes);
        assert!(st_str.contains("\"sites\""));
        assert!(st_str.contains("\"entityId\":\"youtube.com\""));
        assert!(st_str.contains("\"primaryLanguage\""));
        assert!(st_str.contains("\"tagDisplayMap\""));

        // 5b. Test virtual /__chronos_api__/launchers/autocomplete?kind=tag returns localized tag suggestions
        let mut stream_ac = TcpStream::connect(proxy_addr).await.unwrap();
        stream_ac
            .write_all(b"CONNECT www.youtube.com:443 HTTP/1.1\r\nHost: www.youtube.com:443\r\n\r\n")
            .await
            .unwrap();
        let _ = stream_ac.read(&mut connect_buf).await.unwrap();
        let mut tls_ac = client_connector
            .connect(ServerName::try_from("www.youtube.com".to_string()).unwrap(), stream_ac)
            .await
            .unwrap();
        tls_ac
            .write_all(b"GET /__chronos_api__/launchers/autocomplete?kind=tag&q=nsfw HTTP/1.1\r\nHost: www.youtube.com\r\n\r\n")
            .await
            .unwrap();
        let mut ac_bytes = Vec::new();
        tls_ac.read_to_end(&mut ac_bytes).await.unwrap();
        let ac_str = String::from_utf8_lossy(&ac_bytes);
        assert!(ac_str.contains("\"canonicalEn\":\"NSFW\""), "Expected canonical NSFW in: {ac_str}");
        assert!(ac_str.contains("Conte"), "Expected localized PT-BR display name in: {ac_str}");

        // 6. Test steamloopback.host & infra hosts never MITM'd even with global_grayscale
        let mut gf = db::FocusFilters::default();
        gf.global_grayscale = true;
        assert!(!should_intercept_host("steamloopback.host", &gf, &[], &HashSet::new()));
        assert!(!should_intercept_host("api.steampowered.com", &gf, &[], &HashSet::new()));
        assert!(should_intercept_host("store.steampowered.com", &gf, &[], &HashSet::new()));

        let _ = std::fs::remove_dir_all(&tmp_dir);
        });
    }

    #[test]
    fn test_proxy_returns_502_instead_of_empty_response_on_upstream_failure() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let rt = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let pid = std::process::id();
            let tmp_dir = std::env::temp_dir().join(format!("chronos_proxy_502_{pid}"));
            let db_path = tmp_dir.join("test.db");
            let ca_dir = tmp_dir.join("ca");
            let _ = std::fs::remove_dir_all(&tmp_dir);
            std::fs::create_dir_all(&ca_dir).unwrap();

            db::init_db(db_path.to_str().unwrap()).unwrap();
            let mut f = db::FocusFilters::default();
            f.global_grayscale = true;
            db::set_focus_filters(&f);

            // Bind a dead port cleanly by picking ephemeral port and immediately dropping listener
            let dead_listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let dead_addr = dead_listener.local_addr().unwrap();
            drop(dead_listener);

            let mut host_map = HashMap::new();
            host_map.insert("store.steampowered.com".to_string(), dead_addr.to_string());
            let proxy_cfg = ProxyConfig {
                bind_addr: "127.0.0.1:0".to_string(),
                ca_dir: ca_dir.clone(),
                host_map,
                extra_upstream_ca_pem: None,
            };
            let proxy_addr = spawn_proxy_for_test(proxy_cfg).await.unwrap();

            let proxy_ca_pem = std::fs::read(ca_dir.join("chronos-proxy-ca.crt")).unwrap();
            let mut root_store = RootCertStore::empty();
            let mut cur = std::io::Cursor::new(&proxy_ca_pem);
            for c in rustls_pki_types::CertificateDer::pem_reader_iter(&mut cur).filter_map(Result::ok) {
                root_store.add(c).unwrap();
            }
            let client_tls_cfg = ClientConfig::builder()
                .with_root_certificates(root_store)
                .with_no_client_auth();
            let client_connector = TlsConnector::from(Arc::new(client_tls_cfg));

            let mut stream = TcpStream::connect(proxy_addr).await.unwrap();
            stream
                .write_all(b"CONNECT store.steampowered.com:443 HTTP/1.1\r\nHost: store.steampowered.com:443\r\n\r\n")
                .await
                .unwrap();
            let mut connect_buf = [0u8; 256];
            let n = stream.read(&mut connect_buf).await.unwrap();
            assert!(std::str::from_utf8(&connect_buf[..n]).unwrap().contains("200 Connection Established"));

            let mut tls_stream = client_connector
                .connect(ServerName::try_from("store.steampowered.com".to_string()).unwrap(), stream)
                .await
                .unwrap();
            tls_stream
                .write_all(b"GET /app/730/ HTTP/1.1\r\nHost: store.steampowered.com\r\n\r\n")
                .await
                .unwrap();
            let mut resp_bytes = Vec::new();
            tls_stream.read_to_end(&mut resp_bytes).await.unwrap();
            let resp_str = String::from_utf8_lossy(&resp_bytes);
            assert!(
                resp_str.contains("502 Bad Gateway"),
                "Expected explicit 502 instead of empty response (-324), got: {resp_str:?}"
            );

            let _ = std::fs::remove_dir_all(&tmp_dir);
        });
    }

    #[test]
    fn test_injected_html_propagates_anti_cheat_state_to_hud() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db_file = format!("/tmp/chronos_proxy_ac_html_{}.db", std::process::id());
        let _ = std::fs::remove_file(&db_file);
        db::init_db(&db_file).expect("init temp db");

        let mut filters = db::FocusFilters::default();
        filters.launcher_filter_enabled = true;
        filters.launcher_blocked_tags = vec!["Action".to_string()];
        db::set_focus_filters(&filters);

        engine::enable_anti_cheat("CHALLENGE", None).expect("enable ac");
        let html_active = inject_html(
            "<html><head></head><body><h1>Steam</h1></body></html>",
            "store.steampowered.com",
            &filters,
            "nonce123",
        );
        assert!(html_active.contains("var currentAntiCheatActive = true;"));
        assert!(html_active.contains("getAntiCheatActive: function() { return currentAntiCheatActive; }"));
        assert!(html_active.contains("hud.syncFilters(currentFilters, currentTagDisplayMap, currentPrimaryLanguage, currentAntiCheatActive)"));

        engine::disable_anti_cheat(&engine::current_challenge_text()).expect("disable ac");
        let html_off = inject_html(
            "<html><head></head><body><h1>Steam</h1></body></html>",
            "store.steampowered.com",
            &filters,
            "nonce123",
        );
        assert!(html_off.contains("var currentAntiCheatActive = false;"));

        let _ = std::fs::remove_file(db_file);
    }

    #[test]
    fn test_lutris_api_games_search_json_is_filtered() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db_file = format!("/tmp/chronos_proxy_lutris_api_{}.db", std::process::id());
        let _ = std::fs::remove_file(&db_file);
        db::init_db(&db_file).expect("init temp db");

        assert!(is_lutris_api_games_request("lutris.net", "/api/games?search=isaac&with-installers=True"));
        assert!(is_lutris_api_games_request("lutris.net", "/api/games/?search=isaac"));
        assert!(!is_lutris_api_games_request("lutris.net", "/api/games/hades"));
        assert!(!is_lutris_api_games_request("example.com", "/api/games?search=x"));

        let mut filters = db::FocusFilters::default();
        filters.launcher_filter_enabled = true;
        filters.launcher_blocked_tags = vec!["Roguelike".to_string()];
        db::set_focus_filters(&filters);
        steam_api::save_cached_metadata(
            "appid:250900",
            &steam_api::GameMetadata {
                app_id: Some(250900),
                title: "The Binding of Isaac: Rebirth".to_string(),
                tags: vec!["Roguelike".to_string()],
                genres: Vec::new(),
                categories: Vec::new(),
                source: "steam_browse_service".to_string(),
            },
        );
        steam_api::save_cached_metadata(
            &format!("title:{}", steam_api::normalize_match_text("Isaac Asimov Robots")),
            &steam_api::GameMetadata {
                app_id: None,
                title: "Isaac Asimov Robots".to_string(),
                tags: vec!["Puzzle".to_string()],
                genres: Vec::new(),
                categories: Vec::new(),
                source: "gamedb_igdb".to_string(),
            },
        );

        let body = br#"{"count":2,"next":null,"previous":null,"results":[
            {"id":1,"name":"The Binding of Isaac: Rebirth","slug":"the-binding-of-isaac-rebirth",
             "provider_games":[{"name":"x","slug":"250900","service":"steam"}]},
            {"id":2,"name":"Isaac Asimov Robots","slug":"isaac-asimov-robots","provider_games":[]}]}"#;
        let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
        let out = rt
            .block_on(filter_lutris_api_games_json(body, &filters))
            .expect("one result filtered");
        let v: serde_json::Value = serde_json::from_slice(&out).unwrap();
        let names: Vec<&str> = v["results"].as_array().unwrap().iter().map(|r| r["name"].as_str().unwrap()).collect();
        assert_eq!(names, vec!["Isaac Asimov Robots"]);
        assert_eq!(v["count"], 1);

        filters.launcher_blocked_tags = vec!["FPS".to_string()];
        assert!(rt.block_on(filter_lutris_api_games_json(body, &filters)).is_none());
        let _ = std::fs::remove_file(db_file);
    }

    #[test]
    fn test_lutris_interception_and_multiprovider_page_block_label() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db_file = format!("/tmp/chronos_proxy_lutris_block_{}.db", std::process::id());
        let _ = std::fs::remove_file(&db_file);
        db::init_db(&db_file).expect("init temp db");

        let mut filters = db::FocusFilters::default();
        filters.launcher_filter_enabled = true;
        filters.launcher_blocked_tags = vec!["Roguelike".to_string()];
        db::set_focus_filters(&filters);

        assert!(should_intercept_host("lutris.net", &filters, &[], &HashSet::new()));

        steam_api::save_cached_metadata(
            &format!("title:{}", steam_api::normalize_match_text("Mock Lutris Roguelike")),
            &steam_api::GameMetadata {
                app_id: None,
                title: "Mock Lutris Roguelike".to_string(),
                tags: vec!["Roguelike".to_string()],
                genres: Vec::new(),
                categories: Vec::new(),
                source: "itch".to_string(),
            },
        );

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let blocked_reason = check_launcher_page_block(
                "lutris.net",
                "/games/mock-lutris-roguelike",
                &filters,
            )
            .await;
            let (blocked_title, reason) = blocked_reason.expect("expected block reason");
            assert_eq!(blocked_title, "Mock Lutris Roguelike");
            assert!(reason.contains("(Itch.io)"), "got: {reason}");
        });

        let _ = std::fs::remove_file(db_file);
    }
}
