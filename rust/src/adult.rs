//! Adult content filter: domain blocklist + forced SafeSearch, with
//! optional attempt logging. In parental mode the filter is always on; with
//! anti-cheat active it cannot be loosened (disabled or given new exceptions).

use std::collections::HashSet;
use std::sync::OnceLock;

use parking_lot::RwLock;
use serde::{Deserialize, Serialize};

use crate::{db, steam_api};

const SETTINGS_KEY: &str = "adult_filter";
const LIST_URL: &str = "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts";
const LIST_TTL_SECONDS: i64 = 7 * 86400;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AdultFilterSettings {
    #[serde(default)]
    pub enabled: bool,
    /// Block domains from the public adult-sites list.
    #[serde(default = "yes")]
    pub use_domain_list: bool,
    /// Force SafeSearch (Google/Bing/DuckDuckGo) and YouTube Restricted Mode.
    #[serde(default = "yes")]
    pub safe_search: bool,
    /// Record each blocked attempt (date + site) for the guardian.
    #[serde(default)]
    pub log_attempts: bool,
    /// Sites that are never treated as adult (exceptions).
    #[serde(default)]
    pub allowlist: Vec<String>,
    /// System-wide family DNS applied by the root guard (covers every app/browser).
    #[serde(default)]
    pub dns_protection: bool,
    /// `adguard` | `cloudflare` | `opendns`
    #[serde(default = "default_dns_provider")]
    pub dns_provider: String,
    /// Local image AI (NSFWJS model in the extension): blurs +18 images.
    #[serde(default = "yes")]
    pub image_ai: bool,
    /// Whole-screen image AI (daemon captures the focused window; any app).
    #[serde(default)]
    pub screen_ai: bool,
}

pub const DNS_PROVIDERS: [(&str, &str); 3] = [
    ("adguard", "AdGuard Família (bloqueia adulto + força SafeSearch)"),
    ("cloudflare", "Cloudflare Família (1.1.1.3)"),
    ("opendns", "OpenDNS FamilyShield"),
];

fn default_dns_provider() -> String {
    "adguard".to_string()
}

fn yes() -> bool {
    true
}

impl Default for AdultFilterSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            use_domain_list: true,
            safe_search: true,
            log_attempts: false,
            allowlist: Vec::new(),
            dns_protection: false,
            dns_provider: default_dns_provider(),
            image_ai: true,
            screen_ai: false,
        }
    }
}

const PRIVATE_BLOCK_KEY: &str = "block_private_browsing";

/// Whether incognito/private windows and guest profiles are blocked in browsers
/// (default on). Applied system-wide by the guard (`set-incognito`).
pub fn private_browsing_blocked() -> bool {
    db::try_get_conn()
        .and_then(|_| db::get_config(PRIVATE_BLOCK_KEY))
        .map(|v| v != "0")
        .unwrap_or(true)
}

/// Turning the block off is loosening: refused while anti-cheat is active, and only
/// allowed while every running browser extension has incognito access (otherwise
/// incognito windows would run without Chronos).
///
/// Chrome hides "Allow in incognito" while incognito is blocked, so unblocking without
/// that permission opens a short grace window to turn it on. Returns `Ok(true)` when the
/// user still has to grant it (the UI shows [`INCOGNITO_ACCESS_HELP`]).
pub fn set_private_browsing_blocked(blocked: bool, anti_cheat_active: bool) -> Result<bool, String> {
    let mut needs_permission = false;
    if !blocked && private_browsing_blocked() {
        if anti_cheat_active {
            return Err("Anti-Burla ativo: não é possível liberar a guia anônima agora.".to_string());
        }
        let (known, denied) = incognito_access_summary(now_ms());
        if known == 0 || denied > 0 {
            needs_permission = true;
            let _ = db::set_config(PRIVATE_GRACE_KEY, &(now_ms() + INCOGNITO_GRACE_MS).to_string());
        }
    }
    if blocked {
        let _ = db::set_config(PRIVATE_GRACE_KEY, "0");
    }
    db::set_config(PRIVATE_BLOCK_KEY, if blocked { "1" } else { "0" }).map_err(|e| e.to_string())?;
    Ok(needs_permission)
}

const PRIVATE_GRACE_KEY: &str = "private_unlock_grace_until_ms";
/// Time to turn on "Allow in incognito" after unblocking (Chrome only shows it then).
pub const INCOGNITO_GRACE_MS: i64 = 180_000;

fn in_unlock_grace(now: i64) -> bool {
    db::get_config(PRIVATE_GRACE_KEY)
        .and_then(|v| v.parse::<i64>().ok())
        .is_some_and(|until| now < until)
}

pub const INCOGNITO_ACCESS_HELP: &str = "A guia anônima foi liberada por 3 minutos para você permitir a extensão nela. \
Reabra o navegador, abra chrome://extensions, clique em \"Detalhes\" na extensão Chronos e ligue \"Permitir no modo anônimo\" \
(em cada navegador). Se não ligar a tempo, ou se desligar depois, o Chronos volta a bloquear a guia anônima.";

/// Reports older than this are ignored (browser closed).
const INCOGNITO_REPORT_FRESH_MS: i64 = 120_000;

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn incognito_access_path() -> std::path::PathBuf {
    if cfg!(test) {
        return std::env::temp_dir().join(format!("chronos_incognito_access_{}.json", std::process::id()));
    }
    crate::profile::data_dir().join("incognito_access.json")
}

fn read_incognito_reports() -> serde_json::Map<String, serde_json::Value> {
    std::fs::read_to_string(incognito_access_path())
        .ok()
        .and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok())
        .and_then(|v| v.as_object().cloned())
        .unwrap_or_default()
}

/// Browsers (as reported by the extension: chrome, chromium, brave, edge, ...) with a fresh
/// report: (browser, allowed in incognito).
pub fn incognito_access_by_browser(now: i64) -> Vec<(String, bool)> {
    read_incognito_reports()
        .values()
        .filter(|v| now - v.get("ts").and_then(|t| t.as_i64()).unwrap_or(0) <= INCOGNITO_REPORT_FRESH_MS)
        .map(|v| {
            (
                v.get("browser").and_then(|b| b.as_str()).unwrap_or("").to_string(),
                v.get("allowed").and_then(|a| a.as_bool()) == Some(true),
            )
        })
        .collect()
}

/// (fresh reporters, fresh reporters without incognito access)
pub fn incognito_access_summary(now: i64) -> (usize, usize) {
    summarize_incognito_reports(&read_incognito_reports(), now)
}

pub(crate) fn summarize_incognito_reports(map: &serde_json::Map<String, serde_json::Value>, now: i64) -> (usize, usize) {
    let mut known = 0;
    let mut denied = 0;
    for v in map.values() {
        let ts = v.get("ts").and_then(|t| t.as_i64()).unwrap_or(0);
        if now - ts > INCOGNITO_REPORT_FRESH_MS {
            continue;
        }
        known += 1;
        if v.get("allowed").and_then(|a| a.as_bool()) != Some(true) {
            denied += 1;
        }
    }
    (known, denied)
}

/// Called by the daemon on each extension status report. Returns true when incognito is
/// currently allowed but this browser's extension lost incognito access: the caller must
/// re-enable the block (the lock that keeps the extension in incognito windows).
pub fn record_incognito_access(reporter: &str, allowed: bool, browser: &str) -> bool {
    if reporter.is_empty() {
        return false;
    }
    let mut map = read_incognito_reports();
    let prev = map.get(reporter).and_then(|v| v.get("allowed")).and_then(|a| a.as_bool());
    let entry = serde_json::json!({ "allowed": allowed, "ts": now_ms(), "browser": browser });
    let stale = map.get(reporter).and_then(|v| v.get("ts")).and_then(|t| t.as_i64()).map_or(true, |t| now_ms() - t > 10_000);
    if prev != Some(allowed) || stale {
        map.insert(reporter.to_string(), entry);
        let path = incognito_access_path();
        let tmp = path.with_extension("json.tmp");
        if std::fs::write(&tmp, serde_json::Value::Object(map).to_string()).is_ok() {
            let _ = std::fs::rename(&tmp, &path);
        }
    }
    !allowed && db::try_get_conn().is_some() && !private_browsing_blocked() && !in_unlock_grace(now_ms())
}

/// Re-enables the incognito block (config + guard; `set-incognito 1` is passwordless).
pub fn relock_private_browsing() {
    let _ = db::set_config(PRIVATE_BLOCK_KEY, "1");
    let _ = db::set_config(PRIVATE_GRACE_KEY, "0");
    let _ = db::bump_state_revision();
    let guard = "/usr/local/lib/chronos/chronos-guard";
    if std::path::Path::new(guard).exists() {
        let _ = std::process::Command::new("pkexec")
            .args([guard, "set-incognito", "1"])
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn();
    }
}

pub fn is_parental_mode() -> bool {
    db::try_get_conn().is_some() && db::get_config("app_mode").as_deref() == Some("PARENTAL")
}

/// Effective settings: parental mode forces the filter on (and logging stays as chosen).
pub fn settings() -> AdultFilterSettings {
    let mut s: AdultFilterSettings = db::try_get_conn()
        .and_then(|_| db::get_config(SETTINGS_KEY))
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default();
    if is_parental_mode() {
        s.enabled = true;
    }
    s
}

fn norm_host(raw: &str) -> String {
    let r = raw.trim().to_lowercase();
    let r = r.strip_prefix("https://").or_else(|| r.strip_prefix("http://")).unwrap_or(&r);
    let host = r.split(['/', '?', '#']).next().unwrap_or("");
    let host = host.split(':').next().unwrap_or("");
    host.trim_start_matches("www.").trim_end_matches('.').to_string()
}

/// True when `next` relaxes `cur` (disabling, turning a method off, adding exceptions).
pub fn is_loosening(cur: &AdultFilterSettings, next: &AdultFilterSettings) -> bool {
    cur.enabled
        && (!next.enabled
            || (cur.use_domain_list && !next.use_domain_list)
            || (cur.safe_search && !next.safe_search)
            || (cur.log_attempts && !next.log_attempts)
            || (cur.dns_protection && !next.dns_protection)
            || (cur.image_ai && !next.image_ai)
            || (cur.screen_ai && !next.screen_ai)
            || next.allowlist.iter().any(|a| !cur.allowlist.contains(a)))
}

/// Validates and stores settings. Loosening is refused while anti-cheat is active
/// (disabling, turning a method off, or adding exceptions); parental mode cannot disable.
pub fn save_settings(next: AdultFilterSettings, anti_cheat_active: bool) -> Result<(), String> {
    let mut next = next;
    let mut allow: Vec<String> = Vec::new();
    for a in &next.allowlist {
        let h = norm_host(a);
        if !h.is_empty() && !allow.contains(&h) {
            allow.push(h);
        }
    }
    next.allowlist = allow;
    if !DNS_PROVIDERS.iter().any(|(id, _)| *id == next.dns_provider) {
        next.dns_provider = default_dns_provider();
    }
    if is_parental_mode() && !next.enabled {
        return Err("No modo parental o filtro de conteúdo adulto fica sempre ligado.".to_string());
    }
    let cur = settings();
    if anti_cheat_active {
        if is_loosening(&cur, &next) {
            return Err(
                "Modo Anti-Burla está ativo! Não é possível desligar ou afrouxar o filtro de conteúdo adulto."
                    .to_string(),
            );
        }
    }
    db::set_config(SETTINGS_KEY, &serde_json::to_string(&next).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())?;
    let _ = db::bump_state_revision();
    if next.enabled && next.use_domain_list {
        ensure_domain_list_loaded_async();
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Domain list

fn domains() -> &'static RwLock<HashSet<String>> {
    static D: OnceLock<RwLock<HashSet<String>>> = OnceLock::new();
    D.get_or_init(|| RwLock::new(HashSet::new()))
}

fn list_path() -> std::path::PathBuf {
    crate::profile::data_dir().join("adult_domains.txt")
}

/// Parses hosts-file (`0.0.0.0 domain`) or plain domain-per-line lists.
pub fn parse_domain_list(text: &str) -> HashSet<String> {
    let mut out = HashSet::new();
    for line in text.lines() {
        let line = line.split('#').next().unwrap_or("").trim();
        if line.is_empty() {
            continue;
        }
        let mut parts = line.split_whitespace();
        let first = parts.next().unwrap_or("");
        let dom = if first == "0.0.0.0" || first == "127.0.0.1" { parts.next().unwrap_or("") } else { first };
        let dom = norm_host(dom);
        if dom.contains('.') && dom != "localhost" && !dom.starts_with("0.0.0.0") {
            out.insert(dom);
        }
    }
    out
}

fn load_from_disk() -> bool {
    let Ok(text) = std::fs::read_to_string(list_path()) else {
        return false;
    };
    let set = parse_domain_list(&text);
    let ok = !set.is_empty();
    *domains().write() = set;
    ok
}

/// Loads the cached list (if any) and refreshes it from the network when older than
/// a week, in a background thread.
pub fn ensure_domain_list_loaded_async() {
    static STARTED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
    if domains().read().is_empty() {
        load_from_disk();
    }
    if STARTED.swap(true, std::sync::atomic::Ordering::SeqCst) {
        return;
    }
    std::thread::spawn(|| {
        let stale = std::fs::metadata(list_path())
            .and_then(|m| m.modified())
            .ok()
            .and_then(|t| t.elapsed().ok())
            .map_or(true, |age| age.as_secs() as i64 > LIST_TTL_SECONDS);
        if stale {
            let fetched = steam_api::run_async_blocking(async {
                tokio::time::timeout(std::time::Duration::from_secs(30), steam_api::fetch_url_bytes(LIST_URL)).await
            });
            if let Ok(Ok(bytes)) = fetched {
                let text = String::from_utf8_lossy(&bytes).to_string();
                if parse_domain_list(&text).len() > 1000 {
                    let path = list_path();
                    let tmp = path.with_extension("tmp");
                    if std::fs::write(&tmp, text.as_bytes()).is_ok() {
                        let _ = std::fs::rename(&tmp, &path);
                    }
                    load_from_disk();
                }
            }
        }
        STARTED.store(false, std::sync::atomic::Ordering::SeqCst);
    });
}

pub fn domain_list_size() -> usize {
    domains().read().len()
}

fn host_in_set(host: &str, set: &HashSet<String>) -> bool {
    let mut h = host;
    loop {
        if set.contains(h) {
            return true;
        }
        match h.split_once('.') {
            Some((_, rest)) if rest.contains('.') => h = rest,
            _ => return false,
        }
    }
}

// ---------------------------------------------------------------------------
// Decision

#[derive(Debug, Clone, PartialEq)]
pub struct AdultHit {
    /// Detection method ("lista").
    pub method: &'static str,
    pub detail: String,
}

pub fn check_with(settings: &AdultFilterSettings, url: &str, title: &str, set: &HashSet<String>) -> Option<AdultHit> {
    if !settings.enabled {
        return None;
    }
    let host = norm_host(url);
    if host.is_empty() || host == "127.0.0.1" || host == "localhost" {
        return None;
    }
    if settings
        .allowlist
        .iter()
        .any(|a| host == *a || host.ends_with(&format!(".{a}")))
    {
        return None;
    }
    let _ = title;
    if settings.use_domain_list && host_in_set(&host, set) {
        return Some(AdultHit { method: "lista", detail: host });
    }
    None
}

/// Checks a page against the current settings (and logs the attempt when enabled).
pub fn check(url: &str, title: &str) -> Option<AdultHit> {
    let s = settings();
    if !s.enabled {
        return None;
    }
    if s.use_domain_list && domains().read().is_empty() {
        ensure_domain_list_loaded_async();
    }
    let hit = check_with(&s, url, title, &domains().read())?;
    if s.log_attempts {
        log_attempt(url, &hit);
    }
    Some(hit)
}

/// Proxy interception hint (no logging): adult host, or a search engine needing SafeSearch.
pub fn should_intercept_host(host: &str) -> bool {
    let s = settings();
    if !s.enabled {
        return false;
    }
    let h = norm_host(host);
    if s.safe_search
        && (h.starts_with("google.") || h.contains(".google.") || h.ends_with("bing.com") || h.ends_with("duckduckgo.com"))
    {
        return true;
    }
    if s.use_domain_list && domains().read().is_empty() {
        ensure_domain_list_loaded_async();
    }
    check_with(&s, &format!("https://{h}/"), "", &domains().read()).is_some()
}

pub fn blocked_reason(hit: &AdultHit) -> String {
    format!("Conteúdo adulto bloqueado ({})", hit.detail)
}

// ---------------------------------------------------------------------------
// Attempt log

fn ensure_log_table(conn: &rusqlite::Connection) {
    let _ = conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS adult_block_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            at_utc INTEGER NOT NULL,
            url TEXT NOT NULL,
            method TEXT NOT NULL
        );",
    );
}

fn now_utc() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

/// Readable label for a +18 page blocked by the extension on Reddit or X
/// ("Reddit +18 — r/sub", "X +18 — @user"); `None` for other sites.
pub fn social_attempt_label(url: &str) -> Option<(&'static str, String)> {
    let host = norm_host(url);
    let path = url
        .split_once("://")
        .map_or(url, |(_, rest)| rest)
        .split_once('/')
        .map_or("", |(_, p)| p);
    let segs: Vec<&str> = path.split(['?', '#']).next().unwrap_or("").split('/').filter(|s| !s.is_empty()).collect();
    if host == "reddit.com" || host.ends_with(".reddit.com") {
        let what = match segs.as_slice() {
            ["r", sub, ..] => format!("r/{sub}"),
            ["user" | "u", name, ..] => format!("u/{name}"),
            ["over18", ..] => "verificação de idade".to_string(),
            _ => "post".to_string(),
        };
        return Some(("reddit", format!("Reddit +18 — {what}")));
    }
    if host == "x.com" || host.ends_with(".x.com") || host == "twitter.com" || host.ends_with(".twitter.com") {
        let what = match segs.first() {
            Some(u) if !["home", "explore", "search", "i", "notifications", "messages"].contains(u) => format!("@{u}"),
            _ => "post".to_string(),
        };
        return Some(("x", format!("X +18 — {what}")));
    }
    None
}

/// Logs a +18 page blocked by the extension (Reddit/X filters, or `kind == "image"`
/// for the image AI) when logging is on.
/// +18 detected on screen by the whole-screen detector (any app).
pub fn log_screen_attempt(window_class: &str) {
    if !settings().log_attempts {
        return;
    }
    let class: String = window_class.chars().take(60).collect();
    insert_attempt(&format!("Tela +18 — {class}"), "tela");
}

pub fn log_social_attempt(url: &str, kind: &str) {
    if !settings().log_attempts {
        return;
    }
    if kind == "image" {
        let host = norm_host(url);
        if !host.is_empty() {
            insert_attempt(&format!("Imagens +18 — {host}"), "imagem");
        }
        return;
    }
    if let Some((method, label)) = social_attempt_label(url) {
        insert_attempt(&label, method);
    }
}

fn log_attempt(url: &str, hit: &AdultHit) {
    insert_attempt(&norm_host(url), hit.method);
}

fn insert_attempt(site: &str, method: &str) {
    let Some(c) = db::try_get_conn() else { return };
    let conn = c.lock();
    ensure_log_table(&conn);
    let host = site.to_string();
    // Same site within 60s counts once (pages poll /api/check every few seconds).
    let recent: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM adult_block_events WHERE url = ?1 AND at_utc >= ?2",
            (&host, now_utc() - 60),
            |r| r.get(0),
        )
        .unwrap_or(0);
    if recent == 0 {
        let _ = conn.execute(
            "INSERT INTO adult_block_events (at_utc, url, method) VALUES (?1, ?2, ?3)",
            (now_utc(), &host, method),
        );
    }
}

/// Latest logged attempts: (unix time, site, method).
pub fn recent_attempts(limit: usize) -> Vec<(i64, String, String)> {
    let Some(c) = db::try_get_conn() else { return Vec::new() };
    let conn = c.lock();
    ensure_log_table(&conn);
    let Ok(mut st) = conn.prepare("SELECT at_utc, url, method FROM adult_block_events ORDER BY at_utc DESC, rowid DESC LIMIT ?1") else {
        return Vec::new();
    };
    st.query_map([limit as i64], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
        .map(|rows| rows.flatten().collect())
        .unwrap_or_default()
}

// ---------------------------------------------------------------------------
// SafeSearch (URL rewrite + YouTube Restricted Mode header)

/// True when an address returned for a known adult domain is a DNS filter sinkhole
/// (0.0.0.0 / :: / OpenDNS block page 146.112.61.x).
pub fn is_sinkhole_addr(ip: &std::net::IpAddr) -> bool {
    match ip {
        std::net::IpAddr::V4(v4) => v4.is_unspecified() || (v4.octets()[0..3] == [146, 112, 61]),
        std::net::IpAddr::V6(v6) => v6.is_unspecified(),
    }
}

/// Whether the network's DNS (e.g. the router) already filters adult sites: resolves a
/// well-known adult domain with the system resolver and checks for a sinkhole answer.
pub fn network_dns_filters_adult() -> bool {
    use std::net::ToSocketAddrs;
    match "pornhub.com:443".to_socket_addrs() {
        Ok(addrs) => {
            let ips: Vec<std::net::IpAddr> = addrs.map(|a| a.ip()).collect();
            !ips.is_empty() && ips.iter().all(is_sinkhole_addr)
        }
        Err(_) => false,
    }
}

/// SafeSearch URL to send the browser to, when the filter and SafeSearch are on.
pub fn safe_search_target(url: &str) -> Option<String> {
    let s = settings();
    if !s.enabled || !s.safe_search {
        return None;
    }
    safe_search_redirect(url)
}

/// Returns the SafeSearch version of a search URL, or `None` if already safe / not a search.
pub fn safe_search_redirect(url: &str) -> Option<String> {
    let host = norm_host(url);
    let (param, value) = if (host.starts_with("google.") || host.contains(".google.")) && url.contains("/search") {
        ("safe", "active")
    } else if host.ends_with("bing.com") && url.contains("/search") {
        ("adlt", "strict")
    } else if host.ends_with("duckduckgo.com") && (url.contains("q=") || url.contains("/html")) {
        ("kp", "1")
    } else {
        return None;
    };
    let (base, frag) = url.split_once('#').map_or((url, None), |(b, f)| (b, Some(f)));
    let (path, query) = base.split_once('?').unwrap_or((base, ""));
    let mut pairs: Vec<String> = query
        .split('&')
        .filter(|p| !p.is_empty() && p.split('=').next() != Some(param))
        .map(str::to_string)
        .collect();
    let already = query.split('&').any(|p| p == format!("{param}={value}"));
    if already {
        return None;
    }
    pairs.push(format!("{param}={value}"));
    let mut out = format!("{path}?{}", pairs.join("&"));
    if let Some(f) = frag {
        out.push('#');
        out.push_str(f);
    }
    Some(out)
}

/// JSON for extensions/injected script (`/api/status` → `adultFilter`).
pub fn status_json() -> serde_json::Value {
    let s = settings();
    serde_json::json!({
        "enabled": s.enabled,
        "safeSearch": s.enabled && s.safe_search,
        "imageAi": s.enabled && s.image_ai,
        "allowlist": s.allowlist,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn on() -> AdultFilterSettings {
        AdultFilterSettings { enabled: true, ..Default::default() }
    }

    #[test]
    fn test_list_allowlist_and_safesearch() {
        let set = parse_domain_list("# c\n0.0.0.0 badsite.com\n0.0.0.0 www.other-adult.net\nplain.org\n0.0.0.0 0.0.0.0\n");
        assert!(set.contains("badsite.com") && set.contains("other-adult.net") && set.contains("plain.org"));
        let s = on();
        assert_eq!(check_with(&s, "https://cdn.badsite.com/x", "", &set).unwrap().method, "lista");
        assert!(check_with(&s, "https://notbadsite.com/", "", &set).is_none(), "suffix needs a dot boundary");
        assert!(check_with(&s, "https://pt.wikipedia.org/wiki/Educação_sexual", "Educação sexual", &set).is_none());
        let mut allow = on();
        allow.allowlist = vec!["badsite.com".into()];
        assert!(check_with(&allow, "https://cdn.badsite.com/", "", &set).is_none());
        assert!(check_with(&AdultFilterSettings::default(), "https://badsite.com/", "", &set).is_none(), "disabled");

        assert_eq!(
            safe_search_redirect("https://www.google.com/search?q=gatos&hl=pt").as_deref(),
            Some("https://www.google.com/search?q=gatos&hl=pt&safe=active")
        );
        assert!(safe_search_redirect("https://www.google.com/search?q=x&safe=active").is_none());
        assert_eq!(
            safe_search_redirect("https://www.google.com/search?safe=off&q=x").as_deref(),
            Some("https://www.google.com/search?q=x&safe=active")
        );
        assert!(safe_search_redirect("https://www.bing.com/search?q=x").unwrap().ends_with("adlt=strict"));
        assert!(safe_search_redirect("https://duckduckgo.com/?q=x").unwrap().ends_with("kp=1"));
        assert!(safe_search_redirect("https://www.google.com/maps").is_none());
        assert!(safe_search_redirect("https://example.com/search?q=x").is_none());
    }

    #[test]
    fn test_settings_parental_anti_cheat_and_log() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db_file = format!("/tmp/chronos_adult_{}.db", std::process::id());
        let _ = std::fs::remove_file(&db_file);
        db::init_db(&db_file).expect("init temp db");

        assert!(!settings().enabled);
        save_settings(AdultFilterSettings { enabled: true, log_attempts: true, ..Default::default() }, false).unwrap();
        assert!(settings().enabled);

        // Anti-cheat: cannot disable, drop a method or add exceptions; tightening ok
        let cur = settings();
        assert!(save_settings(AdultFilterSettings { enabled: false, ..cur.clone() }, true).is_err());
        assert!(save_settings(AdultFilterSettings { use_domain_list: false, ..cur.clone() }, true).is_err());
        assert!(save_settings(AdultFilterSettings { image_ai: false, ..cur.clone() }, true).is_err(), "image AI locked");
        save_settings(AdultFilterSettings { dns_protection: true, dns_provider: "nope".into(), ..cur.clone() }, true).unwrap();
        assert_eq!(settings().dns_provider, "adguard", "unknown provider falls back to adguard");
        let with_dns = settings();
        assert!(save_settings(AdultFilterSettings { dns_protection: false, ..with_dns.clone() }, true).is_err(), "DNS cannot be turned off under anti-cheat");
        assert!(save_settings(AdultFilterSettings { dns_provider: "cloudflare".into(), ..with_dns.clone() }, true).is_ok(), "switching provider is fine");
        let cur = settings();
        assert!(save_settings(AdultFilterSettings { allowlist: vec!["x.com".into()], ..cur.clone() }, true).is_err());
        assert!(save_settings(cur.clone(), true).is_ok());

        // Logged attempt (deduplicated within 60s)
        let hit = AdultHit { method: "lista", detail: "badsite.com".into() };
        log_attempt("https://badsite.com/a", &hit);
        log_attempt("https://badsite.com/b", &hit);
        assert_eq!(recent_attempts(10).len(), 1);
        assert_eq!(recent_attempts(10)[0].1, "badsite.com");
        assert_eq!(social_attempt_label("https://www.reddit.com/r/nsfwsub/comments/a/b/").unwrap().1, "Reddit +18 — r/nsfwsub");
        assert_eq!(social_attempt_label("https://x.com/someone").unwrap().1, "X +18 — @someone");
        assert!(social_attempt_label("https://example.com/").is_none());
        log_social_attempt("https://old.reddit.com/over18?dest=x", "");
        assert_eq!(recent_attempts(10)[0].1, "Reddit +18 — verificação de idade");
        log_social_attempt("https://www.example.org/gallery", "image");
        assert_eq!(recent_attempts(10)[0].1, "Imagens +18 — example.org");

        // Parental mode: always on, cannot be disabled
        db::set_config("app_mode", "PARENTAL").unwrap();
        db::set_config(SETTINGS_KEY, &serde_json::to_string(&AdultFilterSettings::default()).unwrap()).unwrap();
        assert!(settings().enabled, "forced on in parental mode");
        assert!(save_settings(AdultFilterSettings::default(), false).is_err());
        db::set_config("app_mode", "SELF_CONTROL").unwrap();

        // SafeSearch target only when the filter and SafeSearch are both on
        let cur = settings();
        save_settings(AdultFilterSettings { safe_search: false, ..cur.clone() }, false).unwrap();
        assert!(safe_search_target("https://www.google.com/search?q=x").is_none());
        save_settings(AdultFilterSettings { enabled: true, safe_search: true, ..cur.clone() }, false).unwrap();
        assert!(safe_search_target("https://www.google.com/search?q=x").unwrap().contains("safe=active"));
        assert!(safe_search_target("https://example.com/").is_none());

        assert!(is_sinkhole_addr(&"0.0.0.0".parse().unwrap()));
        assert!(is_sinkhole_addr(&"::".parse().unwrap()));
        assert!(is_sinkhole_addr(&"146.112.61.106".parse().unwrap()));
        assert!(!is_sinkhole_addr(&"66.254.114.41".parse().unwrap()));

        // Private browsing block: on by default; off refused under anti-cheat
        assert!(private_browsing_blocked());
        assert!(set_private_browsing_blocked(false, true).is_err());
        assert!(private_browsing_blocked());
        let mut reports = serde_json::Map::new();
        let now = now_ms();
        reports.insert("chrome".into(), serde_json::json!({"allowed": true, "ts": now}));
        reports.insert("old".into(), serde_json::json!({"allowed": false, "ts": now - 600_000}));
        assert_eq!(summarize_incognito_reports(&reports, now), (1, 0), "stale reports ignored");
        reports.insert("chromium".into(), serde_json::json!({"allowed": false, "ts": now}));
        assert_eq!(summarize_incognito_reports(&reports, now), (2, 1));
        // Unblocking without the permission opens the grace window (no relock during it)
        assert_eq!(set_private_browsing_blocked(false, false), Ok(true));
        assert!(!private_browsing_blocked());
        assert!(in_unlock_grace(now_ms()));
        assert!(!in_unlock_grace(now_ms() + INCOGNITO_GRACE_MS + 1));
        assert!(!private_browsing_blocked());
        set_private_browsing_blocked(true, true).unwrap();
        assert!(private_browsing_blocked(), "turning it on is always allowed");
        assert!(!in_unlock_grace(now_ms()), "blocking clears the grace window");

        let _ = std::fs::remove_file(db_file);
    }
}
