//! Persistent local API & block-page server (`127.0.0.1:4545`) for Chronos Focus.
//!
//! Shares SQLite WAL state cleanly with the Flutter GUI process so browser
//! extensions, focus filters, site quota rules, and the `/blocked` UI remain
//! active even when the Chronos window is closed.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use tokio::io::{AsyncWrite, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{broadcast, Notify};

use crate::{db, engine, launchers, proxy, steam_api};

pub const API_DEFAULT_PORT: u16 = 4545;
static FILTER_REVISION: AtomicU64 = AtomicU64::new(1);
static STATE_EVENT_TX: OnceLock<broadcast::Sender<i64>> = OnceLock::new();
static WATCHDOG_NOTIFY: OnceLock<Arc<Notify>> = OnceLock::new();

fn state_event_sender() -> &'static broadcast::Sender<i64> {
    STATE_EVENT_TX.get_or_init(|| {
        let (tx, _) = broadcast::channel(64);
        tx
    })
}

fn watchdog_notify() -> &'static Arc<Notify> {
    WATCHDOG_NOTIFY.get_or_init(|| Arc::new(Notify::new()))
}

pub fn subscribe_state_events() -> broadcast::Receiver<i64> {
    state_event_sender().subscribe()
}

pub fn subscribe_watchdog_notify() -> Arc<Notify> {
    watchdog_notify().clone()
}

/// Dispara invalidação de caches de launcher e acorda imediatamente SSE + watchdog.
pub fn notify_state_changed() -> i64 {
    FILTER_REVISION.fetch_add(1, Ordering::Relaxed);
    launchers::invalidate_launcher_caches();
    let rev = db::get_state_revision();
    let _ = state_event_sender().send(rev);
    watchdog_notify().notify_waiters();
    rev
}

const CORS_HEADERS: [(&str, &str); 3] = [
    ("Access-Control-Allow-Origin", "*"),
    ("Access-Control-Allow-Methods", "GET, POST, OPTIONS"),
    ("Access-Control-Allow-Headers", "Content-Type, Authorization"),
];

/// Runs the local HTTP API & block page listener until terminated.
pub async fn run_local_api_server(bind_addr: &str) -> Result<(), String> {
    let listener = TcpListener::bind(bind_addr)
        .await
        .map_err(|e| format!("Failed binding local API on {bind_addr}: {e}"))?;
    loop {
        let Ok((stream, _)) = listener.accept().await else {
            continue;
        };
        tokio::spawn(async move {
            let _ = handle_api_connection(stream).await;
        });
    }
}

fn percent_decode(raw: &str) -> String {
    let bytes = raw.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'+' => {
                out.push(b' ');
                i += 1;
            }
            b'%' if i + 2 < bytes.len() => {
                if let (Some(hi), Some(lo)) = (hex_val(bytes[i + 1]), hex_val(bytes[i + 2])) {
                    out.push((hi << 4) | lo);
                    i += 3;
                    continue;
                }
                out.push(b'%');
                i += 1;
            }
            b => {
                out.push(b);
                i += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn hex_val(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

pub(crate) fn split_path_and_query(target: &str) -> (&str, HashMap<String, String>) {
    let (path, qs) = match target.split_once('?') {
        Some((p, q)) => (p, q),
        None => (target, ""),
    };
    let mut params = HashMap::new();
    for pair in qs.split('&').filter(|p| !p.is_empty()) {
        if let Some((k, v)) = pair.split_once('=') {
            params.insert(percent_decode(k), percent_decode(v));
        } else {
            params.insert(percent_decode(pair), String::new());
        }
    }
    (path, params)
}

fn html_escape(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for ch in input.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(ch),
        }
    }
    out
}

const ACTIVE_TAB_FILE: &str = "/tmp/chronos_active_tab.json";

/// Merges a browser report into the active-tab file.
/// - `focused`: the focused tab (`url`/`title`), when the report includes it;
/// - `audible`: `Some((url, title))` when the report also describes the audible tab
///   (`/api/status`), `None` when it does not (`/api/check` from a content script) — in
///   that case the previous audible tab is kept, with its own timestamp.
/// The focused and audible parts expire independently (see `youtube::ACTIVE_TAB_FRESH_MS`).
pub(crate) fn merge_active_tab_report(
    previous: Option<serde_json::Value>,
    focused: Option<(&str, &str)>,
    audible: Option<(&str, &str)>,
    now_ms: i64,
    source: &str,
    reporter: &str,
) -> serde_json::Value {
    let own = crate::profile::api_host();
    let prev = previous.unwrap_or_else(|| serde_json::json!({}));
    let s = |k: &str| prev.get(k).and_then(|v| v.as_str()).unwrap_or("").to_string();
    let n = |k: &str| prev.get(k).and_then(|v| v.as_i64()).unwrap_or(0);
    let clean = |u: &str| if u.contains(&own) { String::new() } else { u.trim().to_string() };

    let (url, title, ts) = match focused {
        Some((u, t)) if !u.trim().is_empty() => (clean(u), t.trim().to_string(), now_ms),
        _ => (s("url"), s("title"), n("timestamp_ms")),
    };
    // Several browsers can report at once (e.g. Chrome + Chromium). A browser with nothing
    // playing may only clear audio it reported itself; another browser's fresh audible tab
    // is kept until it expires.
    let prev_reporter = s("audible_reporter");
    let prev_audible_fresh = !s("audible_url").is_empty()
        && (now_ms - n("audible_timestamp_ms")).abs() <= crate::youtube::AUDIBLE_TAB_FRESH_MS;
    let (a_url, a_title, a_ts, a_rep) = match audible {
        Some((u, _)) if u.trim().is_empty() && prev_audible_fresh && !prev_reporter.is_empty() && prev_reporter != reporter => {
            (s("audible_url"), s("audible_title"), n("audible_timestamp_ms"), prev_reporter.clone())
        }
        Some((u, t)) => (clean(u), t.trim().to_string(), now_ms, reporter.to_string()),
        None => (s("audible_url"), s("audible_title"), n("audible_timestamp_ms").max(0), prev_reporter.clone()),
    };
    serde_json::json!({
        "url": url,
        "title": title,
        "audible_url": a_url,
        "audible_title": a_title,
        "source": source,
        "timestamp_ms": ts,
        "audible_timestamp_ms": a_ts,
        "audible_reporter": a_rep,
    })
}

fn read_active_tab_file() -> Option<serde_json::Value> {
    std::fs::read_to_string(ACTIVE_TAB_FILE)
        .ok()
        .and_then(|c| serde_json::from_str(&c).ok())
}

fn write_active_tab_file(v: &serde_json::Value) {
    let tmp = format!("{ACTIVE_TAB_FILE}.{}", std::process::id());
    if std::fs::write(&tmp, v.to_string()).is_ok() {
        let _ = std::fs::rename(&tmp, ACTIVE_TAB_FILE);
    }
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

/// Full report from the extension background (`/api/status`): focused + audible tabs.
fn record_active_browser_tab(url: &str, title: &str, audible_url: &str, audible_title: &str, reporter: &str) {
    let focused = (!url.trim().is_empty()).then_some((url, title));
    let merged = merge_active_tab_report(read_active_tab_file(), focused, Some((audible_url, audible_title)), now_millis(), "extension", reporter);
    write_active_tab_file(&merged);
}

/// Focused-tab-only report (`/api/check` from the page's content script, or the proxy):
/// keeps the audible tab.
pub(crate) fn record_focused_browser_tab(url: &str, title: &str, source: &str) {
    if url.trim().is_empty() {
        return;
    }
    let merged = merge_active_tab_report(read_active_tab_file(), Some((url, title)), None, now_millis(), source, "");
    write_active_tab_file(&merged);
}

/// A tab closed: forget the focused tab but keep the audible one (it may still be playing).
fn clear_focused_browser_tab() {
    if let Some(mut v) = read_active_tab_file() {
        v["url"] = serde_json::json!("");
        v["title"] = serde_json::json!("");
        v["timestamp_ms"] = serde_json::json!(0);
        write_active_tab_file(&v);
    }
}

fn update_bool_field(target: &mut bool, obj: &serde_json::Map<String, serde_json::Value>, keys: &[&str]) {
    for k in keys {
        if let Some(v) = obj.get(*k).and_then(|val| val.as_bool()) {
            *target = v;
            return;
        }
    }
}

fn update_clamped_f64_field(
    target: &mut f64,
    obj: &serde_json::Map<String, serde_json::Value>,
    keys: &[&str],
    clamp: fn(f64) -> f64,
) {
    for k in keys {
        if let Some(v) = obj.get(*k).and_then(|val| val.as_f64()) {
            *target = clamp(v);
            return;
        }
    }
}

fn update_string_list_field(
    target: &mut Vec<String>,
    obj: &serde_json::Map<String, serde_json::Value>,
    keys: &[&str],
) {
    for k in keys {
        if let Some(arr) = obj.get(*k).and_then(|val| val.as_array()) {
            let items: Vec<String> = arr
                .iter()
                .filter_map(|v| v.as_str().map(str::to_string))
                .collect();
            *target = db::normalize_term_list(&items);
            return;
        }
    }
}

pub(crate) fn merge_focus_filters(mut current: db::FocusFilters, obj: &serde_json::Map<String, serde_json::Value>) -> db::FocusFilters {
    update_bool_field(&mut current.yt_block_shorts, obj, &["ytBlockShorts", "yt_block_shorts"]);
    update_bool_field(&mut current.yt_educational_mode, obj, &["ytEducationalMode", "yt_educational_mode"]);
    update_bool_field(&mut current.yt_block_sidebar, obj, &["ytBlockSidebar", "yt_block_sidebar"]);
    update_bool_field(&mut current.yt_block_comments, obj, &["ytBlockComments", "yt_block_comments"]);
    update_bool_field(&mut current.yt_show_only_enabled, obj, &["ytShowOnlyEnabled", "yt_show_only_enabled"]);
    update_string_list_field(&mut current.yt_show_only_types, obj, &["ytShowOnlyTypes", "yt_show_only_types"]);

    update_bool_field(&mut current.ig_block_reels, obj, &["igBlockReels", "ig_block_reels"]);
    update_bool_field(&mut current.ig_block_feed, obj, &["igBlockFeed", "ig_block_feed"]);
    update_bool_field(&mut current.ig_block_comments, obj, &["igBlockComments", "ig_block_comments"]);

    update_bool_field(&mut current.tt_block_feed, obj, &["ttBlockFeed", "tt_block_feed"]);

    update_bool_field(&mut current.rd_block_feed, obj, &["rdBlockFeed", "rd_block_feed"]);
    update_bool_field(&mut current.rd_block_comments, obj, &["rdBlockComments", "rd_block_comments"]);

    update_bool_field(&mut current.tw_block_feed, obj, &["twBlockFeed", "tw_block_feed"]);
    update_bool_field(&mut current.tw_block_trends, obj, &["twBlockTrends", "tw_block_trends"]);
    update_bool_field(&mut current.rd_block_nsfw, obj, &["rdBlockNsfw", "rd_block_nsfw"]);
    update_bool_field(&mut current.tw_block_sensitive, obj, &["twBlockSensitive", "tw_block_sensitive"]);

    update_bool_field(&mut current.li_block_feed, obj, &["liBlockFeed", "li_block_feed"]);

    update_bool_field(
        &mut current.global_grayscale,
        obj,
        &["globalGrayscale", "global_grayscale", "grayscaleMode", "grayscale_mode"],
    );
    update_bool_field(
        &mut current.global_block_notifications,
        obj,
        &[
            "globalBlockNotifications",
            "global_block_notifications",
            "blockNotifications",
            "block_notifications",
        ],
    );
    update_clamped_f64_field(
        &mut current.hud_alpha,
        obj,
        &["hudAlpha", "hud_alpha"],
        db::clamp_hud_alpha,
    );
    update_clamped_f64_field(
        &mut current.hud_scale,
        obj,
        &["hudScale", "hud_scale"],
        db::clamp_hud_scale,
    );
    update_bool_field(&mut current.hud_hide_to_eye, obj, &["hudHideToEye", "hud_hide_to_eye"]);
    update_bool_field(
        &mut current.launcher_filter_enabled,
        obj,
        &["launcherFilterEnabled", "launcher_filter_enabled"],
    );
    update_string_list_field(
        &mut current.launcher_blocked_tags,
        obj,
        &["launcherBlockedTags", "launcher_blocked_tags"],
    );
    update_string_list_field(
        &mut current.launcher_blocked_names,
        obj,
        &["launcherBlockedNames", "launcher_blocked_names"],
    );
    current.normalize_legacy();
    current
}

pub(crate) fn apply_focus_filters_update(
    obj: &serde_json::Map<String, serde_json::Value>,
) -> (bool, bool, String, db::FocusFilters) {
    let anti_cheat = engine::get_anti_cheat_state();
    let candidate = merge_focus_filters(db::get_focus_filters(), obj);
    match db::set_focus_filters_checked(&candidate, anti_cheat.is_active) {
        Ok(saved) => {
            notify_state_changed();
            if saved.launcher_filter_enabled && crate::launchers::has_launcher_proxy_configured() {
                std::thread::spawn(|| {
                    let _ = crate::launchers::sync_launcher_proxy_if_configured();
                });
            }
            (true, false, "Filtros atualizados.".to_string(), saved)
        }
        Err(msg) => (false, anti_cheat.is_active, msg, db::get_focus_filters()),
    }
}

fn split_url_host_and_path(url: &str) -> (String, String) {
    let trimmed = url.trim();
    let after_scheme = trimmed
        .strip_prefix("https://")
        .or_else(|| trimmed.strip_prefix("http://"))
        .unwrap_or(trimmed);
    if after_scheme.is_empty() || after_scheme.starts_with('/') {
        return (String::new(), after_scheme.to_string());
    }
    match after_scheme.find('/') {
        Some(idx) => {
            let host_port = &after_scheme[..idx];
            let host = host_port.split(':').next().unwrap_or(host_port).to_ascii_lowercase();
            (host, after_scheme[idx..].to_string())
        }
        None => {
            let host = after_scheme.split(':').next().unwrap_or(after_scheme).to_ascii_lowercase();
            (host, "/".to_string())
        }
    }
}

pub(crate) async fn handle_launchers_resolve_payload(req_body: &[u8]) -> Result<serde_json::Value, String> {
    let parsed: serde_json::Value =
        serde_json::from_slice(req_body).map_err(|_| "Invalid JSON".to_string())?;
    let filters = db::get_focus_filters();
    let has_rules = filters.launcher_filter_enabled
        && (!filters.launcher_blocked_tags.is_empty() || !filters.launcher_blocked_names.is_empty());
    let force_lookup = parsed.get("forceLookup").and_then(|v| v.as_bool()).unwrap_or(false);

    #[derive(Clone)]
    struct InputItem {
        id: String,
        app_id: Option<i64>,
        title: String,
        site_tags: Vec<String>,
        is_search_query: bool,
    }

    let parse_i64_array = |val: Option<&serde_json::Value>| -> Vec<i64> {
        val.and_then(|v| v.as_array())
            .map(|arr| arr.iter().filter_map(|n| n.as_i64()).collect())
            .unwrap_or_default()
    };

    let mut inputs: Vec<InputItem> = Vec::new();
    if let Some(arr) = parsed.get("items").and_then(|v| v.as_array()) {
        for (idx, item) in arr.iter().take(120).enumerate() {
            let id = item
                .get("id")
                .and_then(|v| v.as_str())
                .map(str::to_string)
                .unwrap_or_else(|| idx.to_string());
            let url = item.get("url").and_then(|v| v.as_str()).unwrap_or("");
            let (url_host, url_path) = split_url_host_and_path(url);
            let url_hint = if !url_host.is_empty() {
                steam_api::extract_launcher_url_hint(&url_host, &url_path)
            } else {
                None
            };

            let app_id = item
                .get("appId")
                .and_then(|v| v.as_i64())
                .filter(|&n| n > 0)
                .or_else(|| steam_api::extract_steam_appid_from_url(url))
                .or_else(|| url_hint.as_ref().and_then(|h| h.0));

            let raw_title = item.get("title").and_then(|v| v.as_str()).unwrap_or("").trim();
            let mut title = if steam_api::is_generic_storefront_title(raw_title) {
                String::new()
            } else {
                raw_title.to_string()
            };

            let mut site_tags: Vec<String> = item
                .get("siteTags")
                .and_then(|v| v.as_array())
                .map(|t| t.iter().filter_map(|s| s.as_str().map(str::to_string)).collect())
                .unwrap_or_default();

            let site_tag_ids = parse_i64_array(item.get("siteTagIds"));
            let desc_ids = parse_i64_array(item.get("descIds"));
            if !site_tag_ids.is_empty() || !desc_ids.is_empty() {
                site_tags.extend(steam_api::lookup_tag_names_by_ids(&site_tag_ids, &desc_ids));
            }

            let mut is_search_query = item
                .get("isSearchQuery")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            let is_single_game_page = item
                .get("isSingleGamePage")
                .or_else(|| item.get("isDetailPage"))
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            if let Some((_, hint_title, url_tags, hint_is_search)) = url_hint {
                is_search_query = is_search_query || hint_is_search;
                site_tags.extend(url_tags);
                if title.is_empty() && !hint_title.is_empty() && !steam_api::is_generic_storefront_title(&hint_title) {
                    title = hint_title;
                }
                if is_search_query && !title.is_empty() {
                    // Explicit search term on store search can target either a blocked name or tag
                    site_tags.push(title.clone());
                }
            }

            let normalized_site_tags = db::normalize_term_list(&site_tags);
            if is_single_game_page
                && !is_search_query
                && !title.is_empty()
                && !steam_api::is_generic_storefront_title(&title)
                && !normalized_site_tags.is_empty()
            {
                steam_api::save_learned_dom_metadata(&title, &normalized_site_tags);
            }

            inputs.push(InputItem {
                id,
                app_id,
                title,
                site_tags: normalized_site_tags,
                is_search_query,
            });
        }
    }

    let mut batch_meta = HashMap::new();
    if has_rules || force_lookup {
        let app_ids: Vec<i64> = inputs.iter().filter_map(|i| i.app_id).collect();
        if !app_ids.is_empty() {
            batch_meta = steam_api::fetch_batch_by_appids_async(&app_ids).await;
        }
    }

    let mut initial_metas: Vec<Option<steam_api::GameMetadata>> = Vec::with_capacity(inputs.len());
    let mut remote_tasks: Vec<(usize, String, Option<i64>, String)> = Vec::new();
    let mut queued_keys = std::collections::HashSet::new();

    for (idx, item) in inputs.iter().enumerate() {
        let meta = item
            .app_id
            .and_then(|id| batch_meta.get(&id).cloned())
            .or_else(|| {
                steam_api::lookup_cached_only(item.app_id, &item.title).filter(|m| {
                    !m.all_filter_terms().is_empty() && !steam_api::is_dom_learned_only(m)
                })
            });

        let pre_matched = steam_api::match_game_against_filters(
            &item.title,
            &item.site_tags,
            meta.as_ref(),
            &filters,
        );

        if meta.is_none()
            && pre_matched.is_none()
            && !item.is_search_query
            && !item.title.is_empty()
            && !steam_api::is_generic_storefront_title(&item.title)
            && (has_rules || force_lookup)
        {
            let dedup_key = format!(
                "{}:{}",
                item.app_id.unwrap_or(0),
                steam_api::normalize_match_text(&item.title)
            );
            if queued_keys.insert(dedup_key.clone()) && remote_tasks.len() < 24 {
                remote_tasks.push((idx, dedup_key, item.app_id, item.title.clone()));
            }
        }
        initial_metas.push(meta);
    }

    let mut resolved_by_key: HashMap<String, Option<steam_api::GameMetadata>> = HashMap::new();
    if !remote_tasks.is_empty() {
        let batch_deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(6);
        let mut join_set = tokio::task::JoinSet::new();
        let mut iter = remote_tasks.into_iter();
        for _ in 0..6 {
            if let Some((_, key, app_id, title)) = iter.next() {
                join_set.spawn(async move {
                    let res = steam_api::resolve_game_metadata_async(app_id, &title).await;
                    (key, res)
                });
            }
        }
        loop {
            let Ok(next_res) = tokio::time::timeout_at(batch_deadline, join_set.join_next()).await else {
                join_set.abort_all();
                break;
            };
            let Some(joined) = next_res else {
                break;
            };
            if let Ok((key, meta)) = joined {
                resolved_by_key.insert(key, meta);
            }
            if let Some((_, key, app_id, title)) = iter.next() {
                join_set.spawn(async move {
                    let res = steam_api::resolve_game_metadata_async(app_id, &title).await;
                    (key, res)
                });
            }
        }
    }

    let mut results = Vec::with_capacity(inputs.len());
    for (idx, item) in inputs.into_iter().enumerate() {
        let mut meta = initial_metas[idx].take();
        if meta.is_none() && !item.title.is_empty() {
            let dedup_key = format!(
                "{}:{}",
                item.app_id.unwrap_or(0),
                steam_api::normalize_match_text(&item.title)
            );
            if let Some(found) = resolved_by_key.get(&dedup_key).and_then(|m| m.clone()) {
                meta = Some(found);
            }
        }

        let matched = steam_api::match_game_against_filters(
            &item.title,
            &item.site_tags,
            meta.as_ref(),
            &filters,
        );
        let display_title = meta
            .as_ref()
            .map(|m| m.title.clone())
            .filter(|t| !t.is_empty())
            .unwrap_or_else(|| item.title.clone());
        let resolved_appid = meta.as_ref().and_then(|m| m.app_id).or(item.app_id);
        let tags = meta
            .as_ref()
            .map(|m| m.all_filter_terms())
            .unwrap_or_else(|| item.site_tags.clone());

        let (blocked, match_type, matched_term, reason) = if let Some((kind, term)) = matched {
            let r = if kind == "NOME" {
                format!("Bloqueado pelo filtro de nome \"{term}\"")
            } else {
                let src_label = meta
                    .as_ref()
                    .map(|m| steam_api::source_display_label(&m.source))
                    .unwrap_or("Página");
                format!("Bloqueado pela tag \"{term}\" ({src_label})")
            };
            (true, Some(kind), Some(term), r)
        } else {
            (false, None, None, String::new())
        };

        results.push(serde_json::json!({
            "id": item.id,
            "appId": resolved_appid,
            "title": display_title,
            "tags": tags,
            "blocked": blocked,
            "matchType": match_type,
            "matchedTerm": matched_term,
            "reason": reason,
        }));
    }

    Ok(serde_json::json!({
        "success": true,
        "filterEnabled": filters.launcher_filter_enabled,
        "results": results,
    }))
}

fn resolve_lang_prefs(requested_lang: Option<&str>) -> (String, &'static str, &'static str) {
    let raw: String = requested_lang
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| db::normalize_primary_language(s).to_string())
        .unwrap_or_else(db::get_primary_language);
    if raw == "pt-BR" {
        (raw, "brazilian", "BR")
    } else {
        (raw, "english", "US")
    }
}

fn parse_group_pattern_details(pattern: &str) -> (Vec<String>, Vec<serde_json::Value>, Vec<String>) {
    let trimmed = pattern.trim();
    if trimmed.is_empty() {
        return (Vec::new(), Vec::new(), Vec::new());
    }
    if trimmed.starts_with('{') {
        if let Ok(serde_json::Value::Object(map)) = serde_json::from_str::<serde_json::Value>(trimmed)
        {
            let sites: Vec<String> = map
                .get("sites")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|item| {
                            item.as_str()
                                .map(str::trim)
                                .filter(|s| !s.is_empty())
                                .map(|s| s.to_string())
                                .or_else(|| {
                                    item.as_object()
                                        .and_then(|o| o.get("domain").or_else(|| o.get("url")).or_else(|| o.get("name")))
                                        .and_then(|v| v.as_str())
                                        .map(str::trim)
                                        .filter(|s| !s.is_empty())
                                        .map(|s| s.to_string())
                                })
                        })
                        .collect()
                })
                .unwrap_or_default();
            let apps: Vec<serde_json::Value> = map
                .get("apps")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|item| {
                            if let Some(s) = item.as_str().map(str::trim).filter(|s| !s.is_empty()) {
                                Some(serde_json::json!({ "name": s, "exec": s }))
                            } else if let Some(o) = item.as_object() {
                                let name = o.get("name").and_then(|v| v.as_str()).map(str::trim).unwrap_or("");
                                let exec = o.get("exec").and_then(|v| v.as_str()).map(str::trim).unwrap_or(name);
                                if name.is_empty() && exec.is_empty() {
                                    None
                                } else {
                                    Some(serde_json::json!({
                                        "name": if name.is_empty() { exec } else { name },
                                        "exec": exec,
                                    }))
                                }
                            } else {
                                None
                            }
                        })
                        .collect()
                })
                .unwrap_or_default();
            let keywords: Vec<String> = map
                .get("keywords")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|item| item.as_str().map(str::trim).filter(|s| !s.is_empty()).map(String::from))
                        .collect()
                })
                .unwrap_or_default();
            return (sites, apps, keywords);
        }
    }
    let sites: Vec<String> = trimmed
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(String::from)
        .collect();
    (sites, Vec::new(), Vec::new())
}

pub(crate) async fn handle_launchers_tags_payload_for_lang(
    requested_lang: Option<&str>,
) -> serde_json::Value {
    let (primary_lang, steam_lang, _) = resolve_lang_prefs(requested_lang);
    let raw_map = steam_api::ensure_tag_catalog_cached_async().await;
    let localized = steam_api::get_popular_steam_tags_localized(steam_lang);
    let display_tags: Vec<String> = localized.iter().map(|t| t.display_name.clone()).collect();
    let tag_map: serde_json::Map<String, serde_json::Value> = raw_map
        .into_iter()
        .map(|(tid, names)| {
            (
                tid.to_string(),
                serde_json::json!(db::normalize_term_list(&names)),
            )
        })
        .collect();
    serde_json::json!({
        "success": true,
        "primaryLanguage": primary_lang,
        "steamLanguage": steam_lang,
        "tags": display_tags,
        "tagItems": localized,
        "tagMap": tag_map,
    })
}

pub(crate) async fn handle_launchers_autocomplete_payload(
    kind: &str,
    query: &str,
    requested_lang: Option<&str>,
) -> serde_json::Value {
    let (primary_lang, steam_lang, country) = resolve_lang_prefs(requested_lang);
    if kind.eq_ignore_ascii_case("game") || kind.eq_ignore_ascii_case("games") {
        let results =
            steam_api::search_game_suggestions_async(query, steam_lang, country, 10).await;
        serde_json::json!({
            "success": true,
            "kind": "game",
            "primaryLanguage": primary_lang,
            "steamLanguage": steam_lang,
            "results": results,
        })
    } else {
        let results = steam_api::search_tag_suggestions_async(query, steam_lang, 12).await;
        serde_json::json!({
            "success": true,
            "kind": "tag",
            "primaryLanguage": primary_lang,
            "steamLanguage": steam_lang,
            "results": results,
        })
    }
}

pub(crate) fn build_focus_filters_envelope(filters: &db::FocusFilters) -> serde_json::Value {
    let anti_cheat = engine::get_anti_cheat_state();
    let (primary_lang, steam_lang, _) = resolve_lang_prefs(None);
    let tag_display_map =
        steam_api::translate_tags_for_display(&filters.launcher_blocked_tags, steam_lang);
    serde_json::json!({
        "revision": filters_revision(filters),
        "stateRevision": db::get_state_revision(),
        "antiCheatActive": anti_cheat.is_active,
        "antiCheatMode": anti_cheat.mode,
        "primaryLanguage": primary_lang,
        "steamLanguage": steam_lang,
        "tagDisplayMap": tag_display_map,
        "focusFilters": proxy::focus_filters_json_value(filters),
    })
}

pub(crate) fn build_status_payload() -> serde_json::Value {
    let sites = engine::get_all_site_rules_status();
    let sites_json: Vec<serde_json::Value> = sites
        .into_iter()
        .map(|s| {
            let (group_sites, group_apps, group_keywords) =
                parse_group_pattern_details(&s.pattern);
            serde_json::json!({
                "entityId": s.entity_id,
                "displayName": s.display_name,
                "targetType": s.target_type,
                "pattern": s.pattern,
                "groupSites": group_sites,
                "groupApps": group_apps,
                "groupKeywords": group_keywords,
                "dailyQuotaSeconds": s.daily_quota_seconds,
                "consumedSeconds": s.consumed_seconds,
                "remainingSeconds": s.remaining_seconds,
                "isBlocked": s.is_blocked,
                "counting": !s.is_blocked && engine::is_entity_counting(&s.entity_id),
                "emergencyTokensRemaining": s.emergency_tokens_remaining,
                "isWeekend": s.is_weekend,
                "weekendQuotaSeconds": s.weekend_quota_seconds,
            })
        })
        .collect();

    let filters = db::get_focus_filters();
    let anti_cheat = engine::get_anti_cheat_state();
    let (primary_lang, steam_lang, _) = resolve_lang_prefs(None);
    let tag_display_map =
        steam_api::translate_tags_for_display(&filters.launcher_blocked_tags, steam_lang);
    serde_json::json!({
        "online": true,
        "port": crate::profile::api_port(),
        "serverVersion": "1.2.0",
        "revision": filters_revision(&filters),
        "stateRevision": db::get_state_revision(),
        "primaryLanguage": primary_lang,
        "steamLanguage": steam_lang,
        "tagDisplayMap": tag_display_map,
        "antiCheatActive": anti_cheat.is_active,
        "antiCheatMode": anti_cheat.mode,
        "sites": sites_json,
        "focusFilters": proxy::focus_filters_json_value(&filters),
        "extensionUpdate": extension_update_status_json(),
        "adultFilter": crate::adult::status_json(),
    })
}

/// Browser-extension self-update hints read by `background.js`:
/// newest packaged version, whether auto-update is on, and a nonce bumped by
/// "Atualizar agora" in the app settings.
pub fn extension_update_status_json() -> serde_json::Value {
    serde_json::json!({
        "latestVersion": latest_extension_version_cached().unwrap_or_default(),
        "autoUpdate": extension_auto_update_enabled(),
        "requestNonce": db::get_config("ext_update_request_nonce").unwrap_or_default(),
        "firefoxLatestVersion": crate::firefox_updates::latest_firefox_version().unwrap_or_default(),
    })
}

pub fn extension_auto_update_enabled() -> bool {
    db::get_config("ext_auto_update").map_or(true, |v| v != "false")
}

pub fn set_extension_auto_update(enabled: bool) {
    let _ = db::set_config("ext_auto_update", if enabled { "true" } else { "false" });
    let _ = db::bump_state_revision();
}

pub fn request_extension_update_now() {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .to_string();
    let _ = db::set_config("ext_update_request_nonce", &nonce);
    let _ = db::bump_state_revision();
}

static LATEST_EXT_VERSION: parking_lot::Mutex<Option<(std::path::PathBuf, std::time::SystemTime, String)>> =
    parking_lot::Mutex::new(None);

/// Version of the CRX served at `/extension/chronos.crx`, cached by file mtime
/// (`/api/status` is polled every 1.5s).
pub fn latest_extension_version_cached() -> Option<String> {
    let path = find_chromium_extension_crx()?;
    let mtime = std::fs::metadata(&path).and_then(|m| m.modified()).ok()?;
    let mut guard = LATEST_EXT_VERSION.lock();
    if let Some((p, t, v)) = guard.as_ref() {
        if *p == path && *t == mtime {
            return Some(v.clone());
        }
    }
    let v = crx_manifest_version(&path)?;
    *guard = Some((path, mtime, v.clone()));
    Some(v)
}

fn filters_revision(f: &db::FocusFilters) -> String {
    let mem_rev = FILTER_REVISION.load(Ordering::Relaxed);
    let db_rev = db::get_state_revision();
    let anti_cheat = engine::get_anti_cheat_state();
    let ac_flag: u8 = if anti_cheat.is_active { 1 } else { 0 };
    let lang = db::get_primary_language();
    let json = proxy::focus_filters_json_value(f).to_string();
    let mut hash: u32 = 2166136261;
    for b in json
        .bytes()
        .chain(lang.bytes())
        .chain(anti_cheat.mode.bytes())
        .chain(std::iter::once(ac_flag))
    {
        hash ^= b as u32;
        hash = hash.wrapping_mul(16777619);
    }
    format!("{mem_rev}:{db_rev}:{ac_flag}:{hash}")
}

/// Streams real-time SSE `chronos_update` events whenever in-memory or SQLite revision advances.
pub async fn write_sse_stream<W: AsyncWrite + Unpin>(writer: &mut W) -> Result<(), String> {
    let head = concat!(
        "HTTP/1.1 200 OK\r\n",
        "Content-Type: text/event-stream; charset=utf-8\r\n",
        "Cache-Control: no-cache, no-store, must-revalidate\r\n",
        "Connection: keep-alive\r\n",
        "Access-Control-Allow-Origin: *\r\n",
        "\r\n"
    );
    writer
        .write_all(head.as_bytes())
        .await
        .map_err(|e| format!("SSE header write failed: {e}"))?;
    let _ = writer.flush().await;

    let mut rx = subscribe_state_events();
    let mut last_rev = filters_revision(&db::get_focus_filters());
    let init_payload = build_focus_filters_envelope(&db::get_focus_filters()).to_string();
    let init_event = format!("event: chronos_update\ndata: {init_payload}\n\n");
    if writer.write_all(init_event.as_bytes()).await.is_err() {
        return Ok(());
    }
    let _ = writer.flush().await;

    let mut keepalive_ticks: u32 = 0;
    loop {
        match tokio::time::timeout(Duration::from_millis(250), rx.recv()).await {
            Ok(Ok(_)) | Ok(Err(tokio::sync::broadcast::error::RecvError::Lagged(_))) => {
                let filters = db::get_focus_filters();
                last_rev = filters_revision(&filters);
                let payload = build_focus_filters_envelope(&filters).to_string();
                let msg = format!("event: chronos_update\ndata: {payload}\n\n");
                if writer.write_all(msg.as_bytes()).await.is_err() {
                    break;
                }
                let _ = writer.flush().await;
                keepalive_ticks = 0;
            }
            Ok(Err(tokio::sync::broadcast::error::RecvError::Closed)) => break,
            Err(_) => {
                let filters = db::get_focus_filters();
                let current_rev = filters_revision(&filters);
                if current_rev != last_rev {
                    last_rev = current_rev;
                    launchers::invalidate_launcher_caches();
                    watchdog_notify().notify_waiters();
                    let payload = build_focus_filters_envelope(&filters).to_string();
                    let msg = format!("event: chronos_update\ndata: {payload}\n\n");
                    if writer.write_all(msg.as_bytes()).await.is_err() {
                        break;
                    }
                    let _ = writer.flush().await;
                    keepalive_ticks = 0;
                } else {
                    keepalive_ticks += 1;
                    if keepalive_ticks >= 60 {
                        keepalive_ticks = 0;
                        if writer.write_all(b": keepalive\n\n").await.is_err() {
                            break;
                        }
                        let _ = writer.flush().await;
                    }
                }
            }
        }
    }
    Ok(())
}

fn format_minutes(seconds: i64) -> String {
    let h = seconds / 3600;
    let m = (seconds % 3600) / 60;
    if h > 0 {
        if m > 0 {
            format!("{h}h {m}m")
        } else {
            format!("{h}h")
        }
    } else {
        format!("{m}m")
    }
}

/// Block page in the app language (texts translated by `i18n::localize_html`).
fn render_blocked_html(
    display_name: &str,
    entity_id: &str,
    original_url: &str,
    daily_quota_text: &str,
    emergency_tokens: i64,
    custom_reason: Option<&str>,
    same_origin_api: bool,
) -> String {
    let reason = custom_reason.map(crate::i18n::tr_msg);
    crate::i18n::localize_html(&render_blocked_html_pt(
        display_name,
        entity_id,
        original_url,
        daily_quota_text,
        emergency_tokens,
        reason.as_deref(),
        same_origin_api,
    ))
}

fn render_blocked_html_pt(
    display_name: &str,
    entity_id: &str,
    original_url: &str,
    daily_quota_text: &str,
    emergency_tokens: i64,
    custom_reason: Option<&str>,
    same_origin_api: bool,
) -> String {
    let safe_name = html_escape(display_name);
    let safe_quota = html_escape(daily_quota_text);
    let is_launcher_block = entity_id == "launcher_filter" || custom_reason.is_some();
    let is_adult_block = entity_id == "adult_filter";
    let badge_text = if is_adult_block {
        "Filtro de Conteúdo Adulto"
    } else if is_launcher_block {
        "Filtro de Jogos & Launchers"
    } else {
        "Limite de Tempo Esgotado"
    };
    let headline_text = if is_adult_block {
        "Conteúdo Adulto Bloqueado"
    } else if is_launcher_block {
        "Conteúdo de Jogo Bloqueado"
    } else {
        "Site Indisponível"
    };
    let reason_html = if is_adult_block {
        let safe_reason = html_escape(custom_reason.unwrap_or("Conteúdo adulto").trim());
        format!(r#"Esta página foi bloqueada pelo filtro de conteúdo adulto: <strong>{safe_reason}</strong>."#)
    } else if let Some(r) = custom_reason.filter(|s| !s.trim().is_empty()) {
        let safe_reason = html_escape(r.trim());
        format!(
            r#"O conteúdo <span class="site-target">{safe_name}</span> (loja, página do jogo, guias, discussões ou artworks) foi bloqueado: <strong>{safe_reason}</strong>."#
        )
    } else {
        format!(
            r#"O site <span class="site-target">{safe_name}</span> não está disponível pois o seu tempo de tela diário acabou."#
        )
    };
    let js_url = serde_json::to_string(original_url).unwrap_or_else(|_| "\"\"".to_string());
    let js_entity = serde_json::to_string(entity_id).unwrap_or_else(|_| "\"\"".to_string());
    let js_name = serde_json::to_string(display_name).unwrap_or_else(|_| "\"\"".to_string());

    let info_rows_html = if is_launcher_block {
        format!(
            r#"<div class="info-row"><span class="info-label">Regra ativa:</span><span class="info-value">{safe_quota}</span></div>
      <div class="info-row"><span class="info-label">Status de segurança:</span><span class="info-value" style="color:#3fb950;">Bloqueio Ativo pelo Chronos</span></div>"#
        )
    } else {
        format!(
            r#"<div class="info-row"><span class="info-label">Tempo de tela diário:</span><span class="info-value">{safe_quota}</span></div>
      <div class="info-row"><span class="info-label">Próxima liberação:</span><span class="info-value">Amanhã à meia-noite (00:00)</span></div>
      <div class="info-row"><span class="info-label">Status de segurança:</span><span class="info-value" style="color:#3fb950;">Bloqueio Ativo pelo Chronos</span></div>"#
        )
    };

    let token_block = if is_adult_block {
        r#"<div class="token-section" style="border-color:rgba(255,255,255,0.1);background:rgba(255,255,255,0.03);">
      <div class="token-text" style="color:#8b949e;margin-bottom:0;">Tokens de emergência não liberam conteúdo adulto. Se esta página foi bloqueada por engano, adicione-a às <strong>Exceções</strong> do Filtro de Conteúdo Adulto (Anti-Burla deve estar desativado).</div>
    </div>"#
            .to_string()
    } else if is_launcher_block {
        r#"<div class="token-section" style="border-color:rgba(255,255,255,0.1);background:rgba(255,255,255,0.03);">
      <div class="token-text" style="color:#8b949e;margin-bottom:0;">Para liberar este conteúdo, remova a tag ou nome correspondente nas configurações de <strong>Launchers & Jogos</strong> (Anti-Burla deve estar desativado).</div>
    </div>"#
            .to_string()
    } else if emergency_tokens > 0 {
        format!(
            r#"<div class="token-section">
      <div class="token-text">Você possui <strong>{emergency_tokens} token(s)</strong> de emergência disponíveis este mês.</div>
      <button id="btn-token" class="btn-token" onclick="consumeToken()">Usar Token de Emergência (+1h)</button>
      <div id="status-msg" class="status-msg"></div>
    </div>"#
        )
    } else {
        r#"<div class="token-section" style="border-color:rgba(255,255,255,0.1);background:rgba(255,255,255,0.03);">
      <div class="token-text" style="color:#8b949e;margin-bottom:0;">Nenhum token de emergência restante para este mês.</div>
    </div>"#
            .to_string()
    };

    let api_prefix = if same_origin_api { "/__chronos_api__" } else { "/api" };
    let poll_script = if is_launcher_block {
        format!(
            r#"setInterval(async () => {{
      try {{
        const res = await fetch('{api_prefix}/launchers/resolve', {{
          method: 'POST',
          headers: {{ 'Content-Type': 'application/json' }},
          body: JSON.stringify({{ items: [{{ id: 'self', url: originalUrl, title: displayName }}] }})
        }});
        const data = await res.json();
        const item = data && Array.isArray(data.results) ? data.results[0] : null;
        if (item && item.blocked === false && originalUrl && originalUrl.startsWith('http')) {{
          window.location.href = originalUrl;
        }}
      }} catch (_) {{}}
    }}, 5000);"#
        )
    } else {
        r#"setInterval(async () => {
      try {
        const res = await fetch('/api/check?url=' + encodeURIComponent(originalUrl || entityId));
        const data = await res.json();
        if (data && data.blocked === false && originalUrl && originalUrl.startsWith('http')) {
          window.location.href = originalUrl;
        }
      } catch (_) {}
    }, 5000);"#
            .to_string()
    };

    format!(
        r#"<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{headline_text} - Chronos</title>
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{ background: radial-gradient(circle at 50% 20%, #1a1e24 0%, #0d1117 80%, #080a0d 100%); color: #e6edf3; font-family: system-ui, -apple-system, sans-serif; min-height: 100vh; display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 24px; line-height: 1.5; }}
    .container {{ max-width: 620px; width: 100%; background: rgba(22, 27, 34, 0.85); border: 1px solid rgba(248, 81, 73, 0.35); border-radius: 20px; padding: 44px 36px; text-align: center; box-shadow: 0 20px 50px rgba(0, 0, 0, 0.6); }}
    .badge {{ display: inline-block; background: rgba(248, 81, 73, 0.2); color: #ff7b72; font-size: 12px; font-weight: 700; letter-spacing: 1.2px; text-transform: uppercase; padding: 6px 14px; border-radius: 20px; border: 1px solid rgba(248, 81, 73, 0.4); margin-bottom: 16px; }}
    h1 {{ font-size: 28px; font-weight: 800; color: #fff; margin-bottom: 12px; }}
    .site-target {{ color: #f85149; font-weight: 800; }}
    p.message {{ font-size: 16px; color: #8b949e; margin-bottom: 28px; }}
    .card-info {{ background: rgba(13, 17, 23, 0.7); border: 1px solid rgba(255,255,255,0.08); border-radius: 14px; padding: 18px 20px; margin-bottom: 28px; text-align: left; }}
    .info-row {{ display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid rgba(255,255,255,0.05); font-size: 14px; }}
    .info-row:last-child {{ border-bottom: none; }}
    .info-label {{ color: #8b949e; }}
    .info-value {{ font-weight: 600; color: #e6edf3; }}
    .token-section {{ background: rgba(210, 153, 34, 0.1); border: 1px solid rgba(210, 153, 34, 0.3); border-radius: 14px; padding: 18px 20px; margin-bottom: 26px; }}
    .token-text {{ font-size: 14px; color: #d29922; margin-bottom: 12px; font-weight: 500; }}
    .btn-token {{ background: linear-gradient(135deg, #d29922 0%, #b07d12 100%); color: #000; font-size: 14px; font-weight: 700; border: none; padding: 12px 24px; border-radius: 10px; cursor: pointer; }}
    .status-msg {{ margin-top: 10px; font-size: 13px; font-weight: 600; display: none; }}
    .footer {{ margin-top: 24px; font-size: 12px; color: #484f58; }}
  </style>
</head>
<body>
  <div class="container">
    <div class="badge">{badge_text}</div>
    <h1>{headline_text}</h1>
    <p class="message">{reason_html}</p>
    <div class="card-info">
      {info_rows_html}
    </div>
    {token_block}
    <div class="footer">Chronos Focus Engine • Offline-first Productivity Guard</div>
  </div>
  <script>
    const originalUrl = {js_url};
    const entityId = {js_entity};
    const displayName = {js_name};
    async function consumeToken() {{
      const btn = document.getElementById('btn-token');
      const status = document.getElementById('status-msg');
      if (!btn) return;
      btn.disabled = true;
      btn.innerText = 'Ativando token...';
      try {{
        const resp = await fetch('/api/emergency-token?entityId=' + encodeURIComponent(entityId), {{ method: 'POST' }});
        const data = await resp.json();
        if (data.success) {{
          if (status) {{ status.style.display = 'block'; status.style.color = '#3fb950'; status.innerText = '✓ Token ativado! Retornando ao site...'; }}
          setTimeout(() => {{
            if (originalUrl && originalUrl.startsWith('http')) window.location.href = originalUrl;
            else window.location.reload();
          }}, 1200);
        }} else {{
          btn.disabled = false;
          btn.innerText = 'Usar Token de Emergência (+1h)';
          if (status) {{ status.style.display = 'block'; status.style.color = '#f85149'; status.innerText = data.message || 'Falha ao ativar token.'; }}
        }}
      }} catch (_) {{ btn.disabled = false; }}
    }}
    {poll_script}
  </script>
</body>
</html>"#
    )
}

pub(crate) fn render_launcher_blocked_html(
    title: &str,
    reason: &str,
    original_url: &str,
    same_origin_api: bool,
) -> String {
    render_blocked_html(
        title,
        "launcher_filter",
        original_url,
        "Filtro de Conteúdo (Steam API / Launchers)",
        0,
        Some(reason),
        same_origin_api,
    )
}

/// Public URL Chromium policies use to self-update the force-installed extension.
/// Chromium's extension updater fetches over the network stack, which cannot read
/// `file://` update manifests or CRX codebases, so they are served over loopback HTTP.
pub const EXTENSION_UPDATE_URL: &str = "http://127.0.0.1:4545/extension/update.xml";
const EXTENSION_CRX_URL: &str = "http://127.0.0.1:4545/extension/chronos.crx";
const CHROMIUM_EXTENSION_ID: &str = "jmbcpjljbgjabggbblfajojeahficjgi";

fn find_chromium_extension_crx() -> Option<std::path::PathBuf> {
    [
        std::path::PathBuf::from("/usr/local/share/chronos/chronos.crx"),
        crate::profile::data_dir().join("guard/build/chronos.crx"),
        crate::profile::data_dir().join("chronos_extension.crx"),
    ]
    .into_iter()
    .filter(|p| p.is_file())
    .max_by_key(|p| {
        crx_manifest_version(p)
            .map(|v| version_sort_key(&v))
            .unwrap_or_default()
    })
}

fn version_sort_key(v: &str) -> Vec<u64> {
    v.split('.').map(|n| n.trim().parse::<u64>().unwrap_or(0)).collect()
}

/// Reads `manifest.json`'s `version` straight out of a CRX3 file (header + zip).
pub(crate) fn crx_manifest_version(path: &std::path::Path) -> Option<String> {
    let bytes = std::fs::read(path).ok()?;
    if bytes.len() < 12 || &bytes[..4] != b"Cr24" {
        return None;
    }
    let header_len = u32::from_le_bytes(bytes[8..12].try_into().ok()?) as usize;
    let zip = bytes.get(12 + header_len..)?;
    let manifest = read_zip_entry(zip, "manifest.json")?;
    let parsed: serde_json::Value = serde_json::from_slice(&manifest).ok()?;
    parsed.get("version")?.as_str().map(str::to_string)
}

fn extension_reports_path() -> std::path::PathBuf {
    crate::profile::data_dir().join("extension_reports.json")
}

/// Version each browser's extension reported last ({browser: {ver, ts}}), written at most
/// every 30 s per browser.
fn record_extension_report(browser: &str, ver: &str) {
    if browser.is_empty() || ver.is_empty() || browser.len() > 24 || ver.len() > 24 {
        return;
    }
    static LAST: std::sync::OnceLock<parking_lot::Mutex<HashMap<String, (String, i64)>>> = std::sync::OnceLock::new();
    let now = chrono_now_ms();
    {
        let mut last = LAST.get_or_init(Default::default).lock();
        if let Some((v, t)) = last.get(browser) {
            if v == ver && now - *t < 30_000 {
                return;
            }
        }
        last.insert(browser.to_string(), (ver.to_string(), now));
    }
    let mut map: serde_json::Map<String, serde_json::Value> = std::fs::read_to_string(extension_reports_path())
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_default();
    map.insert(browser.to_string(), serde_json::json!({ "ver": ver, "ts": now }));
    let path = extension_reports_path();
    let tmp = path.with_extension("json.tmp");
    if std::fs::write(&tmp, serde_json::Value::Object(map).to_string()).is_ok() {
        let _ = std::fs::rename(&tmp, &path);
    }
}

fn chrono_now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// (browser, version, ms since the report) for every browser that reported.
pub fn extension_reports() -> Vec<(String, String, i64)> {
    let now = chrono_now_ms();
    let map: serde_json::Map<String, serde_json::Value> = std::fs::read_to_string(extension_reports_path())
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_default();
    map.into_iter()
        .map(|(b, v)| {
            let ver = v.get("ver").and_then(|x| x.as_str()).unwrap_or("").to_string();
            let ts = v.get("ts").and_then(|x| x.as_i64()).unwrap_or(0);
            (b, ver, now - ts)
        })
        .collect()
}

pub(crate) fn read_zip_entry_pub(zip: &[u8], wanted: &str) -> Option<Vec<u8>> {
    read_zip_entry(zip, wanted)
}

pub(crate) fn version_sort_key_pub(v: &str) -> Vec<u64> {
    version_sort_key(v)
}

/// Minimal local-file-header zip reader (stored or raw-deflate entries).
fn read_zip_entry(zip: &[u8], wanted: &str) -> Option<Vec<u8>> {
    use std::io::Read;
    let mut i = 0usize;
    while i + 30 <= zip.len() && zip[i..i + 4] == [0x50, 0x4b, 0x03, 0x04] {
        let u16_at = |o: usize| u16::from_le_bytes([zip[o], zip[o + 1]]) as usize;
        let u32_at = |o: usize| u32::from_le_bytes([zip[o], zip[o + 1], zip[o + 2], zip[o + 3]]) as usize;
        let flags = u16_at(i + 6);
        let method = u16_at(i + 8);
        let comp_size = u32_at(i + 18);
        let name_len = u16_at(i + 26);
        let extra_len = u16_at(i + 28);
        let name = std::str::from_utf8(zip.get(i + 30..i + 30 + name_len)?).ok()?;
        let data_start = i + 30 + name_len + extra_len;
        if flags & 0x08 != 0 {
            // Sizes in a data descriptor (Mozilla-signed XPIs): use the central directory.
            return read_zip_entry_central(zip, wanted);
        }
        let data = zip.get(data_start..data_start + comp_size)?;
        if name == wanted {
            return match method {
                0 => Some(data.to_vec()),
                8 => {
                    let mut out = Vec::new();
                    flate2::read::DeflateDecoder::new(data).read_to_end(&mut out).ok()?;
                    Some(out)
                }
                _ => None,
            };
        }
        i = data_start + comp_size;
    }
    None
}

/// Zip reader through the central directory (handles data descriptors).
fn read_zip_entry_central(zip: &[u8], wanted: &str) -> Option<Vec<u8>> {
    use std::io::Read;
    let u16_at = |o: usize| -> Option<usize> { Some(u16::from_le_bytes([*zip.get(o)?, *zip.get(o + 1)?]) as usize) };
    let u32_at = |o: usize| -> Option<usize> {
        Some(u32::from_le_bytes([*zip.get(o)?, *zip.get(o + 1)?, *zip.get(o + 2)?, *zip.get(o + 3)?]) as usize)
    };
    // End of central directory record (search the last 64 KiB).
    let start = zip.len().saturating_sub(65_557);
    let eocd = (start..zip.len().saturating_sub(21)).rev().find(|&i| zip[i..i + 4] == [0x50, 0x4b, 0x05, 0x06])?;
    let entries = u16_at(eocd + 10)?;
    let mut p = u32_at(eocd + 16)?;
    for _ in 0..entries {
        if zip.get(p..p + 4)? != [0x50, 0x4b, 0x01, 0x02] {
            return None;
        }
        let method = u16_at(p + 10)?;
        let comp_size = u32_at(p + 20)?;
        let name_len = u16_at(p + 28)?;
        let extra_len = u16_at(p + 30)?;
        let comment_len = u16_at(p + 32)?;
        let local = u32_at(p + 42)?;
        let name = std::str::from_utf8(zip.get(p + 46..p + 46 + name_len)?).ok()?;
        if name == wanted {
            let lname = u16_at(local + 26)?;
            let lextra = u16_at(local + 28)?;
            let data_start = local + 30 + lname + lextra;
            let data = zip.get(data_start..data_start + comp_size)?;
            return match method {
                0 => Some(data.to_vec()),
                8 => {
                    let mut out = Vec::new();
                    flate2::read::DeflateDecoder::new(data).read_to_end(&mut out).ok()?;
                    Some(out)
                }
                _ => None,
            };
        }
        p += 46 + name_len + extra_len + comment_len;
    }
    None
}

pub(crate) fn chromium_extension_update_manifest() -> Option<String> {
    let crx = find_chromium_extension_crx()?;
    let version = crx_manifest_version(&crx)?;
    Some(format!(
        "<?xml version='1.0' encoding='UTF-8'?>\n\
<gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'>\n\
  <app appid='{CHROMIUM_EXTENSION_ID}'>\n\
    <updatecheck codebase='{EXTENSION_CRX_URL}' version='{version}' />\n\
  </app>\n\
</gupdate>\n"
    ))
}

async fn handle_api_connection(mut stream: TcpStream) -> Result<(), String> {
    let Some(req) = proxy::read_http_head(&mut stream).await? else {
        return Ok(());
    };
    if !req.is_request {
        return Ok(());
    }

    if req.method_or_status.eq_ignore_ascii_case("OPTIONS") {
        proxy::send_simple_response(&mut stream, "204 No Content", "text/plain", &CORS_HEADERS, b"")
            .await?;
        let _ = stream.shutdown().await;
        return Ok(());
    }

    let req_body = if !req.body_start.is_empty()
        || proxy::get_header(&req.headers, "content-length").is_some()
        || proxy::get_header(&req.headers, "transfer-encoding")
            .map(|v| v.to_ascii_lowercase().contains("chunked"))
            .unwrap_or(false)
    {
        let (body, _) =
            proxy::read_body_bytes(&mut stream, &req.body_start, &req.headers, false, 1024 * 1024)
                .await?;
        body
    } else {
        Vec::new()
    };

    let (path, query) = split_path_and_query(&req.target_or_reason);
    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64;

    match path {
        "/extension/update.xml" => {
            eprintln!(
                "chronos ext update: {} {} ua={}",
                req.method_or_status,
                req.target_or_reason,
                proxy::get_header(&req.headers, "user-agent").unwrap_or("")
            );
            let (status, ctype, body) = match chromium_extension_update_manifest() {
                Some(xml) => ("200 OK", "application/xml; charset=utf-8", xml.into_bytes()),
                None => ("404 Not Found", "text/plain", b"no crx".to_vec()),
            };
            proxy::send_simple_response(&mut stream, status, ctype, &[("Cache-Control", "no-store")], &body)
                .await?;
        }
        "/extension/chronos.crx" => {
            eprintln!("chronos ext crx download: {}", req.target_or_reason);
            match find_chromium_extension_crx().and_then(|p| std::fs::read(p).ok()) {
                Some(bytes) => {
                    proxy::send_simple_response(
                        &mut stream,
                        "200 OK",
                        "application/x-chrome-extension",
                        &[("Cache-Control", "no-store")],
                        &bytes,
                    )
                    .await?
                }
                None => {
                    proxy::send_simple_response(&mut stream, "404 Not Found", "text/plain", &[], b"no crx")
                        .await?
                }
            }
        }
        "/api/ping" => {
            let body = serde_json::json!({
                "pong": true,
                "daemon": "chronos_proxy",
                "timestamp": now_ms,
            })
            .to_string();
            proxy::send_simple_response(
                &mut stream,
                "200 OK",
                "application/json; charset=utf-8",
                &CORS_HEADERS,
                body.as_bytes(),
            )
            .await?;
        }
        "/api/status" => {
            let active_url = query.get("activeUrl").map(String::as_str).unwrap_or("");
            let active_title = query.get("activeTitle").map(String::as_str).unwrap_or("");
            let audible_url = query.get("audibleUrl").map(String::as_str).unwrap_or("");
            let audible_title = query.get("audibleTitle").map(String::as_str).unwrap_or("");
            let reporter = query.get("reporter").map(String::as_str).unwrap_or("");
            record_active_browser_tab(active_url, active_title, audible_url, audible_title, reporter);
            if let (Some(ver), Some(browser)) = (query.get("ver"), query.get("browser")) {
                record_extension_report(browser, ver);
            }
            if let Some(inc) = query.get("incognito") {
                // Lock: incognito stays available only while the extension runs there.
                let browser = query.get("browser").map(String::as_str).unwrap_or("");
                if crate::adult::record_incognito_access(reporter, inc == "1", browser) {
                    eprintln!("chronos: extensão {reporter} sem acesso ao anônimo; bloqueando a guia anônima de novo");
                    crate::adult::relock_private_browsing();
                }
            }

            let body = build_status_payload().to_string();
            proxy::send_simple_response(
                &mut stream,
                "200 OK",
                "application/json; charset=utf-8",
                &CORS_HEADERS,
                body.as_bytes(),
            )
            .await?;
        }
        "/api/focus-filters" => {
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
                        apply_focus_filters_update(&obj);
                    let status = if anti_cheat_locked {
                        "403 Forbidden"
                    } else {
                        "200 OK"
                    };
                    let mut payload = build_focus_filters_envelope(&updated);
                    if let Some(map) = payload.as_object_mut() {
                        map.insert("success".to_string(), serde_json::json!(ok));
                        map.insert(
                            "antiCheatLocked".to_string(),
                            serde_json::json!(anti_cheat_locked),
                        );
                        map.insert("message".to_string(), serde_json::json!(message));
                    }
                    let body = payload.to_string();
                    proxy::send_simple_response(
                        &mut stream,
                        status,
                        "application/json; charset=utf-8",
                        &CORS_HEADERS,
                        body.as_bytes(),
                    )
                    .await?;
                } else {
                    proxy::send_simple_response(
                        &mut stream,
                        "400 Bad Request",
                        "application/json; charset=utf-8",
                        &CORS_HEADERS,
                        br#"{"error":"Invalid JSON"}"#,
                    )
                    .await?;
                }
            } else {
                let filters = db::get_focus_filters();
                let mut payload = build_focus_filters_envelope(&filters);
                if let Some(map) = payload.as_object_mut() {
                    map.insert("success".to_string(), serde_json::json!(true));
                }
                let body = payload.to_string();
                proxy::send_simple_response(
                    &mut stream,
                    "200 OK",
                    "application/json; charset=utf-8",
                    &CORS_HEADERS,
                    body.as_bytes(),
                )
                .await?;
            }
        }
        "/api/language" => {
            if req.method_or_status.eq_ignore_ascii_case("POST") {
                if let Ok(serde_json::Value::Object(obj)) =
                    serde_json::from_slice::<serde_json::Value>(&req_body)
                {
                    let raw = obj
                        .get("primaryLanguage")
                        .or_else(|| obj.get("language"))
                        .and_then(|v| v.as_str())
                        .unwrap_or("pt-BR");
                    let saved = db::set_primary_language(raw).unwrap_or_else(|_| db::get_primary_language());
                    let rev = notify_state_changed();
                    let body = serde_json::json!({
                        "success": true,
                        "primaryLanguage": saved,
                        "stateRevision": rev,
                    })
                    .to_string();
                    proxy::send_simple_response(
                        &mut stream,
                        "200 OK",
                        "application/json; charset=utf-8",
                        &CORS_HEADERS,
                        body.as_bytes(),
                    )
                    .await?;
                } else {
                    proxy::send_simple_response(
                        &mut stream,
                        "400 Bad Request",
                        "application/json; charset=utf-8",
                        &CORS_HEADERS,
                        br#"{"success":false,"error":"Invalid JSON"}"#,
                    )
                    .await?;
                }
            } else {
                let (primary_lang, steam_lang, _) = resolve_lang_prefs(query.get("lang").map(String::as_str));
                let body = serde_json::json!({
                    "success": true,
                    "primaryLanguage": primary_lang,
                    "steamLanguage": steam_lang,
                })
                .to_string();
                proxy::send_simple_response(
                    &mut stream,
                    "200 OK",
                    "application/json; charset=utf-8",
                    &CORS_HEADERS,
                    body.as_bytes(),
                )
                .await?;
            }
        }
        "/api/launchers/resolve" => {
            match handle_launchers_resolve_payload(&req_body).await {
                Ok(payload) => {
                    proxy::send_simple_response(
                        &mut stream,
                        "200 OK",
                        "application/json; charset=utf-8",
                        &CORS_HEADERS,
                        payload.to_string().as_bytes(),
                    )
                    .await?;
                }
                Err(_) => {
                    proxy::send_simple_response(
                        &mut stream,
                        "400 Bad Request",
                        "application/json; charset=utf-8",
                        &CORS_HEADERS,
                        br#"{"success":false,"error":"Invalid JSON"}"#,
                    )
                    .await?;
                }
            }
        }
        "/api/youtube/types" => {
            let types: Vec<serde_json::Value> = crate::api::youtube::get_youtube_content_types()
                .into_iter()
                .map(|t| serde_json::json!({"id": t.id, "label": t.label}))
                .collect();
            let mut wl: Vec<String> = crate::youtube::whitelist_exemptions().into_keys().collect();
            wl.sort();
            let body = serde_json::json!({"success": true, "types": types, "whitelistTypes": wl}).to_string();
            proxy::send_simple_response(
                &mut stream,
                "200 OK",
                "application/json; charset=utf-8",
                &CORS_HEADERS,
                body.as_bytes(),
            )
            .await?;
        }
        "/api/youtube/classify" => {
            let payload = crate::youtube::handle_classify_payload(&req_body).await;
            proxy::send_simple_response(
                &mut stream,
                "200 OK",
                "application/json; charset=utf-8",
                &CORS_HEADERS,
                payload.to_string().as_bytes(),
            )
            .await?;
        }
        "/api/launchers/tags" => {
            let payload = handle_launchers_tags_payload_for_lang(query.get("lang").map(String::as_str)).await;
            proxy::send_simple_response(
                &mut stream,
                "200 OK",
                "application/json; charset=utf-8",
                &CORS_HEADERS,
                payload.to_string().as_bytes(),
            )
            .await?;
        }
        "/api/launchers/autocomplete" => {
            let kind = query.get("kind").map(String::as_str).unwrap_or("tag");
            let q = query.get("q").map(String::as_str).unwrap_or("");
            let req_lang = query.get("lang").map(String::as_str);
            let payload = handle_launchers_autocomplete_payload(kind, q, req_lang).await;
            proxy::send_simple_response(
                &mut stream,
                "200 OK",
                "application/json; charset=utf-8",
                &CORS_HEADERS,
                payload.to_string().as_bytes(),
            )
            .await?;
        }
        "/api/events" => {
            write_sse_stream(&mut stream).await?;
            let _ = stream.shutdown().await;
            return Ok(());
        }
        "/api/nudge" => {
            let rev = notify_state_changed();
            let body = serde_json::json!({
                "success": true,
                "stateRevision": rev,
                "timestamp": now_ms,
            })
            .to_string();
            proxy::send_simple_response(
                &mut stream,
                "200 OK",
                "application/json; charset=utf-8",
                &CORS_HEADERS,
                body.as_bytes(),
            )
            .await?;
        }
        "/api/ext/diag" => {
            // Extension diagnostics (image AI): printed to the daemon journal.
            let msg = query.get("msg").map(String::as_str).unwrap_or("");
            let reporter = query.get("reporter").map(String::as_str).unwrap_or("");
            eprintln!("chronos ext diag [{reporter}]: {}", msg.chars().take(600).collect::<String>());
            proxy::send_simple_response(
                &mut stream,
                "200 OK",
                "application/json; charset=utf-8",
                &CORS_HEADERS,
                br#"{"ok":true}"#,
            )
            .await?;
        }
        "/api/adult/log" => {
            // Extension-side +18 blocks (Reddit/X filters) are logged here.
            let url_param = query.get("url").map(String::as_str).unwrap_or("");
            if !url_param.is_empty() {
                let kind = query.get("kind").map(String::as_str).unwrap_or("");
                crate::adult::log_social_attempt(url_param, kind);
            }
            proxy::send_simple_response(
                &mut stream,
                "200 OK",
                "application/json; charset=utf-8",
                &CORS_HEADERS,
                br#"{"ok":true}"#,
            )
            .await?;
        }
        "/api/check" => {
            let url_param = query.get("url").map(String::as_str).unwrap_or("");
            let domain_param = query.get("domain").map(String::as_str).unwrap_or("");
            let title_param = query.get("title").map(String::as_str).unwrap_or("");
            let target = if !url_param.is_empty() { url_param } else { domain_param };
            let focused_param = query.get("focused").map(String::as_str).unwrap_or("1");
            if !url_param.is_empty() && focused_param != "0" {
                record_focused_browser_tab(url_param, title_param, "extension");
            }
            crate::youtube::warm_classification(target).await;

            if let Some(hit) = crate::adult::check(target, title_param) {
                let body = serde_json::json!({
                    "blocked": true,
                    "entityId": "adult_filter",
                    "displayName": "Conteúdo adulto",
                    "reason": crate::adult::blocked_reason(&hit),
                    "remainingSeconds": 0,
                    "dailyQuotaSeconds": 0,
                    "targetType": "ADULT",
                })
                .to_string();
                proxy::send_simple_response(
                    &mut stream,
                    "200 OK",
                    "application/json; charset=utf-8",
                    &CORS_HEADERS,
                    body.as_bytes(),
                )
                .await?;
            } else if let Some(safe) = crate::adult::safe_search_target(target) {
                // Extension applies SafeSearch right away (browser policies reload slowly).
                let body = serde_json::json!({ "blocked": false, "safeSearchRedirect": safe }).to_string();
                proxy::send_simple_response(
                    &mut stream,
                    "200 OK",
                    "application/json; charset=utf-8",
                    &CORS_HEADERS,
                    body.as_bytes(),
                )
                .await?;
            } else if proxy::is_whitelisted_target(target, title_param) {
                proxy::send_simple_response(
                    &mut stream,
                    "200 OK",
                    "application/json; charset=utf-8",
                    &CORS_HEADERS,
                    br#"{"blocked":false,"whitelisted":true}"#,
                )
                .await?;
            } else {
                let sites = engine::get_all_site_rules_status();
                let body = if let Some(matched) = proxy::find_matching_rule(target, title_param, &sites) {
                    serde_json::json!({
                        "blocked": matched.is_blocked,
                        "entityId": matched.entity_id,
                        "displayName": matched.display_name,
                        "remainingSeconds": matched.remaining_seconds,
                        "dailyQuotaSeconds": matched.daily_quota_seconds,
                        "emergencyTokensRemaining": matched.emergency_tokens_remaining,
                        "targetType": matched.target_type,
                        "counting": !matched.is_blocked && engine::is_entity_counting(&matched.entity_id),
                    })
                    .to_string()
                } else {
                    r#"{"blocked":false,"matched":false}"#.to_string()
                };
                proxy::send_simple_response(
                    &mut stream,
                    "200 OK",
                    "application/json; charset=utf-8",
                    &CORS_HEADERS,
                    body.as_bytes(),
                )
                .await?;
            }
        }
        "/api/emergency-token" => {
            let mut entity_id = query.get("entityId").cloned().unwrap_or_default();
            if entity_id.is_empty() {
                if let Ok(serde_json::Value::Object(map)) = serde_json::from_slice(&req_body) {
                    if let Some(id) = map.get("entityId").and_then(|v| v.as_str()) {
                        entity_id = id.to_string();
                    }
                }
            }
            if entity_id.is_empty() {
                proxy::send_simple_response(
                    &mut stream,
                    "400 Bad Request",
                    "application/json; charset=utf-8",
                    &CORS_HEADERS,
                    br#"{"success":false,"message":"entityId is required"}"#,
                )
                .await?;
            } else {
                let res = engine::use_emergency_token(&entity_id);
                if res.success {
                    notify_state_changed();
                }
                let body = serde_json::json!({
                    "success": res.success,
                    "message": res.message,
                })
                .to_string();
                proxy::send_simple_response(
                    &mut stream,
                    "200 OK",
                    "application/json; charset=utf-8",
                    &CORS_HEADERS,
                    body.as_bytes(),
                )
                .await?;
            }
        }
        "/api/tab_closed" => {
            clear_focused_browser_tab();
            let body = serde_json::json!({ "success": true, "timestamp": now_ms }).to_string();
            proxy::send_simple_response(
                &mut stream,
                "200 OK",
                "application/json; charset=utf-8",
                &CORS_HEADERS,
                body.as_bytes(),
            )
            .await?;
        }
        "/proxy.pac" => {
            let pac = format!(
                r#"function FindProxyForURL(url, host) {{
  if (isPlainHostName(host) ||
      shExpMatch(host, "127.*") ||
      shExpMatch(host, "10.*") ||
      shExpMatch(host, "192.168.*") ||
      host === "localhost" ||
      host === "::1") {{
    return "DIRECT";
  }}
  return "PROXY 127.0.0.1:{}; DIRECT";
}}
"#,
                crate::profile::proxy_port()
            );
            proxy::send_simple_response(
                &mut stream,
                "200 OK",
                "application/x-ns-proxy-autoconfig; charset=utf-8",
                &CORS_HEADERS,
                pac.as_bytes(),
            )
            .await?;
        }
        "/" | "/blocked" | "/blocked.html" => {
            let entity = query.get("entity").or_else(|| query.get("entityId")).map(String::as_str).unwrap_or("");
            let site = query.get("site").or_else(|| query.get("name")).map(String::as_str).unwrap_or("");
            let orig_url = query.get("url").map(String::as_str).unwrap_or("");
            let custom_reason = query.get("reason").map(String::as_str).filter(|s| !s.trim().is_empty());
            let sites = engine::get_all_site_rules_status();
            let current = if entity == "launcher_filter" {
                None
            } else if !entity.is_empty() {
                sites.iter().find(|s| s.entity_id.eq_ignore_ascii_case(entity))
            } else if !site.is_empty() {
                proxy::find_matching_rule(site, "", &sites)
            } else {
                None
            };
            let display = current
                .map(|r| r.display_name.as_str())
                .unwrap_or_else(|| if !site.is_empty() { site } else if !entity.is_empty() && entity != "launcher_filter" { entity } else { "Jogo / Conteúdo Filtrado" });
            let active_id = current
                .map(|r| r.entity_id.as_str())
                .unwrap_or_else(|| if !entity.is_empty() { entity } else { "youtube" });
            let quota_text = if entity == "launcher_filter" || custom_reason.is_some() {
                "Filtro de Conteúdo (Steam API / Launchers)".to_string()
            } else {
                current
                    .map(|r| format_minutes(r.daily_quota_seconds))
                    .unwrap_or_else(|| "Limite diário".to_string())
            };
            let tokens = current.map(|r| r.emergency_tokens_remaining).unwrap_or(2);
            let html = render_blocked_html(
                display,
                active_id,
                orig_url,
                &quota_text,
                tokens,
                custom_reason,
                false,
            );
            proxy::send_simple_response(
                &mut stream,
                "200 OK",
                "text/html; charset=utf-8",
                &CORS_HEADERS,
                html.as_bytes(),
            )
            .await?;
        }
        _ => {
            proxy::send_simple_response(
                &mut stream,
                "404 Not Found",
                "text/plain; charset=utf-8",
                &CORS_HEADERS,
                b"404 - Rota nao encontrada no Chronos Server",
            )
            .await?;
        }
    }
    let _ = stream.shutdown().await;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_active_tab_merge_keeps_audible_and_whitelist_per_item() {
        // /api/status: focused + audible
        let a = merge_active_tab_report(None, Some(("https://www.youtube.com/watch?v=EduVid12345", "Aula")), Some(("https://www.youtube.com/watch?v=EduVid12345", "Aula")), 1000, "extension", "chrome");
        // /api/check from another (focused) tab must not wipe the audible tab
        let b = merge_active_tab_report(Some(a.clone()), Some(("https://docs.google.com/x", "Doc")), None, 2000, "extension", "");
        assert_eq!(b["url"], "https://docs.google.com/x");
        assert_eq!(b["timestamp_ms"], 2000);
        assert_eq!(b["audible_url"], "https://www.youtube.com/watch?v=EduVid12345");
        assert_eq!(b["audible_timestamp_ms"], 1000, "audible keeps its own timestamp");
        // /api/status with the browser unfocused: keeps the focused part, refreshes audible
        // Another browser (Chromium) with nothing playing must not erase Chrome's audio
        let other = merge_active_tab_report(Some(b.clone()), None, Some(("", "")), 2500, "extension", "chromium");
        assert_eq!(other["audible_url"], "https://www.youtube.com/watch?v=EduVid12345");
        assert_eq!(other["audible_reporter"], "chrome");
        // The same browser stopping playback clears it
        let c = merge_active_tab_report(Some(other), None, Some(("", "")), 3000, "extension", "chrome");
        assert_eq!(c["url"], "https://docs.google.com/x");
        assert_eq!(c["audible_url"], "");
        // Our own pages are never recorded
        let d = merge_active_tab_report(None, Some(("http://127.0.0.1:4545/blocked", "x")), None, 1, "extension", "");
        assert_eq!(d["url"], "");

        // Whitelisting one item of a group must not exempt the whole group
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db_file = format!("/tmp/chronos_wl_item_{}.db", std::process::id());
        let _ = std::fs::remove_file(&db_file);
        db::init_db(&db_file).expect("init temp db");
        crate::engine::save_rule(
            "group_study",
            "Estudo",
            60,
            "SELF_CONTROL",
            "GROUP",
            r#"{"apps":[{"name":"LibreOffice","exec":"libreoffice"}],"sites":["youtube.com"]}"#,
            None,
            None,
        )
        .unwrap();
        db::get_conn()
            .lock()
            .execute(
                "INSERT INTO usage_intervals (interval_id, entity_id, device_id, started_at_utc, ended_at_utc) VALUES ('u1','group_study','d',?1,?2)",
                (now_millis() / 1000 - 120, now_millis() / 1000 - 30),
            )
            .unwrap();
        db::save_whitelist_group("wl", "WL", r#"{"apps":[{"name":"LibreOffice","exec":"libreoffice"}],"sites":[]}"#).unwrap();
        let st = crate::engine::get_all_site_rules_status();
        let study = st.iter().find(|s| s.entity_id == "group_study").expect("rule status");
        assert!(study.is_blocked, "quota used up: YouTube in the group stays blocked even with LibreOffice whitelisted");
        assert!(crate::proxy::find_blocked_rule("https://www.youtube.com/watch?v=x", &st).is_some());
        let _ = std::fs::remove_file(db_file);
    }

    #[test]
    fn test_extension_auto_update_toggle_and_request_nonce() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db_file = format!("/tmp/chronos_ext_update_{}.db", std::process::id());
        let _ = std::fs::remove_file(&db_file);
        db::init_db(&db_file).expect("init temp db");

        assert!(extension_auto_update_enabled(), "on by default");
        let s0 = extension_update_status_json();
        assert_eq!(s0["autoUpdate"], true);
        let nonce0 = s0["requestNonce"].as_str().unwrap_or("").to_string();

        set_extension_auto_update(false);
        assert_eq!(extension_update_status_json()["autoUpdate"], false);
        request_extension_update_now();
        let nonce1 = extension_update_status_json()["requestNonce"].as_str().unwrap().to_string();
        assert_ne!(nonce0, nonce1, "'Atualizar agora' must change the nonce seen by extensions");
        assert!(build_status_payload().get("extensionUpdate").is_some());

        let _ = std::fs::remove_file(db_file);
    }

    #[test]
    fn test_crx_manifest_version_reader_stored_and_deflated() {
        use std::io::Write;
        fn zip_with(name: &str, data: &[u8], deflate: bool) -> Vec<u8> {
            let payload = if deflate {
                let mut enc = flate2::write::DeflateEncoder::new(Vec::new(), flate2::Compression::default());
                enc.write_all(data).unwrap();
                enc.finish().unwrap()
            } else {
                data.to_vec()
            };
            let mut z = vec![0x50, 0x4b, 0x03, 0x04, 20, 0, 0, 0];
            z.extend_from_slice(&(if deflate { 8u16 } else { 0u16 }).to_le_bytes());
            z.extend_from_slice(&[0; 8]); // time, date, crc (unchecked)
            z.extend_from_slice(&(payload.len() as u32).to_le_bytes());
            z.extend_from_slice(&(data.len() as u32).to_le_bytes());
            z.extend_from_slice(&(name.len() as u16).to_le_bytes());
            z.extend_from_slice(&0u16.to_le_bytes());
            z.extend_from_slice(name.as_bytes());
            z.extend_from_slice(&payload);
            z
        }
        let dir = std::env::temp_dir().join(format!("chronos_crx_test_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        for (i, deflate) in [false, true].into_iter().enumerate() {
            let mut crx = b"Cr24".to_vec();
            crx.extend_from_slice(&3u32.to_le_bytes());
            crx.extend_from_slice(&4u32.to_le_bytes());
            crx.extend_from_slice(b"HDR!");
            crx.extend(zip_with("README.md", b"x", false));
            crx.extend(zip_with("manifest.json", br#"{"manifest_version":3,"version":"1.1.48"}"#, deflate));
            let path = dir.join(format!("t{i}.crx"));
            std::fs::write(&path, &crx).unwrap();
            assert_eq!(crx_manifest_version(&path).as_deref(), Some("1.1.48"));
        }
        std::fs::write(dir.join("bad.crx"), b"PK\x03\x04not a crx").unwrap();
        assert!(crx_manifest_version(&dir.join("bad.crx")).is_none());
        assert!(version_sort_key("1.1.48") > version_sort_key("1.1.9"));
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn test_split_and_percent_decode() {
        let (path, q) = split_path_and_query("/api/check?url=https%3A%2F%2Fyoutube.com%2Fshorts%2Fabc&title=Test+Video");
        assert_eq!(path, "/api/check");
        assert_eq!(q.get("url").map(String::as_str), Some("https://youtube.com/shorts/abc"));
        assert_eq!(q.get("title").map(String::as_str), Some("Test Video"));
    }

    #[test]
    fn test_parse_group_pattern_details_and_autocomplete_and_sse() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db_file = format!("/tmp/chronos_local_api_test_{}.db", std::process::id());
        let _ = std::fs::remove_file(&db_file);
        crate::db::init_db(&db_file).expect("init temp db");

        let (sites, apps, kw) = parse_group_pattern_details(
            r#"{"apps":[{"name":"Youtube","exec":"youtube"}],"sites":["youtube.com","reddit.com"],"keywords":["shorts"]}"#,
        );
        assert_eq!(sites, vec!["youtube.com", "reddit.com"]);
        assert_eq!(apps.len(), 1);
        assert_eq!(apps[0]["name"].as_str(), Some("Youtube"));
        assert_eq!(kw, vec!["shorts"]);

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let ac = handle_launchers_autocomplete_payload("tag", "acao", Some("pt-BR")).await;
            assert_eq!(ac["success"], true);
            assert_eq!(ac["primaryLanguage"], "pt-BR");
            let first = ac["results"].as_array().and_then(|a| a.first()).expect("Action result");
            assert_eq!(first["canonicalEn"], "Action");
            assert_eq!(first["displayName"], "Ação");

            let (mut server_end, mut client_end) = tokio::io::duplex(8192);
            let sse_task = tokio::spawn(async move {
                let _ = write_sse_stream(&mut server_end).await;
            });

            let mut buf = vec![0u8; 4096];
            use tokio::io::AsyncReadExt;
            let n1 = tokio::time::timeout(Duration::from_secs(2), client_end.read(&mut buf))
                .await
                .expect("sse init timeout")
                .expect("sse read");
            let text1 = String::from_utf8_lossy(&buf[..n1]);
            assert!(text1.contains("text/event-stream"));
            assert!(text1.contains("event: chronos_update"));
            assert!(text1.contains("tagDisplayMap"));

            let _ = notify_state_changed();
            let mut n2_buf = vec![0u8; 4096];
            let n2 = tokio::time::timeout(Duration::from_secs(2), client_end.read(&mut n2_buf))
                .await
                .expect("sse nudge timeout")
                .expect("sse read 2");
            let text2 = String::from_utf8_lossy(&n2_buf[..n2]);
            assert!(text2.contains("event: chronos_update"));

            drop(client_end);
            let _ = tokio::time::timeout(Duration::from_secs(2), sse_task).await;
        });

        let _ = std::fs::remove_file(db_file);
    }

    #[test]
    fn test_anti_cheat_enable_and_disable_unlocks_steam_filters_and_sse() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db_file = format!("/tmp/chronos_ac_toggle_test_{}.db", std::process::id());
        let _ = std::fs::remove_file(&db_file);
        crate::db::init_db(&db_file).expect("init temp db");

        let mut filters = db::FocusFilters::default();
        filters.launcher_filter_enabled = true;
        filters.launcher_blocked_tags = vec!["NSFW".to_string()];
        filters.launcher_blocked_names = vec!["Counter-Strike 2".to_string()];
        db::set_focus_filters(&filters);

        engine::enable_anti_cheat("CHALLENGE", None).expect("enable anti-cheat");
        let active_env = build_focus_filters_envelope(&db::get_focus_filters());
        assert_eq!(active_env["antiCheatActive"], true);
        assert_eq!(active_env["antiCheatMode"], "CHALLENGE");

        // Attempting to disable Steam/launcher filter while Anti-Burla is active must fail
        let disable_attempt = serde_json::json!({
            "launcherFilterEnabled": false,
            "launcherBlockedTags": [],
            "launcherBlockedNames": [],
        });
        let (ok_locked, ac_locked, _, _) =
            apply_focus_filters_update(disable_attempt.as_object().unwrap());
        assert!(!ok_locked);
        assert!(ac_locked);

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let (mut server_end, mut client_end) = tokio::io::duplex(8192);
            let sse_task = tokio::spawn(async move {
                let _ = write_sse_stream(&mut server_end).await;
            });

            use tokio::io::AsyncReadExt;
            let mut buf = vec![0u8; 4096];
            let n1 = tokio::time::timeout(Duration::from_secs(2), client_end.read(&mut buf))
                .await
                .expect("sse init timeout")
                .expect("sse init read");
            let text1 = String::from_utf8_lossy(&buf[..n1]);
            assert!(text1.contains("\"antiCheatActive\":true"), "got: {text1}");

            engine::disable_anti_cheat(&engine::current_challenge_text())
                .expect("disable anti-cheat");
            let _ = notify_state_changed();

            let mut n2_buf = vec![0u8; 4096];
            let n2 = tokio::time::timeout(Duration::from_secs(2), client_end.read(&mut n2_buf))
                .await
                .expect("sse update timeout")
                .expect("sse update read");
            let text2 = String::from_utf8_lossy(&n2_buf[..n2]);
            assert!(text2.contains("event: chronos_update"), "got: {text2}");
            assert!(text2.contains("\"antiCheatActive\":false"), "got: {text2}");
            assert!(text2.contains("\"antiCheatMode\":\"OFF\""), "got: {text2}");

            drop(client_end);
            let _ = tokio::time::timeout(Duration::from_secs(2), sse_task).await;
        });

        let post_env = build_focus_filters_envelope(&db::get_focus_filters());
        assert_eq!(post_env["antiCheatActive"], false);
        assert_eq!(post_env["antiCheatMode"], "OFF");

        let (ok_unlocked, ac_after, _, updated) =
            apply_focus_filters_update(disable_attempt.as_object().unwrap());
        assert!(ok_unlocked);
        assert!(!ac_after);
        assert!(!updated.launcher_filter_enabled);
        assert!(updated.launcher_blocked_tags.is_empty());
        assert!(updated.launcher_blocked_names.is_empty());

        // Debug disable also unlocks Nuke mode immediately
        let mut re_filters = db::FocusFilters::default();
        re_filters.launcher_filter_enabled = true;
        re_filters.launcher_blocked_tags = vec!["RPG".to_string()];
        db::set_focus_filters(&re_filters);
        engine::enable_anti_cheat("NUKE", Some(600)).expect("enable nuke");
        assert_eq!(build_focus_filters_envelope(&db::get_focus_filters())["antiCheatActive"], true);
        engine::debug_disable_anti_cheat().expect("debug disable");
        let after_debug = build_focus_filters_envelope(&db::get_focus_filters());
        assert_eq!(after_debug["antiCheatActive"], false);
        assert_eq!(after_debug["antiCheatMode"], "OFF");

        let _ = std::fs::remove_file(db_file);
    }

    #[test]
    fn test_launchers_resolve_dom_learned_search_query_and_source_labels() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db_file = format!("/tmp/chronos_local_api_resolve_{}.db", std::process::id());
        let _ = std::fs::remove_file(&db_file);
        db::init_db(&db_file).expect("init temp db");

        let mut filters = db::FocusFilters::default();
        filters.launcher_filter_enabled = true;
        filters.launcher_blocked_tags = vec!["Roguelike".to_string()];
        filters.launcher_blocked_names = vec!["Forbidden".to_string()];
        db::set_focus_filters(&filters);

        // Seed an external GOG cached title (no Steam appId) to test cache resolution + label
        steam_api::save_cached_metadata(
            &format!("title:{}", steam_api::normalize_match_text("Cached GOG Roguelike")),
            &steam_api::GameMetadata {
                app_id: None,
                title: "Cached GOG Roguelike".to_string(),
                tags: vec!["Roguelike".to_string()],
                genres: vec!["Indie".to_string()],
                categories: Vec::new(),
                source: "gog".to_string(),
            },
        );

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        rt.block_on(async {
            // 1. Single-game page learns DOM tags into SQLite, search query resolves, cached GOG resolves with "GOG"
            let payload = serde_json::json!({
                "items": [
                    {
                        "id": "page-1",
                        "title": "Itch Secret Game",
                        "url": "https://indie.itch.io/itch-secret-game",
                        "siteTags": ["Roguelike"],
                        "isSingleGamePage": true
                    },
                    {
                        "id": "cached-gog",
                        "title": "Cached GOG Roguelike",
                        "url": "https://www.gog.com/en/game/cached_gog_roguelike",
                        "siteTags": []
                    },
                    {
                        "id": "search-1",
                        "title": "",
                        "url": "https://store.epicgames.com/en-US/browse?q=Forbidden",
                        "siteTags": []
                    }
                ]
            })
            .to_string();

            let resp_json = handle_launchers_resolve_payload(payload.as_bytes()).await.unwrap();
            assert_eq!(resp_json["success"], true);
            let res = resp_json["results"].as_array().unwrap();
            assert_eq!(res.len(), 3);
            assert_eq!(res[0]["blocked"], true);
            assert_eq!(res[1]["blocked"], true);
            assert!(res[1]["reason"].as_str().unwrap().contains("(GOG)"));
            assert_eq!(res[2]["blocked"], true);

            // 2. Subsequent search card with empty siteTags must match learned DOM tags from SQLite
            let card_payload = serde_json::json!({
                "items": [
                    {
                        "id": "card-1",
                        "title": "Itch Secret Game",
                        "url": "https://itch.io/games",
                        "siteTags": []
                    }
                ]
            })
            .to_string();
            let card_json = handle_launchers_resolve_payload(card_payload.as_bytes()).await.unwrap();
            let card_res = &card_json["results"].as_array().unwrap()[0];
            assert_eq!(card_res["blocked"], true);
            assert!(card_res["reason"].as_str().unwrap().contains("(Página)"));
        });

        let _ = std::fs::remove_file(db_file);
    }
}
