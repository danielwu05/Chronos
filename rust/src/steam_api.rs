//! Steam API public storefront client & game metadata cache (`rust/src/steam_api.rs`).
//!
//! Uses keyless Steam Web / Store endpoints (`tagdata/populartags`, `IStoreBrowseService/GetItems/v1`,
//! `api/appdetails`, `api/storesearch`) cached in SQLite (`game_metadata_cache` and
//! `steam_tag_catalog`) so launcher/store filtering works uniformly across Steam, Heroic, Epic,
//! GOG, Lutris, Bottles, Itch, and browser tabs.

use std::collections::{HashMap, HashSet};
use std::io::Read;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use flate2::read::{DeflateDecoder, GzDecoder};
use rustls::pki_types::ServerName;
use rustls::{ClientConfig, RootCertStore};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio_rustls::TlsConnector;

use crate::db;

const METADATA_TTL_SECONDS: i64 = 7 * 86400;
const TAG_CATALOG_TTL_SECONDS: i64 = 14 * 86400;
const MAX_HTTP_BODY_BYTES: usize = 4 * 1024 * 1024;
const HTTP_TIMEOUT_SECS: u64 = 4;

static STEAM_TLS: OnceLock<TlsConnector> = OnceLock::new();
static RUNTIME_CRYPTO: OnceLock<()> = OnceLock::new();

fn tls_connector() -> TlsConnector {
    RUNTIME_CRYPTO.get_or_init(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
    });
    STEAM_TLS
        .get_or_init(|| {
            let mut root_store = RootCertStore::empty();
            for cert in rustls_native_certs::load_native_certs().certs {
                let _ = root_store.add(cert);
            }
            let mut cfg = ClientConfig::builder()
                .with_root_certificates(root_store)
                .with_no_client_auth();
            cfg.alpn_protocols = vec![b"http/1.1".to_vec()];
            TlsConnector::from(Arc::new(cfg))
        })
        .clone()
}

use std::sync::Arc;

#[derive(Clone, Debug, Default, serde::Serialize, serde::Deserialize)]
pub struct GameMetadata {
    pub app_id: Option<i64>,
    pub title: String,
    pub tags: Vec<String>,
    pub genres: Vec<String>,
    pub categories: Vec<String>,
    pub source: String,
}

impl GameMetadata {
    pub fn all_filter_terms(&self) -> Vec<String> {
        let mut combined = Vec::new();
        combined.extend(self.tags.iter().cloned());
        combined.extend(self.genres.iter().cloned());
        combined.extend(self.categories.iter().cloned());
        db::normalize_term_list(&combined)
    }
}

fn now_utc() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

const SECONDARY_PROVIDER_TIMEOUT_MS: u64 = 2500;
const MISS_CACHE_TTL_SECONDS: i64 = 60;

static GAME_MISS_CACHE: OnceLock<Mutex<HashMap<String, i64>>> = OnceLock::new();

fn steam_store_base() -> String {
    std::env::var("CHRONOS_STEAM_STORE_BASE")
        .unwrap_or_else(|_| "https://store.steampowered.com".to_string())
        .trim_end_matches('/')
        .to_string()
}

fn steam_api_base() -> String {
    std::env::var("CHRONOS_STEAM_API_BASE")
        .unwrap_or_else(|_| "https://api.steampowered.com".to_string())
        .trim_end_matches('/')
        .to_string()
}

fn gog_catalog_base() -> String {
    std::env::var("CHRONOS_GOG_CATALOG_BASE")
        .unwrap_or_else(|_| "https://catalog.gog.com".to_string())
        .trim_end_matches('/')
        .to_string()
}

fn gamedb_base() -> String {
    std::env::var("CHRONOS_GAMEDB_BASE")
        .unwrap_or_else(|_| "https://app.lizardbyte.dev/GameDB".to_string())
        .trim_end_matches('/')
        .to_string()
}

fn itch_base() -> String {
    std::env::var("CHRONOS_ITCH_BASE")
        .unwrap_or_else(|_| "https://itch.io".to_string())
        .trim_end_matches('/')
        .to_string()
}

/// Maps internal metadata source identifiers to human-readable UI/block labels.
pub fn source_display_label(source: &str) -> &'static str {
    let s = source.trim().to_ascii_lowercase();
    if s.starts_with("gog") {
        "GOG"
    } else if s.starts_with("gamedb") || s.contains("igdb") {
        "IGDB"
    } else if s.starts_with("itch") {
        "Itch.io"
    } else if s == "dom_learned" {
        "Página"
    } else {
        "Steam API"
    }
}

pub fn url_encode(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for b in input.as_bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(*b as char);
            }
            b' ' => out.push_str("%20"),
            other => {
                out.push('%');
                out.push_str(&format!("{:02X}", other));
            }
        }
    }
    out
}

/// Folds Portuguese/Latin accents and normalizes casing so comparisons match reliably.
pub fn normalize_match_text(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for ch in input.trim().to_lowercase().chars() {
        if matches!(ch, '®' | '™' | '©') {
            continue;
        }
        let mapped = match ch {
            'á' | 'à' | 'ã' | 'â' | 'ä' => 'a',
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'í' | 'ì' | 'î' | 'ï' => 'i',
            'ó' | 'ò' | 'õ' | 'ô' | 'ö' => 'o',
            'ú' | 'ù' | 'û' | 'ü' => 'u',
            'ç' => 'c',
            'ñ' => 'n',
            _ => ch,
        };
        out.push(mapped);
    }
    strip_storefront_title_suffixes(&out)
}

/// Removes trailing storefront `<title>` suffixes (Epic, GOG, Lutris, itch.io) from an
/// already-lowercased title so `"Hades | Download and Buy Today - Epic Games Store"`
/// normalizes to `"hades"`.
fn strip_storefront_title_suffixes(norm: &str) -> String {
    const SUFFIXES: [&str; 12] = [
        "| download and buy today - epic games store",
        "| baixe e compre hoje - epic games store",
        "| epic games store",
        "- epic games store",
        "on gog.com",
        "| gog.com",
        "- gog.com",
        "| lutris",
        "- lutris",
        "| itch.io",
        "- itch.io",
        "on itch.io",
    ];
    let mut cur = norm.trim().to_string();
    loop {
        let mut changed = false;
        for suffix in SUFFIXES {
            if let Some(stripped) = cur.strip_suffix(suffix) {
                let trimmed = stripped.trim_end();
                if !trimmed.is_empty() {
                    cur = trimmed.to_string();
                    changed = true;
                }
            }
        }
        if !changed {
            return cur;
        }
    }
}

fn compact_alnum(input: &str) -> String {
    normalize_match_text(input)
        .chars()
        .filter(|c| c.is_alphanumeric())
        .collect()
}

fn strip_edition_suffixes(norm_text: &str) -> String {
    let mut cur = norm_text
        .replace([':', '-', '—', '–', '|'], " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    for suffix in [
        "complete edition",
        "definitive edition",
        "game of the year edition",
        "game of the year",
        "enhanced edition",
        "anniversary edition",
        "special edition",
        "deluxe edition",
        "collectors edition",
        "collector s edition",
        "ultimate edition",
        "java edition",
        "bedrock edition",
        "remastered",
        "complete",
        "collection",
        "goty",
    ] {
        if let Some(stripped) = cur.strip_suffix(suffix) {
            let trimmed = stripped.trim();
            if trimmed.len() >= 4 {
                cur = trimmed.to_string();
            }
        }
    }
    cur
}

/// Checks whether a candidate title from a remote catalog search confidently refers
/// to the queried game title, rejecting unrelated prefix/partial matches.
pub fn is_confident_title_match(query: &str, candidate: &str) -> bool {
    let q_comp = compact_alnum(query);
    let c_comp = compact_alnum(candidate);
    if q_comp.is_empty() || c_comp.is_empty() {
        return false;
    }
    if q_comp == c_comp {
        return true;
    }
    let q_base = compact_alnum(&strip_edition_suffixes(&normalize_match_text(query)));
    let c_base = compact_alnum(&strip_edition_suffixes(&normalize_match_text(candidate)));
    if !q_base.is_empty() && q_base == c_base {
        return true;
    }
    if q_base.len() >= 6 && c_base.len() >= 6 {
        let (shorter, longer) = if q_base.len() <= c_base.len() {
            (&q_base, &c_base)
        } else {
            (&c_base, &q_base)
        };
        if longer.starts_with(shorter.as_str()) {
            let ratio = shorter.len() as f32 / longer.len() as f32;
            if ratio >= 0.72 {
                return true;
            }
        }
    }
    false
}

pub fn percent_decode_lossy(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(hi), Some(lo)) = (
                (bytes[i + 1] as char).to_digit(16),
                (bytes[i + 2] as char).to_digit(16),
            ) {
                out.push(((hi << 4) | lo) as u8);
                i += 3;
                continue;
            }
        } else if bytes[i] == b'+' {
            out.push(b' ');
            i += 1;
            continue;
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

pub fn is_generic_storefront_title(title: &str) -> bool {
    let norm = normalize_match_text(title);
    matches!(
        norm.as_str(),
        "" | "steam"
            | "steam search"
            | "busca steam"
            | "resultados da busca"
            | "search"
            | "welcome to steam"
            | "bem-vindo ao steam"
            | "bem vindo ao steam"
            | "sign in"
            | "iniciar sessao"
            | "login"
            | "age verification"
            | "verificacao de idade"
            | "epic games"
            | "epic games store"
            | "gog"
            | "gog.com"
            | "gog com"
            | "itch"
            | "itch.io"
            | "itch io"
            | "lutris"
            | "lutris.net"
            | "games"
            | "games - lutris"
            | "top games"
            | "browse games"
            | "browse"
            | "store"
            | "home"
            | "explore"
    ) || norm.starts_with("top free ")
        || norm.starts_with("top paid ")
        || norm.starts_with("top games ")
        || norm.ends_with(" on itch.io")
        || norm.ends_with(" on itch io")
        || norm.ends_with(" - lutris")
}

fn find_marker_digits(haystack_lower: &str, markers: &[&str]) -> Option<i64> {
    for marker in markers {
        if let Some(idx) = haystack_lower.find(marker) {
            let rest = &haystack_lower[idx + marker.len()..];
            let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
            if let Ok(id) = digits.parse::<i64>() {
                if id > 0 {
                    return Some(id);
                }
            }
        }
    }
    None
}

pub fn extract_steam_appid_from_url(url: &str) -> Option<i64> {
    let markers = ["/app/", "/stats/", "=app/", "?app/", "&app/", "appid="];
    let lower = url.to_ascii_lowercase();
    if let Some(id) = find_marker_digits(&lower, &markers) {
        return Some(id);
    }
    if url.contains('%') {
        let decoded = percent_decode_lossy(url).to_ascii_lowercase();
        if let Some(id) = find_marker_digits(&decoded, &markers) {
            return Some(id);
        }
    }
    None
}

fn host_suffix_eq(host_lower: &str, suffix: &str) -> bool {
    let s = suffix.trim().trim_end_matches('.').to_ascii_lowercase();
    host_lower == s || host_lower.ends_with(&format!(".{s}"))
}

fn split_path_and_query_decoded(raw_path: &str) -> (String, Vec<(String, String)>) {
    let (path, qs) = raw_path.split_once('?').unwrap_or((raw_path, ""));
    let path_clean = path.split('#').next().unwrap_or(path).to_string();
    let qs_clean = qs.split('#').next().unwrap_or(qs);
    let mut pairs = Vec::new();
    for pair in qs_clean.split('&') {
        if pair.is_empty() {
            continue;
        }
        let (k, v) = pair.split_once('=').unwrap_or((pair, ""));
        pairs.push((
            percent_decode_lossy(k).to_ascii_lowercase(),
            percent_decode_lossy(v),
        ));
    }
    (path_clean, pairs)
}

fn extract_slug_from_app_path(path_str: &str) -> String {
    let segs: Vec<&str> = path_str
        .split('?')
        .next()
        .unwrap_or(path_str)
        .split('/')
        .filter(|s| !s.is_empty())
        .collect();
    if let Some(app_pos) = segs.iter().position(|s| s.eq_ignore_ascii_case("app")) {
        if let Some(s) = segs.get(app_pos + 2) {
            let lower = s.to_ascii_lowercase();
            if !matches!(
                lower.as_str(),
                "discussions"
                    | "guides"
                    | "images"
                    | "screenshots"
                    | "videos"
                    | "broadcasts"
                    | "workshop"
                    | "reviews"
                    | "allnews"
                    | "news"
            ) {
                let candidate = percent_decode_lossy(s)
                    .replace(['_', '-'], " ")
                    .trim()
                    .to_string();
                if !is_generic_storefront_title(&candidate) {
                    return candidate;
                }
            }
        }
    }
    String::new()
}

fn clean_url_tag_token(raw: &str) -> String {
    let decoded = percent_decode_lossy(raw);
    let trimmed = decoded.trim();
    let stripped = trimmed
        .strip_prefix("GameGenre/")
        .or_else(|| trimmed.strip_prefix("gamegenre/"))
        .or_else(|| trimmed.strip_prefix("genre-"))
        .or_else(|| trimmed.strip_prefix("tag-"))
        .unwrap_or(trimmed);
    let cleaned = stripped.replace(['_', '-', '+'], " ").trim().to_string();
    if cleaned.eq_ignore_ascii_case("rougelike") {
        "Roguelike".to_string()
    } else {
        cleaned
    }
}

fn push_split_url_tags(raw: &str, out: &mut Vec<String>) {
    for part in raw.split([',', ';', '|']) {
        let tok = clean_url_tag_token(part);
        if !tok.is_empty() && !tok.chars().all(|c| c.is_ascii_digit()) {
            out.push(tok);
        }
    }
}

/// Extracts `(app_id, title_hint, url_tags, is_search_query)` for launcher/store URLs across
/// Steam (store/community/agecheck/login-redir/tags/category/search), Epic, GOG, Lutris, and Itch.io.
pub fn extract_launcher_url_hint(
    host: &str,
    origin_path: &str,
) -> Option<(Option<i64>, String, Vec<String>, bool)> {
    let clean_host = host.trim().to_ascii_lowercase();
    let (path, query) = split_path_and_query_decoded(origin_path);
    let full = format!("https://{clean_host}{origin_path}");
    let app_id = extract_steam_appid_from_url(&full);

    let q_get = |name: &str| -> Option<&str> {
        query
            .iter()
            .find(|(k, _)| k == name)
            .map(|(_, v)| v.as_str())
            .filter(|v| !v.trim().is_empty())
    };

    if host_suffix_eq(&clean_host, "store.steampowered.com")
        || host_suffix_eq(&clean_host, "steamcommunity.com")
    {
        if app_id.is_some() {
            let mut slug_hint = extract_slug_from_app_path(&path);
            if slug_hint.is_empty() {
                if let Some(redir) = q_get("redir") {
                    slug_hint = extract_slug_from_app_path(redir);
                }
            }
            return Some((app_id, slug_hint, Vec::new(), false));
        }

        let mut url_tags: Vec<String> = Vec::new();
        let segs: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
        if let Some(tag_pos) = segs
            .iter()
            .position(|s| s.eq_ignore_ascii_case("tags") || s.eq_ignore_ascii_case("tag"))
        {
            if let Some(raw_tag) = segs.get(tag_pos + 2).or_else(|| segs.get(tag_pos + 1)) {
                let decoded = percent_decode_lossy(raw_tag).replace(['_', '+'], " ").trim().to_string();
                if !decoded.is_empty() && decoded.len() > 2 {
                    url_tags.push(decoded);
                }
            }
        } else if let Some(cat_pos) = segs.iter().position(|s| s.eq_ignore_ascii_case("category")) {
            if let Some(raw_cat) = segs.get(cat_pos + 1) {
                let decoded = clean_url_tag_token(raw_cat);
                if !decoded.is_empty() {
                    url_tags.push(decoded);
                }
            }
        }

        if let Some(raw_tags) = q_get("tags").or_else(|| q_get("tag")) {
            let mut numeric_ids = Vec::new();
            for part in raw_tags.split([',', ';']) {
                let trimmed = part.trim();
                if let Ok(tid) = trimmed.parse::<i64>() {
                    if tid > 0 {
                        numeric_ids.push(tid);
                    }
                } else if !trimmed.is_empty() {
                    url_tags.push(trimmed.replace(['_', '+'], " "));
                }
            }
            if !numeric_ids.is_empty() {
                url_tags.extend(lookup_tag_names_by_ids(&numeric_ids, &[]));
            }
        }

        if let Some(term) = q_get("term")
            .or_else(|| q_get("q"))
            .or_else(|| q_get("searchtext"))
        {
            let clean_term = term.trim().to_string();
            return Some((None, clean_term, db::normalize_term_list(&url_tags), true));
        }

        if !url_tags.is_empty() {
            return Some((None, String::new(), db::normalize_term_list(&url_tags), false));
        }
        return None;
    }

    if host_suffix_eq(&clean_host, "store.epicgames.com") {
        let mut url_tags = Vec::new();
        for key in ["tag", "tags", "genre", "genres", "category"] {
            if let Some(raw) = q_get(key) {
                push_split_url_tags(raw, &mut url_tags);
            }
        }
        let segs: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
        if let Some(pos) = segs
            .iter()
            .position(|&s| s.eq_ignore_ascii_case("p") || s.eq_ignore_ascii_case("product"))
        {
            if let Some(slug) = segs.get(pos + 1) {
                return Some((
                    None,
                    percent_decode_lossy(slug).replace(['-', '_'], " "),
                    db::normalize_term_list(&url_tags),
                    false,
                ));
            }
        }
        if let Some(term) = q_get("q") {
            let clean_term = term.trim().to_string();
            if !clean_term.is_empty() {
                return Some((None, clean_term, db::normalize_term_list(&url_tags), true));
            }
        }
        if !url_tags.is_empty() {
            return Some((None, String::new(), db::normalize_term_list(&url_tags), false));
        }
    }

    if host_suffix_eq(&clean_host, "gog.com") {
        let mut url_tags = Vec::new();
        for key in ["tags", "tag", "genres", "genre"] {
            if let Some(raw) = q_get(key) {
                push_split_url_tags(raw, &mut url_tags);
            }
        }
        let segs: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
        if let Some(pos) = segs.iter().position(|&s| s.eq_ignore_ascii_case("game")) {
            if let Some(slug) = segs.get(pos + 1) {
                return Some((
                    None,
                    percent_decode_lossy(slug).replace(['_', '-'], " "),
                    db::normalize_term_list(&url_tags),
                    false,
                ));
            }
        }
        if let Some(term) = q_get("query").or_else(|| q_get("q")) {
            let clean_term = term.trim().to_string();
            if !clean_term.is_empty() {
                return Some((None, clean_term, db::normalize_term_list(&url_tags), true));
            }
        }
        if !url_tags.is_empty() {
            return Some((None, String::new(), db::normalize_term_list(&url_tags), false));
        }
    }

    if host_suffix_eq(&clean_host, "lutris.net") {
        let mut url_tags = Vec::new();
        for key in ["genre", "genres", "tag", "tags"] {
            if let Some(raw) = q_get(key) {
                push_split_url_tags(raw, &mut url_tags);
            }
        }
        let segs: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
        if let Some(pos) = segs.iter().position(|&s| s.eq_ignore_ascii_case("games")) {
            if let Some(&sub) = segs.get(pos + 1) {
                if sub.eq_ignore_ascii_case("genre") {
                    if let Some(g_slug) = segs.get(pos + 2) {
                        let clean_g = clean_url_tag_token(g_slug);
                        if !clean_g.is_empty() && !clean_g.chars().all(|c| c.is_ascii_digit()) {
                            url_tags.push(clean_g);
                        }
                    }
                } else if !matches!(
                    sub.to_ascii_lowercase().as_str(),
                    "platform" | "tags" | "tag" | "category" | "search" | "year" | "company" | "series"
                ) {
                    return Some((
                        None,
                        percent_decode_lossy(sub).replace(['-', '_'], " ").trim().to_string(),
                        db::normalize_term_list(&url_tags),
                        false,
                    ));
                }
            }
        }
        if let Some(term) = q_get("q") {
            let clean_term = term.trim().to_string();
            if !clean_term.is_empty() {
                return Some((None, clean_term, db::normalize_term_list(&url_tags), true));
            }
        }
        if !url_tags.is_empty() {
            return Some((None, String::new(), db::normalize_term_list(&url_tags), false));
        }
    }

    if host_suffix_eq(&clean_host, "itch.io") {
        let segs: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
        if clean_host == "itch.io" || clean_host == "www.itch.io" {
            let mut url_tags = Vec::new();
            for seg in &segs {
                let lower_seg = seg.to_ascii_lowercase();
                if lower_seg.starts_with("tag-") && seg.len() > 4 {
                    let clean_t = clean_url_tag_token(&seg[4..]);
                    if !clean_t.is_empty() {
                        url_tags.push(clean_t);
                    }
                } else if lower_seg.starts_with("genre-") && seg.len() > 6 {
                    let clean_g = clean_url_tag_token(&seg[6..]);
                    if !clean_g.is_empty() {
                        url_tags.push(clean_g);
                    }
                }
            }
            if let Some(term) = q_get("q") {
                let clean_term = term.trim().to_string();
                if !clean_term.is_empty() {
                    return Some((None, clean_term, db::normalize_term_list(&url_tags), true));
                }
            }
            if !url_tags.is_empty() {
                return Some((None, String::new(), db::normalize_term_list(&url_tags), false));
            }
        } else if let Some(slug) = segs.first() {
            if !matches!(
                slug.to_ascii_lowercase().as_str(),
                "games"
                    | "devlogs"
                    | "devlog"
                    | "download"
                    | "data.json"
                    | "presskit"
                    | "rate"
                    | "comments"
                    | "community"
                    | "posts"
                    | "files"
                    | "t"
                    | "profile"
            ) {
                return Some((
                    None,
                    percent_decode_lossy(slug).replace(['-', '_'], " ").trim().to_string(),
                    Vec::new(),
                    false,
                ));
            }
        }
    }

    None
}

fn parse_http_url(url: &str) -> Result<(bool, String, u16, String), String> {
    let (is_https, rest) = if let Some(r) = url.strip_prefix("https://") {
        (true, r)
    } else if let Some(r) = url.strip_prefix("http://") {
        (false, r)
    } else {
        return Err(format!("Unsupported URL scheme: {url}"));
    };

    let (host_port, path) = match rest.split_once('/') {
        Some((hp, p)) => (hp, format!("/{p}")),
        None => (rest, "/".to_string()),
    };

    let default_port = if is_https { 443 } else { 80 };
    let (host, port) = if let Some((h, p_str)) = host_port.rsplit_once(':') {
        if !h.contains(']') && p_str.chars().all(|c| c.is_ascii_digit()) {
            (h.to_string(), p_str.parse::<u16>().unwrap_or(default_port))
        } else {
            (host_port.to_string(), default_port)
        }
    } else {
        (host_port.to_string(), default_port)
    };

    Ok((is_https, host, port, path))
}

async fn read_raw_http_response<S: AsyncRead + Unpin>(
    stream: &mut S,
) -> Result<(u16, Vec<(String, String)>, Vec<u8>), String> {
    let mut buf = Vec::with_capacity(8192);
    let mut tmp = [0u8; 4096];
    let header_end;

    loop {
        let n = stream.read(&mut tmp).await.map_err(|e| e.to_string())?;
        if n == 0 {
            return Err("EOF before HTTP response headers".to_string());
        }
        buf.extend_from_slice(&tmp[..n]);
        if let Some(pos) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
            header_end = pos + 4;
            break;
        }
        if buf.len() > 64 * 1024 {
            return Err("HTTP response headers too large".to_string());
        }
    }

    let mut headers_parsed = [httparse::EMPTY_HEADER; 64];
    let mut resp = httparse::Response::new(&mut headers_parsed);
    let status = match resp.parse(&buf[..header_end]) {
        Ok(httparse::Status::Complete(_)) => resp.code.unwrap_or(0),
        _ => return Err("Malformed HTTP response".to_string()),
    };
    let mut headers = Vec::new();
    for h in resp.headers.iter() {
        headers.push((
            h.name.to_ascii_lowercase(),
            String::from_utf8_lossy(h.value).trim().to_string(),
        ));
    }

    let mut body = buf[header_end..].to_vec();
    let is_chunked = headers
        .iter()
        .any(|(k, v)| k == "transfer-encoding" && v.to_ascii_lowercase().contains("chunked"));
    let content_len = headers
        .iter()
        .find(|(k, _)| k == "content-length")
        .and_then(|(_, v)| v.parse::<usize>().ok());

    while body.len() < MAX_HTTP_BODY_BYTES {
        if let Some(len) = content_len {
            if body.len() >= len {
                body.truncate(len);
                break;
            }
        }
        if is_chunked && body.windows(5).any(|w| w == b"0\r\n\r\n") {
            break;
        }
        let n = stream.read(&mut tmp).await.map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        body.extend_from_slice(&tmp[..n]);
    }

    let decoded = if is_chunked {
        decode_chunked(&body)?
    } else {
        body
    };

    let encoding = headers
        .iter()
        .find(|(k, _)| k == "content-encoding")
        .map(|(_, v)| v.to_ascii_lowercase())
        .unwrap_or_default();

    let final_bytes = if encoding.contains("gzip") {
        let mut dec = GzDecoder::new(&decoded[..]);
        let mut out = Vec::new();
        dec.read_to_end(&mut out).unwrap_or(0);
        if out.is_empty() { decoded } else { out }
    } else if encoding.contains("deflate") {
        let mut dec = DeflateDecoder::new(&decoded[..]);
        let mut out = Vec::new();
        dec.read_to_end(&mut out).unwrap_or(0);
        if out.is_empty() { decoded } else { out }
    } else {
        decoded
    };

    Ok((status, headers, final_bytes))
}

fn decode_chunked(raw: &[u8]) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < raw.len() {
        let Some(rel_end) = raw[i..].windows(2).position(|w| w == b"\r\n") else {
            break;
        };
        let size_line = String::from_utf8_lossy(&raw[i..i + rel_end]);
        let hex_part = size_line.split(';').next().unwrap_or("").trim();
        let chunk_len = usize::from_str_radix(hex_part, 16)
            .map_err(|_| "Invalid HTTP chunk length".to_string())?;
        i += rel_end + 2;
        if chunk_len == 0 {
            break;
        }
        if i + chunk_len > raw.len() {
            out.extend_from_slice(&raw[i..]);
            break;
        }
        out.extend_from_slice(&raw[i..i + chunk_len]);
        i += chunk_len + 2;
    }
    Ok(out)
}

pub async fn fetch_url_bytes(url: &str) -> Result<Vec<u8>, String> {
    let mut current_url = url.to_string();
    for _ in 0..3 {
        let (is_https, host, port, path) = parse_http_url(&current_url)?;
        let req_text = format!(
            "GET {path} HTTP/1.1\r\n\
             Host: {host}\r\n\
             User-Agent: ChronosFocus/1.1.3\r\n\
             Accept: application/json,text/plain,*/*\r\n\
             Accept-Encoding: gzip, deflate, identity\r\n\
             Connection: close\r\n\r\n"
        );

        let fut = async {
            let tcp = TcpStream::connect((host.as_str(), port))
                .await
                .map_err(|e| format!("TCP connect {host}:{port}: {e}"))?;
            if is_https {
                let sni = ServerName::try_from(host.clone())
                    .map_err(|_| format!("Invalid TLS host: {host}"))?;
                let mut tls = tls_connector()
                    .connect(sni, tcp)
                    .await
                    .map_err(|e| format!("TLS handshake {host}: {e}"))?;
                tls.write_all(req_text.as_bytes())
                    .await
                    .map_err(|e| e.to_string())?;
                tls.flush().await.map_err(|e| e.to_string())?;
                read_raw_http_response(&mut tls).await
            } else {
                let mut tcp = tcp;
                tcp.write_all(req_text.as_bytes())
                    .await
                    .map_err(|e| e.to_string())?;
                tcp.flush().await.map_err(|e| e.to_string())?;
                read_raw_http_response(&mut tcp).await
            }
        };

        let (status, headers, body) = tokio::time::timeout(Duration::from_secs(HTTP_TIMEOUT_SECS), fut)
            .await
            .map_err(|_| format!("HTTP timeout querying {host}"))??;

        if matches!(status, 301 | 302 | 303 | 307 | 308) {
            if let Some((_, loc)) = headers.iter().find(|(k, _)| k == "location") {
                if loc.starts_with("http://") || loc.starts_with("https://") {
                    current_url = loc.clone();
                    continue;
                }
            }
        }
        if status >= 400 {
            return Err(format!("HTTP {status} from {host}{path}"));
        }
        return Ok(body);
    }
    Err("Too many redirects".to_string())
}

pub fn run_async_blocking<F, T>(fut: F) -> T
where
    F: std::future::Future<Output = T> + Send + 'static,
    T: Send + 'static,
{
    if tokio::runtime::Handle::try_current().is_ok() {
        std::thread::spawn(move || {
            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("tokio current_thread runtime");
            rt.block_on(fut)
        })
        .join()
        .expect("async worker thread panicked")
    } else {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("tokio current_thread runtime");
        rt.block_on(fut)
    }
}

pub fn parse_populartags_json(body: &[u8]) -> Vec<(i64, String)> {
    let Ok(val) = serde_json::from_slice::<serde_json::Value>(body) else {
        return Vec::new();
    };
    let Some(arr) = val.as_array() else {
        return Vec::new();
    };
    let mut out = Vec::with_capacity(arr.len());
    for entry in arr {
        let Some(tagid) = entry.get("tagid").and_then(|v| v.as_i64()) else {
            continue;
        };
        let Some(name) = entry.get("name").and_then(|v| v.as_str()) else {
            continue;
        };
        let clean = name.trim();
        if !clean.is_empty() {
            out.push((tagid, clean.to_string()));
        }
    }
    out
}

pub fn parse_gettaglist_json(body: &[u8]) -> Vec<(i64, String)> {
    let Ok(val) = serde_json::from_slice::<serde_json::Value>(body) else {
        return Vec::new();
    };
    let Some(arr) = val
        .get("response")
        .and_then(|r| r.get("tags"))
        .and_then(|v| v.as_array())
    else {
        return Vec::new();
    };
    let mut out = Vec::with_capacity(arr.len());
    for entry in arr {
        let Some(tagid) = entry.get("tagid").and_then(|v| v.as_i64()) else {
            continue;
        };
        let Some(name) = entry.get("name").and_then(|v| v.as_str()) else {
            continue;
        };
        let clean = name.trim();
        if !clean.is_empty() {
            out.push((tagid, clean.to_string()));
        }
    }
    out
}

pub fn builtin_fallback_tags_for_id(tag_id: i64) -> &'static [&'static str] {
    match tag_id {
        6650 => &["Nudity", "Nudez"],
        9130 => &["Hentai"],
        12095 => &["Sexual Content", "Conteúdo Sexual"],
        40500 => &["Sexual Themes"],
        24904 => &["NSFW", "Conteúdo Adulto"],
        5611 => &["Hentai", "NSFW", "Conteúdo Adulto"],
        4085 => &["Anime"],
        113 => &["Free to Play", "Gratuito para Jogar"],
        19 => &["Action", "Ação"],
        21 => &["Adventure", "Aventura"],
        122 => &["RPG"],
        9 => &["Strategy", "Estratégia"],
        597 => &["Casual"],
        599 => &["Simulation", "Simulação"],
        492 => &["Indie"],
        1663 => &["FPS", "Tiro em Primeira Pessoa (FPS)"],
        3859 => &["Multiplayer", "Multijogador"],
        1775 => &["PvP", "Jogador x Jogador (PvP)"],
        4182 => &["Singleplayer", "Um Jogador"],
        1716 => &["Roguelike"],
        29482 => &["Souls-like", "Soulslike"],
        1662 => &["Survival", "Sobrevivência"],
        4345 => &["Gore", "Violência Extrema"],
        4667 => &["Violent", "Violento"],
        _ => &[],
    }
}

fn is_umbrella_adult_tag(norm: &str) -> bool {
    matches!(
        norm,
        "nsfw" | "conteudo adulto" | "adult only" | "adulto" | "adult" | "18+"
    )
}

fn is_explicit_adult_candidate(norm: &str) -> bool {
    matches!(
        norm,
        "hentai"
            | "nsfw"
            | "sexual content"
            | "conteudo sexual"
            | "nudity"
            | "nudez"
            | "sexual themes"
            | "conteudo adulto"
            | "adult only"
            | "erotic"
            | "eroge"
    )
}

pub fn append_canonical_tag_aliases(
    tags: &mut Vec<String>,
    tag_ids: &[i64],
    desc_ids: &[i64],
) {
    let has_adult_desc = desc_ids.iter().any(|&d| matches!(d, 3 | 4));
    let has_gore_desc = desc_ids.contains(&2);
    let has_adult_tag_id = tag_ids
        .iter()
        .any(|&tid| matches!(tid, 6650 | 9130 | 12095 | 40500 | 24904 | 5611));
    let has_adult_text = tags
        .iter()
        .any(|t| is_explicit_adult_candidate(&normalize_match_text(t)));

    if has_adult_desc || has_adult_tag_id || has_adult_text {
        tags.push("NSFW".to_string());
        tags.push("Conteúdo Adulto".to_string());
        tags.push("Adult Only".to_string());
    }
    if has_adult_desc {
        tags.push("Sexual Content".to_string());
        tags.push("Conteúdo Sexual".to_string());
        tags.push("Nudity".to_string());
        tags.push("Nudez".to_string());
    }
    if has_gore_desc {
        tags.push("Violência Extrema".to_string());
        tags.push("Gore".to_string());
    }
}

pub fn lookup_tag_names_by_ids(tag_ids: &[i64], desc_ids: &[i64]) -> Vec<String> {
    if tag_ids.is_empty() && desc_ids.is_empty() {
        return Vec::new();
    }
    let (db_map, _) = load_tag_map_from_db();
    let mut out = Vec::new();
    for &tid in tag_ids {
        if let Some(names) = db_map.get(&tid) {
            out.extend(names.iter().cloned());
        }
        for fallback in builtin_fallback_tags_for_id(tid) {
            out.push((*fallback).to_string());
        }
    }
    append_canonical_tag_aliases(&mut out, tag_ids, desc_ids);
    db::normalize_term_list(&out)
}

pub fn parse_store_browse_items_json(
    body: &[u8],
    tag_map: &HashMap<i64, Vec<String>>,
) -> Vec<GameMetadata> {
    let Ok(val) = serde_json::from_slice::<serde_json::Value>(body) else {
        return Vec::new();
    };
    let Some(items) = val
        .get("response")
        .and_then(|r| r.get("store_items"))
        .and_then(|s| s.as_array())
    else {
        return Vec::new();
    };

    let mut out = Vec::new();
    for item in items {
        let Some(appid) = item
            .get("appid")
            .or_else(|| item.get("id"))
            .and_then(|v| v.as_i64())
        else {
            continue;
        };
        let title = item
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        if title.is_empty() {
            continue;
        }

        let mut tags = Vec::new();
        let mut parsed_tag_ids = Vec::new();
        if let Some(tagids) = item.get("tagids").and_then(|t| t.as_array()) {
            for tid_val in tagids {
                if let Some(tid) = tid_val.as_i64() {
                    parsed_tag_ids.push(tid);
                    if let Some(names) = tag_map.get(&tid) {
                        tags.extend(names.iter().cloned());
                    }
                    for fallback in builtin_fallback_tags_for_id(tid) {
                        tags.push((*fallback).to_string());
                    }
                }
            }
        }
        if let Some(tag_objs) = item.get("tags").and_then(|t| t.as_array()) {
            for tobj in tag_objs {
                if let Some(tid) = tobj.get("tagid").and_then(|v| v.as_i64()) {
                    parsed_tag_ids.push(tid);
                    if let Some(names) = tag_map.get(&tid) {
                        tags.extend(names.iter().cloned());
                    }
                    for fallback in builtin_fallback_tags_for_id(tid) {
                        tags.push((*fallback).to_string());
                    }
                }
            }
        }

        let mut desc_ids = Vec::new();
        if let Some(cdids) = item.get("content_descriptorids").and_then(|d| d.as_array()) {
            for dv in cdids {
                if let Some(d) = dv.as_i64() {
                    desc_ids.push(d);
                }
            }
        }

        if item
            .get("is_free")
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
        {
            tags.push("Free to Play".to_string());
            tags.push("Gratuito para Jogar".to_string());
        }

        append_canonical_tag_aliases(&mut tags, &parsed_tag_ids, &desc_ids);

        out.push(GameMetadata {
            app_id: Some(appid),
            title,
            tags: db::normalize_term_list(&tags),
            genres: Vec::new(),
            categories: Vec::new(),
            source: "steam_browse_service".to_string(),
        });
    }
    out
}

pub fn parse_appdetails_json(appid: i64, body: &[u8]) -> Option<GameMetadata> {
    let val = serde_json::from_slice::<serde_json::Value>(body).ok()?;
    let key = appid.to_string();
    let entry = val.get(&key)?;
    if !entry.get("success").and_then(|v| v.as_bool()).unwrap_or(false) {
        return None;
    }
    let data = entry.get("data")?;
    let title = data.get("name").and_then(|v| v.as_str())?.trim().to_string();
    if title.is_empty() {
        return None;
    }

    let mut genres = Vec::new();
    if let Some(arr) = data.get("genres").and_then(|v| v.as_array()) {
        for g in arr {
            if let Some(desc) = g.get("description").and_then(|v| v.as_str()) {
                genres.push(desc.trim().to_string());
            }
        }
    }

    let mut categories = Vec::new();
    if let Some(arr) = data.get("categories").and_then(|v| v.as_array()) {
        for c in arr {
            if let Some(desc) = c.get("description").and_then(|v| v.as_str()) {
                categories.push(desc.trim().to_string());
            }
        }
    }

    let mut extra_tags = Vec::new();
    if data.get("is_free").and_then(|v| v.as_bool()).unwrap_or(false) {
        extra_tags.push("Free to Play".to_string());
        extra_tags.push("Gratuito para Jogar".to_string());
    }
    let mut desc_ids = Vec::new();
    if let Some(desc_arr) = data
        .get("content_descriptors")
        .and_then(|cd| cd.get("ids"))
        .and_then(|ids| ids.as_array())
    {
        for idv in desc_arr {
            if let Some(d) = idv.as_i64() {
                desc_ids.push(d);
            }
        }
    }
    append_canonical_tag_aliases(&mut extra_tags, &[], &desc_ids);

    Some(GameMetadata {
        app_id: Some(appid),
        title,
        tags: db::normalize_term_list(&extra_tags),
        genres: db::normalize_term_list(&genres),
        categories: db::normalize_term_list(&categories),
        source: "steam_appdetails".to_string(),
    })
}

#[derive(Clone, Debug, Default, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SteamTagSuggestion {
    pub tag_id: i64,
    pub canonical_en: String,
    pub display_name: String,
}

#[derive(Clone, Debug, Default, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SteamGameSuggestion {
    pub app_id: i64,
    pub title: String,
    pub tiny_image: String,
    pub source: String,
}

static GAME_AUTOCOMPLETE_CACHE: OnceLock<Mutex<HashMap<String, (i64, Vec<SteamGameSuggestion>)>>> =
    OnceLock::new();

const GAME_AUTOCOMPLETE_TTL_SECONDS: i64 = 300;

/// Pares bilíngues base (`English`, `Brazilian Portuguese`) usados como garantia offline e
/// padronização imediata antes mesmo do download completo do catálogo da Steam.
const BUILTIN_TAG_PAIRS: &[(&str, &str)] = &[
    ("Multiplayer", "Multijogador"),
    ("Online PvP", "JxJ On-line"),
    ("PvP", "JxJ"),
    ("FPS", "Tiro em Primeira Pessoa (FPS)"),
    ("Shooter", "Tiro"),
    ("First-Person", "Primeira Pessoa"),
    ("Third Person", "Terceira Pessoa"),
    ("Battle Royale", "Battle Royale"),
    ("MMORPG", "MMORPG"),
    ("MOBA", "MOBA"),
    ("Gacha", "Gacha"),
    ("NSFW", "Conteúdo Adulto"),
    ("Sexual Content", "Conteúdo Sexual"),
    ("Nudity", "Nudez"),
    ("Violent", "Violento"),
    ("Gore", "Sangue"),
    ("Anime", "Anime"),
    ("Free to Play", "Gratuito para Jogar"),
    ("Singleplayer", "Um Jogador"),
    ("Co-op", "Cooperativo"),
    ("Online Co-Op", "Cooperativo On-line"),
    ("Competitive", "Competitivo"),
    ("Roguelike", "Roguelike"),
    ("Roguelite", "Roguelite"),
    ("Souls-like", "Soulslike"),
    ("Survival", "Sobrevivência"),
    ("Survival Horror", "Terror de Sobrevivência"),
    ("Horror", "Terror"),
    ("Psychological Horror", "Terror Psicológico"),
    ("Action", "Ação"),
    ("Adventure", "Aventura"),
    ("RPG", "RPG"),
    ("Action RPG", "RPG de Ação"),
    ("Strategy", "Estratégia"),
    ("Simulation", "Simulação"),
    ("Open World", "Mundo Aberto"),
    ("Sandbox", "Sandbox"),
    ("Fighting", "Luta"),
    ("Racing", "Corrida"),
    ("Sports", "Esportes"),
    ("Stealth", "Furtivo"),
    ("Puzzle", "Quebra-Cabeça"),
    ("Platformer", "Plataforma"),
    ("Card Game", "Jogo de Cartas"),
    ("City Builder", "Construção de Cidades"),
    ("Casual", "Casual"),
    ("Indie", "Indie"),
    ("Early Access", "Acesso Antecipado"),
    ("Turn-Based", "Em Turnos"),
    ("Gambling", "Apostas"),
];

pub fn parse_storesearch_items_detailed(body: &[u8]) -> Vec<SteamGameSuggestion> {
    let Ok(val) = serde_json::from_slice::<serde_json::Value>(body) else {
        return Vec::new();
    };
    let Some(items) = val.get("items").and_then(|v| v.as_array()) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for item in items {
        let Some(id) = item.get("id").and_then(|v| v.as_i64()) else {
            continue;
        };
        let Some(name) = item.get("name").and_then(|v| v.as_str()) else {
            continue;
        };
        let clean_name = name.trim();
        if clean_name.is_empty() {
            continue;
        }
        let tiny = item
            .get("tiny_image")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        out.push(SteamGameSuggestion {
            app_id: id,
            title: clean_name.to_string(),
            tiny_image: tiny,
            source: "steam_storesearch".to_string(),
        });
    }
    out
}

pub fn parse_storesearch_json(body: &[u8]) -> Vec<(i64, String)> {
    parse_storesearch_items_detailed(body)
        .into_iter()
        .map(|s| (s.app_id, s.title))
        .collect()
}

fn cache_key_appid(appid: i64) -> String {
    format!("appid:{appid}")
}

fn cache_key_title(title: &str) -> String {
    format!("title:{}", normalize_match_text(title))
}

fn load_tag_map_from_db() -> (HashMap<i64, Vec<String>>, bool) {
    let Some(conn_mutex) = db::try_get_conn() else {
        return (HashMap::new(), true);
    };
    let now = now_utc();
    let conn = conn_mutex.lock();
    let mut stmt = match conn.prepare(
        "SELECT tag_id, name, updated_at_utc FROM steam_tag_catalog ORDER BY language ASC, tag_id ASC",
    ) {
        Ok(s) => s,
        Err(_) => return (HashMap::new(), true),
    };
    let mut map: HashMap<i64, Vec<String>> = HashMap::new();
    let mut newest = 0i64;
    let rows = stmt.query_map([], |r| {
        Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?, r.get::<_, i64>(2)?))
    });
    if let Ok(iter) = rows {
        for row in iter.flatten() {
            newest = newest.max(row.2);
            map.entry(row.0).or_default().push(row.1);
        }
    }
    let needs_refresh = map.is_empty() || (now - newest) > TAG_CATALOG_TTL_SECONDS;
    (map, needs_refresh)
}

fn save_tag_catalog_to_db(language: &str, tags: &[(i64, String)]) {
    if tags.is_empty() {
        return;
    }
    let now = now_utc();
    let mut conn = db::get_conn().lock();
    let Ok(tx) = conn.transaction() else {
        return;
    };
    {
        if let Ok(mut stmt) = tx.prepare(
            "INSERT INTO steam_tag_catalog (language, tag_id, name, updated_at_utc)
             VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(language, tag_id) DO UPDATE SET name = ?3, updated_at_utc = ?4",
        ) {
            for (id, name) in tags {
                let _ = stmt.execute(rusqlite::params![language, id, name, now]);
            }
        }
    }
    let _ = tx.commit();
}

pub async fn ensure_tag_catalog_cached_async() -> HashMap<i64, Vec<String>> {
    let (mut map, needs_refresh) = load_tag_map_from_db();
    if !needs_refresh && map.len() >= 435 {
        return map;
    }

    let store_base = steam_store_base();
    let api_base = steam_api_base();
    for lang in ["english", "brazilian"] {
        let tag_list_url = format!("{api_base}/IStoreService/GetTagList/v1/?language={lang}");
        let mut parsed = if let Ok(bytes) = fetch_url_bytes(&tag_list_url).await {
            parse_gettaglist_json(&bytes)
        } else {
            Vec::new()
        };
        if parsed.is_empty() {
            let pop_url = format!("{store_base}/tagdata/populartags/{lang}");
            if let Ok(bytes) = fetch_url_bytes(&pop_url).await {
                parsed = parse_populartags_json(&bytes);
            }
        }
        if !parsed.is_empty() {
            save_tag_catalog_to_db(lang, &parsed);
            for (id, name) in parsed {
                map.entry(id).or_default().push(name);
            }
        }
    }
    map
}

pub fn load_cached_metadata(cache_key: &str) -> Option<GameMetadata> {
    let now = now_utc();
    let conn = db::get_conn().lock();
    let row = conn
        .query_row(
            "SELECT app_id, title, tags_json, genres_json, categories_json, source, updated_at_utc
             FROM game_metadata_cache WHERE cache_key = ?1",
            [cache_key],
            |r| {
                Ok((
                    r.get::<_, Option<i64>>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, String>(3)?,
                    r.get::<_, String>(4)?,
                    r.get::<_, String>(5)?,
                    r.get::<_, i64>(6)?,
                ))
            },
        )
        .ok()?;
    if (now - row.6) > METADATA_TTL_SECONDS {
        return None;
    }
    Some(GameMetadata {
        app_id: row.0,
        title: row.1,
        tags: serde_json::from_str(&row.2).unwrap_or_default(),
        genres: serde_json::from_str(&row.3).unwrap_or_default(),
        categories: serde_json::from_str(&row.4).unwrap_or_default(),
        source: row.5,
    })
}

pub fn save_cached_metadata(cache_key: &str, meta: &GameMetadata) {
    let now = now_utc();
    let conn = db::get_conn().lock();
    let tags_json = serde_json::to_string(&meta.tags).unwrap_or_else(|_| "[]".to_string());
    let genres_json = serde_json::to_string(&meta.genres).unwrap_or_else(|_| "[]".to_string());
    let categories_json =
        serde_json::to_string(&meta.categories).unwrap_or_else(|_| "[]".to_string());
    let _ = conn.execute(
        "INSERT INTO game_metadata_cache
         (cache_key, app_id, title, tags_json, genres_json, categories_json, source, updated_at_utc)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
         ON CONFLICT(cache_key) DO UPDATE SET
            app_id = excluded.app_id,
            title = excluded.title,
            tags_json = excluded.tags_json,
            genres_json = excluded.genres_json,
            categories_json = excluded.categories_json,
            source = excluded.source,
            updated_at_utc = excluded.updated_at_utc",
        rusqlite::params![
            cache_key,
            meta.app_id,
            meta.title,
            tags_json,
            genres_json,
            categories_json,
            meta.source,
            now,
        ],
    );
}

fn merge_metadata(primary: GameMetadata, secondary: Option<GameMetadata>) -> GameMetadata {
    let Some(sec) = secondary else {
        return primary;
    };
    let mut tags = primary.tags;
    tags.extend(sec.tags);
    let mut genres = primary.genres;
    genres.extend(sec.genres);
    let mut categories = primary.categories;
    categories.extend(sec.categories);
    GameMetadata {
        app_id: primary.app_id.or(sec.app_id),
        title: if !primary.title.is_empty() { primary.title } else { sec.title },
        tags: db::normalize_term_list(&tags),
        genres: db::normalize_term_list(&genres),
        categories: db::normalize_term_list(&categories),
        source: if primary.source.is_empty() { sec.source } else { primary.source },
    }
}

pub async fn fetch_batch_by_appids_async(app_ids: &[i64]) -> HashMap<i64, GameMetadata> {
    let mut results = HashMap::new();
    let mut missing = Vec::new();
    let mut seen = HashSet::new();

    for &id in app_ids {
        if id <= 0 || !seen.insert(id) {
            continue;
        }
        if let Some(cached) = load_cached_metadata(&cache_key_appid(id)) {
            results.insert(id, cached);
        } else {
            missing.push(id);
        }
    }

    if missing.is_empty() {
        return results;
    }

    let tag_map = ensure_tag_catalog_cached_async().await;
    let api_base = steam_api_base();
    let store_base = steam_store_base();

    for chunk in missing.chunks(40) {
        let ids_json: Vec<serde_json::Value> =
            chunk.iter().map(|id| serde_json::json!({ "appid": id })).collect();
        let req_payload = serde_json::json!({
            "ids": ids_json,
            "context": { "language": "english", "country_code": "US", "steam_realm": 1 },
            "data_request": {
                "include_basic_info": true,
                "include_ratings": true,
                "include_tag_count": 20
            }
        });
        let url = format!(
            "{api_base}/IStoreBrowseService/GetItems/v1/?input_json={}",
            url_encode(&req_payload.to_string())
        );

        let mut chunk_map: HashMap<i64, GameMetadata> = HashMap::new();
        if let Ok(bytes) = fetch_url_bytes(&url).await {
            for m in parse_store_browse_items_json(&bytes, &tag_map) {
                if let Some(id) = m.app_id {
                    chunk_map.insert(id, m);
                }
            }
        }

        // Only fall back to `api/appdetails` (concurrently!) for items missed or tagless in GetItems
        let detail_ids: Vec<i64> = chunk
            .iter()
            .copied()
            .filter(|id| {
                chunk_map
                    .get(id)
                    .map(|m| m.tags.is_empty() && m.genres.is_empty())
                    .unwrap_or(true)
            })
            .take(8)
            .collect();
        if !detail_ids.is_empty() {
            let mut join_set = tokio::task::JoinSet::new();
            for id in detail_ids {
                let detail_url = format!("{store_base}/api/appdetails?appids={id}&l=english");
                join_set.spawn(async move {
                    let det = fetch_url_bytes(&detail_url)
                        .await
                        .ok()
                        .and_then(|bytes| parse_appdetails_json(id, &bytes));
                    (id, det)
                });
            }
            while let Some(joined) = join_set.join_next().await {
                if let Ok((id, Some(det))) = joined {
                    let merged = match chunk_map.remove(&id) {
                        Some(existing) => merge_metadata(existing, Some(det)),
                        None => det,
                    };
                    chunk_map.insert(id, merged);
                }
            }
        }

        for (id, meta) in chunk_map {
            save_cached_metadata(&cache_key_appid(id), &meta);
            if !meta.title.is_empty() && !is_generic_storefront_title(&meta.title) {
                save_cached_metadata(&cache_key_title(&meta.title), &meta);
            }
            results.insert(id, meta);
        }
    }

    results
}

async fn fetch_url_bytes_timeout(url: &str, timeout_ms: u64) -> Result<Vec<u8>, String> {
    tokio::time::timeout(Duration::from_millis(timeout_ms), fetch_url_bytes(url))
        .await
        .map_err(|_| format!("Timeout ({timeout_ms}ms) ao consultar {url}"))?
}

fn is_recent_miss(miss_key: &str) -> bool {
    let now = now_utc();
    GAME_MISS_CACHE
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
        .ok()
        .and_then(|map| map.get(miss_key).copied())
        .map(|ts| (now - ts) <= MISS_CACHE_TTL_SECONDS)
        .unwrap_or(false)
}

fn record_recent_miss(miss_key: &str) {
    if let Ok(mut guard) = GAME_MISS_CACHE
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
    {
        if guard.len() > 512 {
            let now = now_utc();
            guard.retain(|_, ts| (now - *ts) <= MISS_CACHE_TTL_SECONDS);
        }
        guard.insert(miss_key.to_string(), now_utc());
    }
}

fn clear_recent_miss(miss_key: &str) {
    if let Ok(mut guard) = GAME_MISS_CACHE
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
    {
        guard.remove(miss_key);
    }
}

fn has_nonempty_filter_terms(meta: &GameMetadata) -> bool {
    !meta.tags.is_empty() || !meta.genres.is_empty() || !meta.categories.is_empty()
}

/// Persists DOM-extracted tags for a game page while preserving existing API
/// metadata (`app_id`, `genres`, `categories`, and authoritative API `source`).
pub fn save_learned_dom_metadata(title: &str, site_tags: &[String]) {
    let clean_title = title.trim();
    if clean_title.is_empty() || is_generic_storefront_title(clean_title) || site_tags.is_empty() {
        return;
    }
    let canonical_tags = canonicalize_tags_to_english(site_tags);
    if canonical_tags.is_empty() {
        return;
    }
    let key = cache_key_title(clean_title);
    clear_recent_miss(&key);

    if let Some(mut existing) = load_cached_metadata(&key) {
        let mut combined_tags = existing.tags.clone();
        combined_tags.extend(canonical_tags);
        let deduped = db::normalize_term_list(&combined_tags);
        if deduped != existing.tags {
            existing.tags = deduped;
            save_cached_metadata(&key, &existing);
            if let Some(id) = existing.app_id.filter(|&id| id > 0) {
                save_cached_metadata(&cache_key_appid(id), &existing);
            }
        }
        return;
    }

    let learned = GameMetadata {
        app_id: None,
        title: clean_title.to_string(),
        tags: canonical_tags,
        genres: Vec::new(),
        categories: Vec::new(),
        source: "dom_learned".to_string(),
    };
    save_cached_metadata(&key, &learned);
}

fn decode_html_entities_basic(raw: &str) -> String {
    raw.replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&apos;", "'")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&nbsp;", " ")
        .trim()
        .to_string()
}

fn strip_html_tags_compact(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let mut in_tag = false;
    for ch in raw.chars() {
        match ch {
            '<' => in_tag = true,
            '>' => {
                in_tag = false;
                if !out.ends_with(' ') {
                    out.push(' ');
                }
            }
            _ if !in_tag => out.push(ch),
            _ => {}
        }
    }
    decode_html_entities_basic(&out)
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn extract_html_attr<'a>(tag_fragment: &'a str, attr_name: &str) -> Option<&'a str> {
    let lower = tag_fragment.to_ascii_lowercase();
    for quote in ['"', '\''] {
        let needle = format!("{attr_name}={quote}");
        if let Some(pos) = lower.find(&needle) {
            let start = pos + needle.len();
            if let Some(end) = tag_fragment[start..].find(quote) {
                return Some(&tag_fragment[start..start + end]);
            }
        }
    }
    None
}

fn extract_elements_by_class(html: &str, class_needle: &str) -> Vec<String> {
    let mut out = Vec::new();
    let lower = html.to_ascii_lowercase();
    let mut cursor = 0usize;
    while let Some(rel) = lower[cursor..].find(class_needle) {
        let hit = cursor + rel;
        let open_start = html[..hit].rfind('<');
        let tag_end = html[hit..].find('>').map(|d| hit + d + 1);
        if let (Some(ts), Some(te)) = (open_start, tag_end) {
            let tag_header = &html[ts..te];
            let tag_name = tag_header[1..]
                .split(|c: char| c.is_whitespace() || c == '>' || c == '/')
                .next()
                .unwrap_or("")
                .to_ascii_lowercase();
            if !tag_name.is_empty() {
                let close_needle = format!("</{tag_name}>");
                if let Some(close_rel) = lower[te..].find(&close_needle) {
                    out.push(html[te..te + close_rel].to_string());
                    cursor = te + close_rel + close_needle.len();
                    continue;
                }
            }
        }
        cursor = hit + class_needle.len();
    }
    out
}

/// Parses GOG public catalog search JSON into `(GameMetadata, cover_image_url)` items.
pub fn parse_gog_catalog_products(body: &[u8]) -> Vec<(GameMetadata, String)> {
    let Ok(val) = serde_json::from_slice::<serde_json::Value>(body) else {
        return Vec::new();
    };
    let Some(products) = val.get("products").and_then(|v| v.as_array()) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for item in products {
        let title = item
            .get("title")
            .and_then(|v| v.as_str())
            .map(str::trim)
            .unwrap_or("");
        if title.is_empty() {
            continue;
        }
        let mut raw_genres = Vec::new();
        if let Some(arr) = item.get("genres").and_then(|v| v.as_array()) {
            for g in arr {
                if let Some(name) = g.get("name").and_then(|v| v.as_str()) {
                    raw_genres.push(name.trim().to_string());
                }
            }
        }
        let mut raw_tags = Vec::new();
        if let Some(arr) = item.get("tags").and_then(|v| v.as_array()) {
            for t in arr {
                if let Some(name) = t.get("name").and_then(|v| v.as_str()) {
                    raw_tags.push(name.trim().to_string());
                }
            }
        }
        if let Some(arr) = item.get("features").and_then(|v| v.as_array()) {
            for f in arr {
                if let Some(name) = f.get("name").and_then(|v| v.as_str()) {
                    raw_tags.push(name.trim().to_string());
                }
            }
        }
        let image = item
            .get("coverHorizontal")
            .or_else(|| item.get("coverVertical"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        let meta = GameMetadata {
            app_id: None,
            title: title.to_string(),
            tags: canonicalize_tags_to_english(&raw_tags),
            genres: canonicalize_tags_to_english(&raw_genres),
            categories: Vec::new(),
            source: "gog_catalog".to_string(),
        };
        out.push((meta, image));
    }
    out
}

/// Computes the LizardByte GameDB bucket name (first 1-2 lowercase ASCII alphanumerics).
pub fn gamedb_bucket_key(title: &str) -> Option<String> {
    let alnum: String = compact_alnum(title)
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .collect();
    if alnum.is_empty() {
        None
    } else if alnum.len() == 1 {
        Some(alnum)
    } else {
        Some(alnum[..2].to_string())
    }
}

/// Parses a LizardByte GameDB bucket map `{ "<id>": { "name": "..." } }` into `(id, name)` pairs.
pub fn parse_gamedb_bucket_entries(body: &[u8]) -> Vec<(i64, String)> {
    let Ok(serde_json::Value::Object(map)) = serde_json::from_slice::<serde_json::Value>(body) else {
        return Vec::new();
    };
    let mut entries = Vec::with_capacity(map.len());
    for (k, v) in map {
        let Ok(id) = k.parse::<i64>() else {
            continue;
        };
        if let Some(name) = v.get("name").and_then(|n| n.as_str()) {
            let trimmed = name.trim();
            if !trimmed.is_empty() {
                entries.push((id, trimmed.to_string()));
            }
        }
    }
    entries
}

/// Parses a LizardByte GameDB game detail JSON into `(GameMetadata, cover_url)`.
pub fn parse_gamedb_game_json(body: &[u8]) -> Option<(GameMetadata, String)> {
    let val = serde_json::from_slice::<serde_json::Value>(body).ok()?;
    let title = val.get("name")?.as_str()?.trim();
    if title.is_empty() {
        return None;
    }

    let collect_names = |key: &str| -> Vec<String> {
        val.get(key)
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|item| item.get("name").and_then(|n| n.as_str()))
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect()
            })
            .unwrap_or_default()
    };

    let mut raw_genres = collect_names("genres");
    let mut raw_tags = collect_names("themes");
    let categories = canonicalize_tags_to_english(&collect_names("game_modes"));
    raw_genres.retain(|g| !g.is_empty());

    if let Some(ratings) = val.get("age_ratings").and_then(|v| v.as_array()) {
        for r in ratings {
            let rating = r
                .get("rating_category")
                .and_then(|rc| rc.get("rating"))
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim();
            let r_norm = normalize_match_text(rating);
            if r_norm == "ao" || r_norm == "adults only" || r_norm == "adult only" {
                raw_tags.push("NSFW".to_string());
                raw_tags.push("Adult Only".to_string());
            }
        }
    }

    let mut cover_url = val
        .get("cover")
        .and_then(|c| c.get("url"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();
    if cover_url.starts_with("//") {
        cover_url = format!("https:{cover_url}");
    }

    let meta = GameMetadata {
        app_id: None,
        title: title.to_string(),
        tags: canonicalize_tags_to_english(&raw_tags),
        genres: canonicalize_tags_to_english(&raw_genres),
        categories,
        source: "gamedb_igdb".to_string(),
    };
    Some((meta, cover_url))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ItchSearchCell {
    pub title: String,
    pub game_url: String,
    pub genres: Vec<String>,
    pub thumb_url: String,
}

fn floor_char_boundary(s: &str, max_idx: usize) -> usize {
    let mut i = max_idx.min(s.len());
    while i > 0 && !s.is_char_boundary(i) {
        i -= 1;
    }
    i
}

/// Parses bounded `.game_cell` blocks from `https://itch.io/search?q=...` HTML.
pub fn parse_itch_search_cells(body: &[u8]) -> Vec<ItchSearchCell> {
    let html = String::from_utf8_lossy(body);
    let lower = html.to_ascii_lowercase();
    let mut out = Vec::new();
    let mut cursor = 0usize;

    while let Some(pos) = lower[cursor..].find("game_cell") {
        let hit = cursor + pos;
        let Some(tag_start) = html[..hit].rfind("<div") else {
            cursor = hit + 9;
            continue;
        };
        let Some(tag_end_rel) = html[tag_start..].find('>') else {
            break;
        };
        let header = &html[tag_start..tag_start + tag_end_rel + 1];
        if !header.to_ascii_lowercase().contains("game_cell") {
            cursor = hit + 9;
            continue;
        }
        let next_cell = lower[tag_start + tag_end_rel..]
            .find("class=\"game_cell")
            .or_else(|| lower[tag_start + tag_end_rel..].find("class='game_cell"))
            .map(|d| tag_start + tag_end_rel + d)
            .unwrap_or_else(|| floor_char_boundary(&html, tag_start + 8000));
        let slice = &html[tag_start..next_cell];

        let mut game_url = String::new();
        let mut title = String::new();
        for title_block in extract_elements_by_class(slice, "game_title") {
            if let Some(a_pos) = title_block.to_ascii_lowercase().find("<a") {
                if let Some(a_end) = title_block[a_pos..].find('>') {
                    let a_tag = &title_block[a_pos..a_pos + a_end + 1];
                    if let Some(href) = extract_html_attr(a_tag, "href") {
                        game_url = decode_html_entities_basic(href);
                    }
                }
            }
            let cleaned = strip_html_tags_compact(&title_block);
            if !cleaned.is_empty() {
                title = cleaned;
                break;
            }
        }
        if game_url.is_empty() || title.is_empty() {
            let slice_l = slice.to_ascii_lowercase();
            if let Some(a_pos) = slice_l.find("class=\"title") {
                if let Some(open) = slice[..a_pos].rfind("<a") {
                    if let Some(close) = slice[open..].find('>') {
                        let a_tag = &slice[open..open + close + 1];
                        if game_url.is_empty() {
                            game_url = extract_html_attr(a_tag, "href")
                                .map(decode_html_entities_basic)
                                .unwrap_or_default();
                        }
                        if let Some(end_a) = slice_l[open + close..].find("</a>") {
                            let inner = strip_html_tags_compact(&slice[open + close + 1..open + close + end_a]);
                            if !inner.is_empty() {
                                title = inner;
                            }
                        }
                    }
                }
            }
        }

        let mut genres = Vec::new();
        for g in extract_elements_by_class(slice, "game_genre") {
            let clean_g = strip_html_tags_compact(&g);
            if !clean_g.is_empty() {
                genres.push(clean_g);
            }
        }
        let mut thumb_url = String::new();
        if let Some(img_pos) = slice.to_ascii_lowercase().find("<img") {
            if let Some(img_end) = slice[img_pos..].find('>') {
                let img_tag = &slice[img_pos..img_pos + img_end + 1];
                thumb_url = extract_html_attr(img_tag, "data-lazy_src")
                    .or_else(|| extract_html_attr(img_tag, "src"))
                    .map(decode_html_entities_basic)
                    .unwrap_or_default();
            }
        }

        if !title.is_empty() && !game_url.is_empty() {
            out.push(ItchSearchCell {
                title,
                game_url,
                genres,
                thumb_url,
            });
        }
        cursor = next_cell;
    }
    out
}

/// Parses `.game_info_panel_widget` `/games/tag-*`, `/games/genre-*` links and JSON-LD
/// metadata from an `itch.io` game detail HTML page.
pub fn parse_itch_game_page_html(fallback_title: &str, body: &[u8]) -> GameMetadata {
    let html = String::from_utf8_lossy(body);
    let lower = html.to_ascii_lowercase();
    let mut title = fallback_title.trim().to_string();

    if let Some(h1_start) = lower.find("<h1") {
        if let Some(h1_gt) = html[h1_start..].find('>') {
            let inner_start = h1_start + h1_gt + 1;
            if let Some(h1_end) = lower[inner_start..].find("</h1>") {
                let clean_h1 = strip_html_tags_compact(&html[inner_start..inner_start + h1_end]);
                if !clean_h1.is_empty() && !is_generic_storefront_title(&clean_h1) {
                    title = clean_h1;
                }
            }
        }
    }

    let mut raw_tags = Vec::new();
    let mut raw_genres = Vec::new();
    for marker in ["/games/tag-", "/games/genre-"] {
        let is_genre = marker == "/games/genre-";
        let mut cur = 0usize;
        while cur < lower.len() {
            let Some(rel) = lower[cur..].find(marker) else {
                break;
            };
            let hit = cur + rel;
            let slug_start = hit + marker.len();
            if slug_start > html.len() {
                break;
            }
            let end_href = html[slug_start..]
                .find(|c: char| matches!(c, '"' | '\'' | '?' | '#' | '/' | '<' | '>'))
                .map(|d| slug_start + d)
                .unwrap_or(slug_start);
            let slug = &html[slug_start..end_href];
            let decoded = clean_url_tag_token(slug);
            if !decoded.is_empty() {
                if is_genre {
                    raw_genres.push(decoded);
                } else {
                    raw_tags.push(decoded);
                }
            }
            if let Some(gt) = html[end_href..].find('>') {
                let inner_start = end_href + gt + 1;
                if let Some(close_a) = lower[inner_start..].find("</a>") {
                    let link_txt = strip_html_tags_compact(&html[inner_start..inner_start + close_a]);
                    if !link_txt.is_empty() && link_txt.len() <= 48 {
                        if is_genre {
                            raw_genres.push(link_txt);
                        } else {
                            raw_tags.push(link_txt);
                        }
                    }
                }
            }
            cur = (end_href + 1).min(html.len());
        }
    }

    // Extract JSON-LD `genre` and `keywords`
    let mut ld_cur = 0usize;
    while let Some(rel) = lower[ld_cur..].find("application/ld+json") {
        let hit = ld_cur + rel;
        let Some(gt) = html[hit..].find('>') else {
            break;
        };
        let content_start = hit + gt + 1;
        let Some(end_rel) = lower[content_start..].find("</script>") else {
            break;
        };
        let raw_json = html[content_start..content_start + end_rel].trim();
        if let Ok(val) = serde_json::from_str::<serde_json::Value>(raw_json) {
            let mut stack = vec![&val];
            while let Some(node) = stack.pop() {
                if let Some(arr) = node.as_array() {
                    for x in arr {
                        stack.push(x);
                    }
                    continue;
                }
                for key in ["genre", "keywords"] {
                    match node.get(key) {
                        Some(serde_json::Value::String(s)) => {
                            for part in s.split([',', ';']) {
                                let p = part.trim();
                                if !p.is_empty() {
                                    raw_tags.push(p.to_string());
                                }
                            }
                        }
                        Some(serde_json::Value::Array(arr)) => {
                            for el in arr {
                                if let Some(s) = el.as_str() {
                                    let p = s.trim();
                                    if !p.is_empty() {
                                        raw_tags.push(p.to_string());
                                    }
                                }
                            }
                        }
                        _ => {}
                    }
                }
                if let Some(graph) = node.get("@graph") {
                    stack.push(graph);
                }
            }
        }
        ld_cur = content_start + end_rel + 9;
    }

    GameMetadata {
        app_id: None,
        title,
        tags: canonicalize_tags_to_english(&raw_tags),
        genres: canonicalize_tags_to_english(&raw_genres),
        categories: Vec::new(),
        source: "itch_web".to_string(),
    }
}

async fn fetch_gog_catalog_metadata(title_hint: &str) -> Option<GameMetadata> {
    let url = format!(
        "{}/v1/catalog?limit=5&query=like:{}",
        gog_catalog_base(),
        url_encode(title_hint)
    );
    let bytes = fetch_url_bytes_timeout(&url, SECONDARY_PROVIDER_TIMEOUT_MS)
        .await
        .ok()?;
    let candidates = parse_gog_catalog_products(&bytes);
    candidates
        .into_iter()
        .map(|(m, _)| m)
        .find(|m| is_confident_title_match(title_hint, &m.title) && has_nonempty_filter_terms(m))
}

async fn fetch_gamedb_metadata(title_hint: &str) -> Option<GameMetadata> {
    let bucket = gamedb_bucket_key(title_hint)?;
    let base = gamedb_base();
    let bucket_url = format!("{base}/buckets/{bucket}.json");
    let bucket_bytes = fetch_url_bytes_timeout(&bucket_url, SECONDARY_PROVIDER_TIMEOUT_MS)
        .await
        .ok()?;
    let entries = parse_gamedb_bucket_entries(&bucket_bytes);

    let hint_compact = compact_alnum(title_hint);
    let mut matched: Vec<(i64, String)> = entries
        .into_iter()
        .filter(|(_, name)| is_confident_title_match(title_hint, name))
        .collect();
    matched.sort_by_key(|(_, name)| {
        let c = compact_alnum(name);
        (c != hint_compact, c.len())
    });
    let (game_id, _) = matched.into_iter().next()?;
    let detail_url = format!("{base}/games/{game_id}.json");
    let detail_bytes = fetch_url_bytes_timeout(&detail_url, SECONDARY_PROVIDER_TIMEOUT_MS)
        .await
        .ok()?;
    parse_gamedb_game_json(&detail_bytes)
        .map(|(m, _)| m)
        .filter(has_nonempty_filter_terms)
}

async fn fetch_itch_web_metadata(title_hint: &str) -> Option<GameMetadata> {
    let base = itch_base();
    let search_url = format!("{base}/search?q={}", url_encode(title_hint));
    let search_bytes = fetch_url_bytes_timeout(&search_url, SECONDARY_PROVIDER_TIMEOUT_MS)
        .await
        .ok()?;
    let cells = parse_itch_search_cells(&search_bytes);
    let matched = cells
        .into_iter()
        .find(|c| is_confident_title_match(title_hint, &c.title))?;

    let mut page_meta = None;
    let detail_url = if matched.game_url.starts_with("http://") || matched.game_url.starts_with("https://") {
        matched.game_url.clone()
    } else if matched.game_url.starts_with('/') {
        format!("{base}{}", matched.game_url)
    } else {
        String::new()
    };
    if !detail_url.is_empty() {
        if let Ok(detail_bytes) = fetch_url_bytes_timeout(&detail_url, SECONDARY_PROVIDER_TIMEOUT_MS).await {
            let parsed = parse_itch_game_page_html(&matched.title, &detail_bytes);
            if has_nonempty_filter_terms(&parsed) {
                page_meta = Some(parsed);
            }
        }
    }

    if let Some(mut m) = page_meta {
        if !matched.genres.is_empty() {
            let mut g = m.genres;
            g.extend(canonicalize_tags_to_english(&matched.genres));
            m.genres = db::normalize_term_list(&g);
        }
        return Some(m);
    }

    if !matched.genres.is_empty() {
        return Some(GameMetadata {
            app_id: None,
            title: matched.title,
            tags: Vec::new(),
            genres: canonicalize_tags_to_english(&matched.genres),
            categories: Vec::new(),
            source: "itch_web".to_string(),
        });
    }
    None
}

async fn resolve_steam_by_title_async(clean_title: &str) -> Option<GameMetadata> {
    let store_base = steam_store_base();
    let search_url = format!(
        "{store_base}/api/storesearch/?term={}&l=english&cc=us",
        url_encode(clean_title)
    );
    let bytes = fetch_url_bytes_timeout(&search_url, SECONDARY_PROVIDER_TIMEOUT_MS)
        .await
        .ok()?;
    let candidates = parse_storesearch_json(&bytes);
    let hint_compact = compact_alnum(clean_title);
    let matched_id = candidates
        .iter()
        .find(|(_, name)| compact_alnum(name) == hint_compact)
        .or_else(|| {
            candidates
                .iter()
                .find(|(_, name)| is_confident_title_match(clean_title, name))
        })
        .map(|(id, _)| *id)?;
    let mut map = fetch_batch_by_appids_async(&[matched_id]).await;
    map.remove(&matched_id)
}

pub async fn resolve_game_metadata_async(
    app_id: Option<i64>,
    title_hint: &str,
) -> Option<GameMetadata> {
    if let Some(id) = app_id.filter(|&id| id > 0) {
        let mut map = fetch_batch_by_appids_async(&[id]).await;
        if let Some(meta) = map.remove(&id) {
            return Some(meta);
        }
    }

    let clean_title = title_hint.trim();
    if clean_title.is_empty() || is_generic_storefront_title(clean_title) {
        return None;
    }
    let t_key = cache_key_title(clean_title);
    let prev_cached = load_cached_metadata(&t_key);
    // Page-learned (`dom_learned`) entries only hold the storefront's coarse genres
    // (e.g. Lutris "Action, RPG"), so they never short-circuit the API cascade.
    if let Some(cached) = prev_cached
        .as_ref()
        .filter(|m| has_nonempty_filter_terms(m) && !is_dom_learned_only(m))
    {
        return Some(cached.clone());
    }

    let prev_dom_learned = prev_cached.filter(|m| is_dom_learned_only(m));

    if is_recent_miss(&t_key) {
        return prev_dom_learned;
    }

    let resolved = match resolve_steam_by_title_async(clean_title).await {
        Some(m) if has_nonempty_filter_terms(&m) => Some(m),
        _ => match fetch_gog_catalog_metadata(clean_title).await {
            Some(m) => Some(m),
            None => match fetch_gamedb_metadata(clean_title).await {
                Some(m) => Some(m),
                None => fetch_itch_web_metadata(clean_title).await,
            },
        },
    };

    if let Some(api_meta) = resolved {
        clear_recent_miss(&t_key);
        let merged = merge_metadata(api_meta, prev_dom_learned);
        save_cached_metadata(&t_key, &merged);
        if !merged.title.is_empty() && !is_generic_storefront_title(&merged.title) {
            save_cached_metadata(&cache_key_title(&merged.title), &merged);
        }
        return Some(merged);
    }

    record_recent_miss(&t_key);
    prev_dom_learned
}

/// True when a cache entry was learned only from a storefront page's DOM and has
/// never been enriched by an API provider.
pub fn is_dom_learned_only(meta: &GameMetadata) -> bool {
    meta.source == "dom_learned"
}

pub fn resolve_game_metadata_blocking(
    app_id: Option<i64>,
    title_hint: &str,
) -> Option<GameMetadata> {
    let hint = title_hint.to_string();
    run_async_blocking(async move { resolve_game_metadata_async(app_id, &hint).await })
}

pub fn lookup_cached_only(app_id: Option<i64>, title_hint: &str) -> Option<GameMetadata> {
    if let Some(id) = app_id.filter(|&id| id > 0) {
        if let Some(m) = load_cached_metadata(&cache_key_appid(id)) {
            return Some(m);
        }
    }
    let clean = title_hint.trim();
    if !clean.is_empty() && !is_generic_storefront_title(clean) {
        if let Some(m) = load_cached_metadata(&cache_key_title(clean)) {
            return Some(m);
        }
    }
    None
}

fn load_bilingual_tag_catalog(display_lang: &str) -> Vec<SteamTagSuggestion> {
    let mut list: Vec<SteamTagSuggestion> = Vec::new();
    let mut seen_en: HashSet<String> = HashSet::new();

    if let Some(conn_mutex) = db::try_get_conn() {
        let conn = conn_mutex.lock();
        if let Ok(mut stmt) = conn.prepare(
            "SELECT en.tag_id, en.name, COALESCE(loc.name, en.name)
             FROM steam_tag_catalog en
             LEFT JOIN steam_tag_catalog loc
               ON loc.tag_id = en.tag_id AND loc.language = ?1
             WHERE en.language = 'english'
             ORDER BY en.tag_id ASC",
        ) {
            if let Ok(rows) = stmt.query_map([display_lang], |r| {
                Ok(SteamTagSuggestion {
                    tag_id: r.get(0)?,
                    canonical_en: r.get(1)?,
                    display_name: r.get(2)?,
                })
            }) {
                for row in rows.flatten() {
                    let key = normalize_match_text(&row.canonical_en);
                    if !key.is_empty() && seen_en.insert(key) {
                        list.push(row);
                    }
                }
            }
        };
    }

    // Completa/traduz pares base caso alguma tag esteja sem tradução local no banco ainda.
    let use_pt = !display_lang.eq_ignore_ascii_case("english");
    for (idx, (en, pt)) in BUILTIN_TAG_PAIRS.iter().enumerate() {
        let key = normalize_match_text(en);
        let desired_disp = if use_pt { *pt } else { *en };
        if let Some(existing) = list
            .iter_mut()
            .find(|item| normalize_match_text(&item.canonical_en) == key)
        {
            if use_pt
                && normalize_match_text(&existing.display_name)
                    == normalize_match_text(&existing.canonical_en)
            {
                existing.display_name = desired_disp.to_string();
            }
        } else if seen_en.insert(key) {
            list.push(SteamTagSuggestion {
                tag_id: -((idx as i64) + 1),
                canonical_en: (*en).to_string(),
                display_name: desired_disp.to_string(),
            });
        }
    }

    list
}

/// Converte uma tag digitada (em português, inglês ou variações de acento) para o nome
/// canônico em inglês esperado pela Steam API, mantendo entradas customizadas desconhecidas.
pub fn canonical_tag_to_english(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    let norm = normalize_match_text(trimmed);
    let compact = compact_alnum(trimmed);
    if matches!(
        norm.as_str(),
        "nsfw" | "adult" | "adult only" | "adults only" | "conteudo adulto" | "18+"
    ) {
        return "NSFW".to_string();
    }
    if norm == "rougelike" {
        return "Roguelike".to_string();
    }
    if matches!(
        norm.as_str(),
        "role-playing" | "role playing" | "role-playing (rpg)" | "role playing (rpg)"
    ) {
        return "RPG".to_string();
    }
    if norm == "simulator" {
        return "Simulation".to_string();
    }
    if norm == "hack and slash/beat 'em up" || norm == "hack and slash/beat em up" {
        return "Hack and Slash".to_string();
    }
    if norm == "real time strategy (rts)" {
        return "Strategy".to_string();
    }
    if norm == "point-and-click" {
        return "Point & Click".to_string();
    }
    if norm == "co-operative" || norm == "cooperative" {
        return "Co-op".to_string();
    }
    if norm == "single player" || norm == "single-player" {
        return "Singleplayer".to_string();
    }
    if norm == "erotic" {
        return "Sexual Content".to_string();
    }

    for entry in load_bilingual_tag_catalog("brazilian") {
        let en_norm = normalize_match_text(&entry.canonical_en);
        let disp_norm = normalize_match_text(&entry.display_name);
        if norm == en_norm || norm == disp_norm {
            return entry.canonical_en;
        }
        if !compact.is_empty()
            && (compact == compact_alnum(&entry.canonical_en)
                || compact == compact_alnum(&entry.display_name))
        {
            return entry.canonical_en;
        }
    }

    if let Some(conn_mutex) = db::try_get_conn() {
        let conn = conn_mutex.lock();
        let found: Option<String> = conn
            .prepare(
                "SELECT en.name
                 FROM steam_tag_catalog any_lang
                 JOIN steam_tag_catalog en
                   ON en.tag_id = any_lang.tag_id AND en.language = 'english'
                 WHERE lower(any_lang.name) = lower(?1)
                 LIMIT 1",
            )
            .ok()
            .and_then(|mut stmt| stmt.query_row([trimmed], |r| r.get::<_, String>(0)).ok());
        if let Some(canonical) = found {
            return canonical;
        }
    }

    trimmed.to_string()
}

pub fn canonicalize_tags_to_english(tags: &[String]) -> Vec<String> {
    let mapped: Vec<String> = tags
        .iter()
        .map(|t| canonical_tag_to_english(t))
        .filter(|t| !t.is_empty())
        .collect();
    db::normalize_term_list(&mapped)
}

pub fn display_name_for_canonical_tag(tag: &str, display_lang: &str) -> String {
    let trimmed = tag.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    let canonical = canonical_tag_to_english(trimmed);
    let norm_can = normalize_match_text(&canonical);
    let norm_raw = normalize_match_text(trimmed);

    for entry in load_bilingual_tag_catalog(display_lang) {
        let entry_can = normalize_match_text(&entry.canonical_en);
        let entry_disp = normalize_match_text(&entry.display_name);
        if norm_can == entry_can || norm_raw == entry_can || norm_raw == entry_disp {
            return entry.display_name;
        }
    }
    trimmed.to_string()
}

pub fn translate_tags_for_display(tags: &[String], display_lang: &str) -> HashMap<String, String> {
    let catalog = load_bilingual_tag_catalog(display_lang);
    let mut by_en: HashMap<String, String> = HashMap::with_capacity(catalog.len() * 2);
    for entry in &catalog {
        by_en.insert(normalize_match_text(&entry.canonical_en), entry.display_name.clone());
        by_en.insert(normalize_match_text(&entry.display_name), entry.display_name.clone());
    }
    let mut out = HashMap::new();
    for t in tags {
        let key = t.trim();
        if key.is_empty() {
            continue;
        }
        let norm_can = normalize_match_text(&canonical_tag_to_english(key));
        let disp = by_en
            .get(&norm_can)
            .or_else(|| by_en.get(&normalize_match_text(key)))
            .cloned()
            .unwrap_or_else(|| key.to_string());
        out.insert(key.to_string(), disp);
    }
    out
}

pub fn get_popular_steam_tags_localized(display_lang: &str) -> Vec<SteamTagSuggestion> {
    let catalog = load_bilingual_tag_catalog(display_lang);
    let mut out = Vec::new();
    let mut seen = HashSet::new();

    // Prioriza os pares populares curados primeiro para UX consistente no idioma principal
    for (en, _) in BUILTIN_TAG_PAIRS {
        let en_norm = normalize_match_text(en);
        if let Some(found) = catalog
            .iter()
            .find(|c| normalize_match_text(&c.canonical_en) == en_norm)
        {
            if seen.insert(en_norm) {
                out.push(found.clone());
            }
        }
    }
    for item in catalog {
        if out.len() >= 80 {
            break;
        }
        let key = normalize_match_text(&item.canonical_en);
        if seen.insert(key) {
            out.push(item);
        }
    }
    out
}

pub fn get_popular_steam_tags() -> Vec<String> {
    let (lang, _) = db::get_steam_language_and_country();
    get_popular_steam_tags_localized(lang)
        .into_iter()
        .map(|s| s.display_name)
        .collect()
}

pub async fn search_tag_suggestions_async(
    query: &str,
    display_lang: &str,
    limit: usize,
) -> Vec<SteamTagSuggestion> {
    let limit = limit.clamp(1, 50);
    // Garante catálogo atualizado em segundo plano / rapidamente sem travar caso offline
    let _ = tokio::time::timeout(
        Duration::from_secs(2),
        ensure_tag_catalog_cached_async(),
    )
    .await;

    let catalog = load_bilingual_tag_catalog(display_lang);
    let q_norm = normalize_match_text(query);
    if q_norm.is_empty() {
        return get_popular_steam_tags_localized(display_lang)
            .into_iter()
            .take(limit)
            .collect();
    }

    let mut scored: Vec<(i32, i64, SteamTagSuggestion)> = Vec::new();
    for (idx, item) in catalog.into_iter().enumerate() {
        let disp_norm = normalize_match_text(&item.display_name);
        let en_norm = normalize_match_text(&item.canonical_en);

        let rank = if disp_norm == q_norm || en_norm == q_norm {
            0
        } else if disp_norm.starts_with(&q_norm) || en_norm.starts_with(&q_norm) {
            1
        } else if disp_norm
            .split(|c: char| !c.is_alphanumeric())
            .any(|w| w.starts_with(&q_norm))
            || en_norm
                .split(|c: char| !c.is_alphanumeric())
                .any(|w| w.starts_with(&q_norm))
        {
            2
        } else if disp_norm.contains(&q_norm) || en_norm.contains(&q_norm) {
            3
        } else {
            continue;
        };

        let priority = if item.tag_id < 0 {
            idx as i64
        } else {
            1000 + item.tag_id
        };
        scored.push((rank, priority, item));
    }

    scored.sort_by(|a, b| {
        a.0.cmp(&b.0)
            .then_with(|| a.1.cmp(&b.1))
            .then_with(|| a.2.display_name.len().cmp(&b.2.display_name.len()))
    });
    scored.into_iter().take(limit).map(|(_, _, item)| item).collect()
}

pub fn search_tag_suggestions_sync(
    query: &str,
    display_lang: &str,
    limit: usize,
) -> Vec<SteamTagSuggestion> {
    let q = query.to_string();
    let lang = display_lang.to_string();
    run_async_blocking(async move { search_tag_suggestions_async(&q, &lang, limit).await })
}

pub async fn search_game_suggestions_async(
    query: &str,
    display_lang: &str,
    country: &str,
    limit: usize,
) -> Vec<SteamGameSuggestion> {
    let limit = limit.clamp(1, 30);
    let clean_q = query.trim();
    if clean_q.len() < 2 {
        return Vec::new();
    }

    let q_norm = normalize_match_text(clean_q);
    let cache_key = format!("{display_lang}:{country}:{q_norm}");
    let now = now_utc();

    if let Some(cached) = GAME_AUTOCOMPLETE_CACHE
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
        .ok()
        .and_then(|map| map.get(&cache_key).cloned())
        .filter(|(ts, _)| (now - *ts) <= GAME_AUTOCOMPLETE_TTL_SECONDS)
    {
        return cached.1.into_iter().take(limit).collect();
    }

    let store_base = steam_store_base();
    let steam_search_url = format!(
        "{store_base}/api/storesearch/?term={}&l={}&cc={}",
        url_encode(clean_q),
        url_encode(display_lang),
        url_encode(country)
    );
    let gog_search_url = format!(
        "{}/v1/catalog?limit=8&query=like:{}",
        gog_catalog_base(),
        url_encode(clean_q)
    );
    let gamedb_bucket_url = gamedb_bucket_key(clean_q)
        .map(|b| format!("{}/buckets/{b}.json", gamedb_base()));

    let steam_task = tokio::spawn(async move {
        fetch_url_bytes_timeout(&steam_search_url, SECONDARY_PROVIDER_TIMEOUT_MS).await
    });
    let gog_task = tokio::spawn(async move {
        fetch_url_bytes_timeout(&gog_search_url, SECONDARY_PROVIDER_TIMEOUT_MS).await
    });
    let gamedb_task = tokio::spawn(async move {
        match gamedb_bucket_url {
            Some(u) => fetch_url_bytes_timeout(&u, SECONDARY_PROVIDER_TIMEOUT_MS).await.ok(),
            None => None,
        }
    });

    let steam_res = steam_task.await.unwrap_or_else(|e| Err(e.to_string()));
    let gog_res = gog_task.await.unwrap_or_else(|e| Err(e.to_string()));
    let gamedb_res = gamedb_task.await.unwrap_or(None);

    let mut results = Vec::new();
    let mut seen_ids = HashSet::new();
    let mut seen_titles = HashSet::new();

    if let Ok(bytes) = steam_res {
        for item in parse_storesearch_items_detailed(&bytes) {
            let norm_t = normalize_match_text(&item.title);
            if seen_ids.insert(item.app_id) && seen_titles.insert(norm_t) {
                results.push(item);
            }
        }
    }

    if let Ok(bytes) = gog_res {
        for (meta, img) in parse_gog_catalog_products(&bytes) {
            let norm_t = normalize_match_text(&meta.title);
            if seen_titles.insert(norm_t) {
                results.push(SteamGameSuggestion {
                    app_id: 0,
                    title: meta.title,
                    tiny_image: img,
                    source: "GOG".to_string(),
                });
            }
        }
    }

    if let Some(bytes) = gamedb_res {
        let mut matches: Vec<(i64, String)> = parse_gamedb_bucket_entries(&bytes)
            .into_iter()
            .filter(|(_, name)| {
                let norm = normalize_match_text(name);
                norm.contains(&q_norm)
            })
            .collect();
        matches.sort_by_key(|(_, name)| {
            let norm = normalize_match_text(name);
            (!norm.starts_with(&q_norm), norm.len())
        });
        for (_, name) in matches.into_iter().take(6) {
            let norm_t = normalize_match_text(&name);
            if seen_titles.insert(norm_t) {
                results.push(SteamGameSuggestion {
                    app_id: 0,
                    title: name,
                    tiny_image: String::new(),
                    source: "IGDB (GameDB)".to_string(),
                });
            }
        }
    }

    let has_exact_pc_match = results.iter().any(|r| compact_alnum(&r.title) == compact_alnum(clean_q));
    if (results.len() < limit || !has_exact_pc_match) && clean_q.chars().count() >= 3 {
        let itch_url = format!("{}/search?q={}", itch_base(), url_encode(clean_q));
        if let Ok(bytes) = fetch_url_bytes_timeout(&itch_url, SECONDARY_PROVIDER_TIMEOUT_MS).await {
            for cell in parse_itch_search_cells(&bytes).into_iter().take(6) {
                let norm_t = normalize_match_text(&cell.title);
                if seen_titles.insert(norm_t) {
                    results.push(SteamGameSuggestion {
                        app_id: 0,
                        title: cell.title,
                        tiny_image: cell.thumb_url,
                        source: "Itch.io".to_string(),
                    });
                }
            }
        }
    }

    // Completa com jogos instalados localmente que correspondam à busca caso offline/novo título
    for installed in crate::launchers::discover_installed_games(false) {
        let norm_t = normalize_match_text(&installed.title);
        if !norm_t.contains(&q_norm) {
            continue;
        }
        let app_id = installed.app_id.unwrap_or(0);
        if (app_id > 0 && !seen_ids.insert(app_id)) || !seen_titles.insert(norm_t) {
            continue;
        }
        results.push(SteamGameSuggestion {
            app_id,
            title: installed.title,
            tiny_image: String::new(),
            source: installed.launcher,
        });
    }

    if !results.is_empty() {
        if let Ok(mut guard) = GAME_AUTOCOMPLETE_CACHE
            .get_or_init(|| Mutex::new(HashMap::new()))
            .lock()
        {
            if guard.len() > 250 {
                guard.clear();
            }
            guard.insert(cache_key, (now, results.clone()));
        }
    }

    results.into_iter().take(limit).collect()
}

pub fn search_game_suggestions_sync(
    query: &str,
    display_lang: &str,
    country: &str,
    limit: usize,
) -> Vec<SteamGameSuggestion> {
    let q = query.to_string();
    let lang = display_lang.to_string();
    let cc = country.to_string();
    run_async_blocking(async move { search_game_suggestions_async(&q, &lang, &cc, limit).await })
}

fn tag_matches(blocked_norm: &str, blocked_compact: &str, candidate: &str) -> bool {
    let cand_norm = normalize_match_text(candidate);
    if cand_norm.is_empty() || blocked_norm.is_empty() {
        return false;
    }
    if cand_norm == blocked_norm {
        return true;
    }
    if is_umbrella_adult_tag(blocked_norm) && is_explicit_adult_candidate(&cand_norm) {
        return true;
    }
    let cand_compact = compact_alnum(candidate);
    if !blocked_compact.is_empty() && cand_compact == blocked_compact {
        return true;
    }
    blocked_norm.len() >= 4 && cand_norm.contains(blocked_norm)
}

/// Checks whether a game's title, visible site tags, or Steam API metadata match active filters.
/// Returns `Some(("NOME" | "TAG", matched_term))` if blocked.
pub fn match_game_against_filters(
    title: &str,
    site_tags: &[String],
    meta: Option<&GameMetadata>,
    filters: &db::FocusFilters,
) -> Option<(String, String)> {
    if !filters.launcher_filter_enabled {
        return None;
    }

    let mut titles_to_check = Vec::new();
    let mut titles_compact = Vec::new();
    if !title.trim().is_empty() {
        titles_to_check.push(normalize_match_text(title));
        titles_compact.push(compact_alnum(title));
    }
    if let Some(m) = meta {
        if !m.title.trim().is_empty() {
            titles_to_check.push(normalize_match_text(&m.title));
            titles_compact.push(compact_alnum(&m.title));
        }
    }

    for blocked_name in &filters.launcher_blocked_names {
        let needle = normalize_match_text(blocked_name);
        let needle_compact = compact_alnum(blocked_name);
        if needle.is_empty() {
            continue;
        }
        if titles_to_check.iter().any(|t| t.contains(&needle))
            || (needle_compact.len() >= 3 && titles_compact.iter().any(|tc| tc.contains(&needle_compact)))
        {
            return Some(("NOME".to_string(), blocked_name.clone()));
        }
    }

    let mut candidate_terms: Vec<String> = Vec::with_capacity(site_tags.len() * 2 + 16);
    for t in site_tags {
        candidate_terms.push(t.clone());
        let can = canonical_tag_to_english(t);
        if !can.is_empty() {
            candidate_terms.push(can);
        }
    }
    if let Some(m) = meta {
        candidate_terms.extend(m.all_filter_terms());
    }

    for blocked_tag in &filters.launcher_blocked_tags {
        let canonical = canonical_tag_to_english(blocked_tag);
        let b_norm = normalize_match_text(&canonical);
        let b_compact = compact_alnum(&canonical);
        let raw_norm = normalize_match_text(blocked_tag);
        let raw_compact = compact_alnum(blocked_tag);
        if candidate_terms.iter().any(|cand| {
            tag_matches(&b_norm, &b_compact, cand)
                || (raw_norm != b_norm && tag_matches(&raw_norm, &raw_compact, cand))
        }) {
            return Some(("TAG".to_string(), canonical));
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_appid_from_urls() {
        assert_eq!(
            extract_steam_appid_from_url("https://store.steampowered.com/app/730/CounterStrike_2/"),
            Some(730)
        );
        assert_eq!(
            extract_steam_appid_from_url("https://steamcommunity.com/app/1145360/discussions/"),
            Some(1145360)
        );
        assert_eq!(
            extract_steam_appid_from_url("https://steamcommunity.com/sharedfiles/filedetails/?id=123&appid=570"),
            Some(570)
        );
        assert_eq!(
            extract_steam_appid_from_url("https://store.steampowered.com/login/?redir=app%2F339800%2FHuniePop%2F&snr=1_agecheck"),
            Some(339800)
        );
        assert_eq!(
            extract_steam_appid_from_url("https://store.steampowered.com/agecheck/app/339800/"),
            Some(339800)
        );
        assert_eq!(
            extract_steam_appid_from_url("https://store.steampowered.com/"),
            None
        );

        let tag_hub = extract_launcher_url_hint("store.steampowered.com", "/tags/pt/Conte%C3%BAdo%20Adulto/");
        assert!(tag_hub.is_some());
        let (_, _, tags_hub, is_search) = tag_hub.unwrap();
        assert!(!is_search);
        assert!(tags_hub.iter().any(|t| t == "Conteúdo Adulto"));

        let search_tags = extract_launcher_url_hint("store.steampowered.com", "/search/?tags=9130");
        assert!(search_tags.is_some());
        let (_, _, tags_qs, _) = search_tags.unwrap();
        assert!(tags_qs.iter().any(|t| t == "Hentai"));
    }

    #[test]
    fn test_steam_api_json_parsers_and_matching() {
        let popular_json = br#"[{"tagid":19,"name":"Action"},{"tagid":1663,"name":"FPS"}]"#;
        let tags = parse_populartags_json(popular_json);
        assert_eq!(tags, vec![(19, "Action".to_string()), (1663, "FPS".to_string())]);

        let taglist_json = br#"{"response":{"tags":[{"tagid":40500,"name":"Sexual Themes"}]}}"#;
        assert_eq!(parse_gettaglist_json(taglist_json), vec![(40500, "Sexual Themes".to_string())]);

        let mut catalog = HashMap::new();
        catalog.insert(19, vec!["Action".to_string(), "Ação".to_string()]);
        catalog.insert(1663, vec!["FPS".to_string()]);
        catalog.insert(9130, vec!["Hentai".to_string()]);

        let browse_json = br#"{
          "response": {
            "store_items": [
              { "appid": 730, "name": "Counter-Strike 2", "tagids": [19, 1663] },
              { "appid": 339800, "name": "HuniePop", "tagids": [9130], "content_descriptorids": [1, 3, 4] }
            ]
          }
        }"#;
        let parsed_browse = parse_store_browse_items_json(browse_json, &catalog);
        assert_eq!(parsed_browse.len(), 2);
        let cs2 = &parsed_browse[0];
        assert_eq!(cs2.app_id, Some(730));
        assert_eq!(cs2.title, "Counter-Strike 2");
        assert!(cs2.tags.iter().any(|t| t == "FPS"));
        assert!(cs2.tags.iter().any(|t| t == "Ação"));

        let hunie = &parsed_browse[1];
        assert!(hunie.tags.iter().any(|t| t == "NSFW"));
        assert!(hunie.tags.iter().any(|t| t == "Conteúdo Adulto"));

        let appdetails_json = r#"{
          "1145360": {
            "success": true,
            "data": {
              "steam_appid": 1145360,
              "name": "Hades",
              "genres": [{"id":"1","description":"Ação"},{"id":"23","description":"Indie"}],
              "categories": [{"id":2,"description":"Um jogador"}]
            }
          }
        }"#
        .as_bytes();
        let hades = parse_appdetails_json(1145360, appdetails_json).expect("appdetails parsed");
        assert_eq!(hades.title, "Hades");
        assert!(hades.genres.contains(&"Ação".to_string()));

        let search_json = br#"{"total":1,"items":[{"id":367520,"name":"Hollow Knight","tiny_image":"https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/367520/capsule_sm_120.jpg"}]}"#;
        let hits = parse_storesearch_json(search_json);
        assert_eq!(hits, vec![(367520, "Hollow Knight".to_string())]);
        let detailed_hits = parse_storesearch_items_detailed(search_json);
        assert_eq!(detailed_hits.len(), 1);
        assert_eq!(detailed_hits[0].app_id, 367520);
        assert_eq!(detailed_hits[0].title, "Hollow Knight");
        assert!(detailed_hits[0].tiny_image.contains("capsule_sm_120.jpg"));

        // Matching with canonical English conversion, localized DOM tags ("Ação" vs canonical "Action"), adult aliases, and game name
        assert_eq!(canonical_tag_to_english("acao"), "Action");
        assert_eq!(canonical_tag_to_english("Conteúdo Adulto"), "NSFW");
        assert_eq!(display_name_for_canonical_tag("Action", "brazilian"), "Ação");
        assert_eq!(display_name_for_canonical_tag("Action", "english"), "Action");
        let disp_map = translate_tags_for_display(&["Action".to_string(), "NSFW".to_string()], "brazilian");
        assert_eq!(disp_map.get("Action").map(String::as_str), Some("Ação"));
        assert_eq!(disp_map.get("NSFW").map(String::as_str), Some("Conteúdo Adulto"));

        let mut filters = db::FocusFilters::default();
        filters.launcher_filter_enabled = true;
        filters.launcher_blocked_tags = vec!["acao".to_string()];
        assert_eq!(
            match_game_against_filters("Hades", &[], Some(&hades), &filters),
            Some(("TAG".to_string(), "Action".to_string()))
        );

        // Canonical EN tag in filters must also match localized DOM tag ("Ação") even without SteamMetadata
        filters.launcher_blocked_tags = vec!["Action".to_string()];
        assert_eq!(
            match_game_against_filters("Hades", &["Ação".to_string()], None, &filters),
            Some(("TAG".to_string(), "Action".to_string()))
        );

        filters.launcher_blocked_tags = vec!["Conteúdo Adulto".to_string()];
        assert_eq!(
            match_game_against_filters("HuniePop", &[], Some(hunie), &filters),
            Some(("TAG".to_string(), "NSFW".to_string()))
        );

        assert!(is_generic_storefront_title("Steam Search"));
        assert!(!is_generic_storefront_title("HuniePop"));

        filters.launcher_blocked_tags.clear();
        filters.launcher_blocked_names = vec!["counter strike".to_string()];
        assert_eq!(
            match_game_against_filters("Counter-Strike 2", &[], Some(cs2), &filters),
            Some(("NOME".to_string(), "counter strike".to_string()))
        );

        filters.launcher_filter_enabled = false;
        assert_eq!(
            match_game_against_filters("Counter-Strike 2", &[], Some(cs2), &filters),
            None
        );
    }

    #[test]
    fn test_external_parsers_url_hints_and_tag_aliases() {
        assert_eq!(
            normalize_match_text("Hades | Download and Buy Today - Epic Games Store"),
            "hades"
        );
        assert_eq!(
            normalize_match_text("Hollow Knight | Baixe e compre hoje - Epic Games Store"),
            "hollow knight"
        );
        assert_eq!(
            normalize_match_text("Heroes of Might and Magic® 3: Complete on GOG.com"),
            "heroes of might and magic 3: complete"
        );
        assert_eq!(normalize_match_text("Celeste - Lutris"), "celeste");
        assert_eq!(normalize_match_text("Epic Games Store"), "epic games store");
        assert!(is_confident_title_match(
            "Hades | Download and Buy Today - Epic Games Store",
            "Hades"
        ));
        // GOG Catalog parser + trademark folding + tag canonicalization
        let gog_json = r#"{
          "products": [
            {
              "id": "1207658787",
              "title": "Heroes of Might and Magic® 3: Complete",
              "coverHorizontal": "https://images.gog-statics.com/h3_h.jpg",
              "coverVertical": "https://images.gog-statics.com/h3_v.jpg",
              "genres": [{"name": "Strategy"}, {"name": "Role-playing"}],
              "tags": [{"name": "Fantasy"}, {"name": "Turn-based"}],
              "features": [{"name": "Single-player"}]
            }
          ]
        }"#
        .as_bytes();
        let gog_parsed = parse_gog_catalog_products(gog_json);
        assert_eq!(gog_parsed.len(), 1);
        assert_eq!(gog_parsed[0].0.source, "gog_catalog");
        assert!(gog_parsed[0].0.genres.contains(&"Strategy".to_string()));
        assert!(gog_parsed[0].0.genres.contains(&"RPG".to_string()));
        assert!(gog_parsed[0].0.tags.contains(&"Singleplayer".to_string()));
        assert_eq!(gog_parsed[0].1, "https://images.gog-statics.com/h3_h.jpg");
        assert!(is_confident_title_match(
            "Heroes of Might and Magic 3: Complete",
            "Heroes of Might and Magic® 3: Complete"
        ));

        // GameDB buckets (1-char vs 2-char) & JSON parser + ESRB Mature vs Adults Only
        assert_eq!(gamedb_bucket_key("I"), Some("i".to_string()));
        assert_eq!(gamedb_bucket_key("Minecraft"), Some("mi".to_string()));
        assert_eq!(gamedb_bucket_key("!!!"), None);

        let bucket_json = br#"{"100":{"name":"The Binding of Isaac: Rebirth"},"200":{"name":"Tactics"}}"#;
        let bucket_entries = parse_gamedb_bucket_entries(bucket_json);
        assert_eq!(bucket_entries.len(), 2);

        let gamedb_mature = br#"{
          "name": "Dark Dungeon",
          "genres": [{"name": "Role-playing (RPG)"}],
          "themes": [{"name": "Dark Fantasy"}, {"name": "Action"}],
          "game_modes": [{"name": "Single player"}],
          "age_ratings": [{"rating_category": {"rating": "M"}}],
          "cover": {"url": "//images.igdb.com/igdb/image/upload/t_thumb/co1234.jpg"}
        }"#;
        let (m_meta, m_cover) = parse_gamedb_game_json(gamedb_mature).expect("gamedb mature");
        assert!(m_meta.genres.contains(&"RPG".to_string()));
        assert!(!m_meta.tags.iter().any(|t| t == "NSFW"), "ESRB M must not auto-tag NSFW");
        assert_eq!(m_cover, "https://images.igdb.com/igdb/image/upload/t_thumb/co1234.jpg");

        let gamedb_ao = br#"{
          "name": "Adults Only Visual Novel",
          "age_ratings": [{"rating_category": {"rating": "AO"}}]
        }"#;
        let (ao_meta, _) = parse_gamedb_game_json(gamedb_ao).expect("gamedb ao");
        assert!(ao_meta.tags.iter().any(|t| t == "NSFW"));

        // Itch search & detail HTML + JSON-LD parser
        let itch_search_html = br#"
          <div class="game_cell" data-game_id="999">
            <a class="title game_link" href="https://dev.itch.io/celeste-classic">Celeste Classic</a>
            <div class="game_genre">Platformer</div>
          </div>"#;
        let itch_cells = parse_itch_search_cells(itch_search_html);
        assert_eq!(itch_cells.len(), 1);
        assert_eq!(itch_cells[0].title, "Celeste Classic");
        assert!(itch_cells[0].genres.contains(&"Platformer".to_string()));

        let itch_detail_html = br#"
          <html><head>
            <script type="application/ld+json">{"@type":"VideoGame","genre":"Roguelike"}</script>
          </head><body>
            <div class="game_info_panel_widget"><table>
              <tr><td>Genre</td><td><a href="https://itch.io/games/genre-action">Action</a></td></tr>
              <tr><td>Tags</td><td><a href="/games/tag-roguelite">Roguelite</a><a>Pixel Art</a></td></tr>
            </table></div>
          </body></html>"#;
        let itch_meta = parse_itch_game_page_html("Celeste Classic", itch_detail_html);
        assert_eq!(itch_meta.source, "itch_web");
        assert!(itch_meta.genres.contains(&"Action".to_string()));
        assert!(itch_meta.tags.contains(&"Roguelike".to_string()));
        assert!(itch_meta.tags.contains(&"Roguelite".to_string()));

        // URL hints across GOG (including rougelike typo), Epic, Lutris, and Itch
        let gog_hint = extract_launcher_url_hint("www.gog.com", "/en/games?genres=rougelike").expect("gog hint");
        assert!(gog_hint.2.contains(&"Roguelike".to_string()));
        let epic_hint = extract_launcher_url_hint("store.epicgames.com", "/en-US/p/hades").expect("epic hint");
        assert_eq!(epic_hint.1.to_lowercase(), "hades");
        let lutris_hint = extract_launcher_url_hint("lutris.net", "/games/genre/roguelike").expect("lutris genre");
        assert!(lutris_hint.2.iter().any(|t| t.eq_ignore_ascii_case("roguelike")));
        let itch_hint = extract_launcher_url_hint("itch.io", "/games/tag-roguelike").expect("itch tag");
        assert!(itch_hint.2.iter().any(|t| t.eq_ignore_ascii_case("roguelike")));

        assert!(is_generic_storefront_title("Epic Games Store"));
        assert!(is_generic_storefront_title("GOG.com"));
        assert!(is_generic_storefront_title("Lutris"));
        assert!(is_generic_storefront_title("Top free games on itch.io"));
        assert_eq!(source_display_label("gog"), "GOG");
        assert_eq!(source_display_label("gamedb"), "IGDB");
        assert_eq!(source_display_label("itch"), "Itch.io");
        assert_eq!(source_display_label("dom_learned"), "Página");
    }

    #[test]
    fn test_multiprovider_cascade_dom_learned_merge_and_miss_cache() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db_file = format!("/tmp/chronos_steam_cascade_{}.db", std::process::id());
        let _ = std::fs::remove_file(&db_file);
        db::init_db(&db_file).expect("init temp db");

        struct EnvGuard(&'static [&'static str]);
        impl Drop for EnvGuard {
            fn drop(&mut self) {
                for k in self.0 {
                    std::env::remove_var(k);
                }
            }
        }
        let _env_guard = EnvGuard(&[
            "CHRONOS_STEAM_STORE_BASE",
            "CHRONOS_STEAM_API_BASE",
            "CHRONOS_GOG_CATALOG_BASE",
            "CHRONOS_GAMEDB_BASE",
            "CHRONOS_ITCH_BASE",
        ]);

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        let req_count = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let req_count_srv = req_count.clone();

        rt.block_on(async move {
            use tokio::io::{AsyncReadExt, AsyncWriteExt};
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let port = listener.local_addr().unwrap().port();
            let base = format!("http://127.0.0.1:{port}");
            std::env::set_var("CHRONOS_STEAM_STORE_BASE", &base);
            std::env::set_var("CHRONOS_STEAM_API_BASE", &base);
            std::env::set_var("CHRONOS_GOG_CATALOG_BASE", &base);
            std::env::set_var("CHRONOS_GAMEDB_BASE", &base);
            std::env::set_var("CHRONOS_ITCH_BASE", &base);

            let srv = tokio::spawn(async move {
                while let Ok((mut sock, _)) = listener.accept().await {
                    let cnt = req_count_srv.clone();
                    tokio::spawn(async move {
                        let mut buf = [0u8; 4096];
                        let n = sock.read(&mut buf).await.unwrap_or(0);
                        let req = String::from_utf8_lossy(&buf[..n]);
                        let path = req
                            .lines()
                            .next()
                            .and_then(|l| l.split_whitespace().nth(1))
                            .unwrap_or("/");
                        cnt.fetch_add(1, std::sync::atomic::Ordering::Relaxed);

                        let (ct, body): (&str, String) = if path.starts_with("/api/storesearch/") {
                            ("application/json", r#"{"total":0,"items":[]}"#.to_string())
                        } else if path.starts_with("/v1/catalog") && path.contains("Heroes") {
                            (
                                "application/json",
                                r#"{"products":[{"id":"1","title":"Heroes of Might and Magic® 3: Complete","genres":[{"name":"Strategy"}],"tags":[{"name":"Turn-based"}],"features":[]}]}"#.to_string(),
                            )
                        } else if path.starts_with("/v1/catalog") {
                            ("application/json", r#"{"products":[]}"#.to_string())
                        } else if path == "/buckets/ob.json" {
                            ("application/json", r#"{"42":{"name":"Obscure Classic"}}"#.to_string())
                        } else if path == "/games/42.json" {
                            (
                                "application/json",
                                r#"{"name":"Obscure Classic","genres":[{"name":"Role-playing (RPG)"}],"themes":[{"name":"Action"}]}"#.to_string(),
                            )
                        } else if path.starts_with("/buckets/") {
                            ("application/json", "{}".to_string())
                        } else if path.starts_with("/search") && path.contains("Indie%20Jam") {
                            (
                                "text/html",
                                format!(
                                    r#"<div class="game_cell"><a class="title game_link" href="http://127.0.0.1:{port}/indie-jam">Indie Jam</a><div class="game_genre">Platformer</div></div>"#
                                ),
                            )
                        } else if path == "/indie-jam" {
                            (
                                "text/html",
                                r#"<html><body><div class="game_info_panel_widget"><table><tr><td>Tags</td><td><a href="/games/tag-roguelike">Roguelike</a></td></tr></table></div></body></html>"#.to_string(),
                            )
                        } else {
                            ("text/html", "<html><body></body></html>".to_string())
                        };

                        let resp = format!(
                            "HTTP/1.1 200 OK\r\nContent-Type: {ct}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                            body.len()
                        );
                        let _ = sock.write_all(resp.as_bytes()).await;
                    });
                }
            });

            let heroes = resolve_game_metadata_async(None, "Heroes of Might and Magic 3: Complete")
                .await
                .expect("resolved via mock GOG");
            assert_eq!(heroes.source, "gog_catalog");
            assert!(heroes.genres.contains(&"Strategy".to_string()));

            // DOM learning must preserve upstream GOG source & existing genres while appending new tags
            save_learned_dom_metadata(
                "Heroes of Might and Magic® 3: Complete",
                &["Roguelike".to_string()],
            );
            let merged = lookup_cached_only(None, "Heroes of Might and Magic 3: Complete").expect("cached merged");
            assert_eq!(merged.source, "gog_catalog");
            assert!(merged.genres.contains(&"Strategy".to_string()));
            assert!(merged.tags.contains(&"Roguelike".to_string()));

            // Generic storefront titles must never be persisted into dom_learned
            save_learned_dom_metadata("GOG.com", &["Action".to_string()]);
            assert!(lookup_cached_only(None, "GOG.com").is_none());

            // GameDB fallback
            let obscure = resolve_game_metadata_async(None, "Obscure Classic")
                .await
                .expect("resolved via mock GameDB");
            assert_eq!(obscure.source, "gamedb_igdb");
            assert!(obscure.genres.contains(&"RPG".to_string()));

            // Itch search + detail fallback. A prior page-learned entry with coarse genres
            // (as lutris.net shows) must not short-circuit the cascade; it gets merged instead.
            save_learned_dom_metadata("Indie Jam", &["Strategy".to_string()]);
            assert!(is_dom_learned_only(
                &lookup_cached_only(None, "Indie Jam").expect("dom learned entry")
            ));
            let itch = resolve_game_metadata_async(None, "Indie Jam")
                .await
                .expect("resolved via mock Itch");
            assert_eq!(itch.source, "itch_web");
            assert!(itch.tags.contains(&"Roguelike".to_string()));
            assert!(itch.tags.contains(&"Strategy".to_string()));

            // Miss cache prevents hammering providers within 60s for unknown titles
            let miss1 = resolve_game_metadata_async(None, "ZxQvNonExistentTitle999").await;
            assert!(miss1.is_none());
            let after_first_miss = req_count.load(std::sync::atomic::Ordering::Relaxed);
            let miss2 = resolve_game_metadata_async(None, "ZxQvNonExistentTitle999").await;
            assert!(miss2.is_none());
            assert_eq!(req_count.load(std::sync::atomic::Ordering::Relaxed), after_first_miss);

            // Multi-source autocomplete
            let suggestions = search_game_suggestions_async("Heroes", "english", "US", 15).await;
            assert!(suggestions.iter().any(|s| s.source == "GOG" && s.title.contains("Heroes")));

            srv.abort();
        });

        let _ = std::fs::remove_file(db_file);
    }
}
