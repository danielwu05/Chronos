//! YouTube content-type classification and whitelist exemptions.
//!
//! A video is classified from YouTube's public player endpoint
//! (`POST /youtubei/v1/player`, ~11 KB, no API key) into Chronos types
//! (`educacional`, `ciencia_tecnologia`, `tutoriais`, `musica`, `podcasts`).
//! Results are cached in SQLite (`yt_video_meta`, `yt_playlist_meta`).
//! Whitelist groups may list `"yt_types"` so watching those types does not
//! consume rule quotas (optionally up to a daily cap); that time is logged in
//! `yt_exempt_intervals` instead.

use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use parking_lot::Mutex;

use crate::{db, steam_api};

pub const TYPE_EDUCATIONAL: &str = "educacional";
pub const TYPE_SCIENCE_TECH: &str = "ciencia_tecnologia";
pub const TYPE_HOWTO: &str = "tutoriais";
pub const TYPE_MUSIC: &str = "musica";
pub const TYPE_PODCAST: &str = "podcasts";

/// Built-in types shown in the UI: (id, label).
pub const BUILTIN_TYPES: [(&str, &str); 5] = [
    (TYPE_EDUCATIONAL, "Educacional"),
    (TYPE_SCIENCE_TECH, "Ciência e Tecnologia"),
    (TYPE_HOWTO, "Tutoriais"),
    (TYPE_MUSIC, "Música"),
    (TYPE_PODCAST, "Podcasts"),
];

const DEFAULT_CLIENT_VERSION: &str = "2.20261116.00.00";
const VIDEO_META_TTL_SECONDS: i64 = 30 * 86400;
const PLAYLIST_META_TTL_SECONDS: i64 = 7 * 86400;
const MISS_RETRY_SECONDS: i64 = 120;
const ACTIVE_TAB_FILE: &str = "/tmp/chronos_active_tab.json";

fn now_utc() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

/// A YouTube page reference parsed from a URL.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct YtRef {
    pub video_id: String,
    pub list_id: Option<String>,
    pub is_music_host: bool,
    pub is_shorts: bool,
}

fn is_valid_video_id(id: &str) -> bool {
    id.len() == 11 && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

/// Parses `youtube.com/watch?v=`, `/shorts/ID`, `/embed/ID`, `/live/ID`,
/// `youtu.be/ID` and `music.youtube.com/watch?v=` (case of the ID preserved).
pub fn parse_youtube_url(url: &str) -> Option<YtRef> {
    let rest = url
        .trim()
        .strip_prefix("https://")
        .or_else(|| url.trim().strip_prefix("http://"))
        .unwrap_or(url.trim());
    let (host, path_q) = rest.split_once('/').unwrap_or((rest, ""));
    let host = host.to_ascii_lowercase();
    let host = host.split(':').next().unwrap_or("");
    let is_short_link = host == "youtu.be";
    let is_yt = is_short_link
        || host == "youtube.com"
        || host.ends_with(".youtube.com");
    if !is_yt {
        return None;
    }
    let (path, query) = path_q.split_once('?').unwrap_or((path_q, ""));
    let query = query.split('#').next().unwrap_or("");
    let q_get = |key: &str| -> Option<String> {
        query.split('&').find_map(|pair| {
            let (k, v) = pair.split_once('=')?;
            (k == key && !v.is_empty()).then(|| v.to_string())
        })
    };
    let segs: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();

    let mut is_shorts = false;
    let video_id = if is_short_link {
        segs.first().map(|s| s.to_string())
    } else if segs.first().is_some_and(|s| *s == "watch") {
        q_get("v")
    } else if let [kind, id, ..] = segs.as_slice() {
        if matches!(*kind, "shorts" | "embed" | "live" | "v") {
            is_shorts = *kind == "shorts";
            Some(id.to_string())
        } else {
            None
        }
    } else {
        None
    }?;
    if !is_valid_video_id(&video_id) {
        return None;
    }
    Some(YtRef {
        video_id,
        list_id: q_get("list").filter(|l| l.len() >= 10 && !l.starts_with("RD")),
        is_music_host: host == "music.youtube.com",
        is_shorts,
    })
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct YtVideoMeta {
    pub video_id: String,
    pub category: String,
    pub channel_id: String,
    pub channel: String,
    pub keywords: Vec<String>,
    pub title: String,
}

/// User rule that assigns a type (built-in like `podcasts`, or a new custom one)
/// to videos from given channels or whose title/keywords contain given terms.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct YtCustomRule {
    pub type_id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub channels: Vec<String>,
    #[serde(default)]
    pub keywords: Vec<String>,
}

const CUSTOM_RULES_KEY: &str = "yt_custom_rules";

pub fn custom_rules() -> Vec<YtCustomRule> {
    db::try_get_conn()
        .and_then(|_| db::get_config(CUSTOM_RULES_KEY))
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default()
}

/// Normalizes and stores custom rules. While anti-cheat is active, only removals are
/// allowed (adding channels/keywords could widen what is exempt or shown).
pub fn save_custom_rules(rules: Vec<YtCustomRule>, anti_cheat_active: bool) -> Result<(), String> {
    let clean_list = |v: &[String]| -> Vec<String> {
        let mut out: Vec<String> = Vec::new();
        for s in v {
            let t = s.trim().to_string();
            if !t.is_empty() && !out.iter().any(|o| o.eq_ignore_ascii_case(&t)) {
                out.push(t);
            }
        }
        out
    };
    let next: Vec<YtCustomRule> = rules
        .into_iter()
        .filter_map(|r| {
            let type_id = r.type_id.trim().to_lowercase();
            if type_id.is_empty() {
                return None;
            }
            let channels = clean_list(&r.channels);
            let keywords = clean_list(&r.keywords);
            (!channels.is_empty() || !keywords.is_empty()).then(|| YtCustomRule {
                name: if r.name.trim().is_empty() { type_label(&type_id) } else { r.name.trim().to_string() },
                type_id,
                channels,
                keywords,
            })
        })
        .collect();
    if anti_cheat_active {
        let current = custom_rules();
        for r in &next {
            let old = current.iter().find(|c| c.type_id == r.type_id);
            let norm = |s: &str| fold(s.trim().trim_start_matches('@'));
            let had = |list: Option<&Vec<String>>, v: &String| {
                list.is_some_and(|l| l.iter().any(|x| norm(x) == norm(v)))
            };
            let added = r.channels.iter().any(|c| !had(old.map(|o| &o.channels), c))
                || r.keywords.iter().any(|k| !had(old.map(|o| &o.keywords), k));
            if added {
                return Err(format!(
                    "Modo Anti-Burla está ativo! Adicionar canais ou palavras ao tipo '{}' exige desativar o Anti-Burla.",
                    r.name
                ));
            }
        }
    }
    let raw = serde_json::to_string(&next).map_err(|e| e.to_string())?;
    db::set_config(CUSTOM_RULES_KEY, &raw).map_err(|e| e.to_string())?;
    let _ = db::bump_state_revision();
    Ok(())
}

fn fold(s: &str) -> String {
    crate::steam_api::normalize_match_text(s)
}

fn custom_rule_matches(rule: &YtCustomRule, meta: &YtVideoMeta) -> bool {
    let channel = fold(&meta.channel);
    let channel_id = meta.channel_id.to_lowercase();
    if rule.channels.iter().any(|c| {
        let c_f = fold(c.trim_start_matches('@'));
        !c_f.is_empty() && (c_f == channel || c.to_lowercase() == channel_id)
    }) {
        return true;
    }
    let title = fold(&meta.title);
    let kws: Vec<String> = meta.keywords.iter().map(|k| fold(k)).collect();
    rule.keywords.iter().any(|k| {
        let k_f = fold(k);
        !k_f.is_empty() && (title.contains(&k_f) || kws.iter().any(|x| x.contains(&k_f)))
    })
}

/// Extracts category/channel/keywords from a `youtubei/v1/player` JSON response.
pub fn parse_player_response(video_id: &str, body: &[u8]) -> Option<YtVideoMeta> {
    let v: serde_json::Value = serde_json::from_slice(body).ok()?;
    let micro = v.pointer("/microformat/playerMicroformatRenderer");
    let details = v.get("videoDetails");
    let category = micro
        .and_then(|m| m.get("category"))
        .and_then(|c| c.as_str())
        .unwrap_or("")
        .to_string();
    if category.is_empty() {
        return None;
    }
    let s = |val: Option<&serde_json::Value>, key: &str| -> String {
        val.and_then(|d| d.get(key))
            .and_then(|x| x.as_str())
            .unwrap_or("")
            .to_string()
    };
    let channel_id = {
        let c = s(details, "channelId");
        if c.is_empty() { s(micro, "externalChannelId") } else { c }
    };
    let channel = {
        let c = s(details, "author");
        if c.is_empty() { s(micro, "ownerChannelName") } else { c }
    };
    let keywords = details
        .and_then(|d| d.get("keywords"))
        .and_then(|k| k.as_array())
        .map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_string)).take(40).collect())
        .unwrap_or_default();
    Some(YtVideoMeta {
        video_id: video_id.to_string(),
        category,
        channel_id,
        channel,
        keywords,
        title: s(details, "title"),
    })
}

/// True when a playlist page is a YouTube podcast show.
pub fn parse_playlist_is_podcast(html: &[u8]) -> bool {
    let text = String::from_utf8_lossy(html);
    text.contains("\"key\":\"is_podcast_show_page\",\"value\":\"1\"")
        || text.contains("\"label\":\"Podcast\",\"tooltip\":\"Podcast\"")
}

/// Maps a classified video to Chronos types (built-in rules + the user's custom rules).
pub fn types_for(meta: &YtVideoMeta, yt: &YtRef, playlist_is_podcast: bool) -> Vec<String> {
    types_for_with(meta, yt, playlist_is_podcast, &custom_rules())
}

pub fn types_for_with(
    meta: &YtVideoMeta,
    yt: &YtRef,
    playlist_is_podcast: bool,
    custom: &[YtCustomRule],
) -> Vec<String> {
    let mut out = builtin_types_for(meta, yt, playlist_is_podcast);
    for rule in custom {
        if !out.contains(&rule.type_id) && custom_rule_matches(rule, meta) {
            out.push(rule.type_id.clone());
        }
    }
    out
}

fn builtin_types_for(meta: &YtVideoMeta, yt: &YtRef, playlist_is_podcast: bool) -> Vec<String> {
    let mut out = Vec::new();
    match meta.category.as_str() {
        "Education" => out.push(TYPE_EDUCATIONAL),
        "Science & Technology" => out.push(TYPE_SCIENCE_TECH),
        "Howto & Style" => out.push(TYPE_HOWTO),
        "Music" => out.push(TYPE_MUSIC),
        _ => {}
    }
    if yt.is_music_host && !out.contains(&TYPE_MUSIC) && !playlist_is_podcast {
        out.push(TYPE_MUSIC);
    }
    if playlist_is_podcast {
        out.push(TYPE_PODCAST);
    }
    out.into_iter().map(str::to_string).collect()
}

// ---------------------------------------------------------------------------
// Cache (SQLite)

pub fn load_cached_video(video_id: &str) -> Option<YtVideoMeta> {
    let conn = db::try_get_conn()?.lock();
    conn.query_row(
        "SELECT category, channel_id, channel, keywords_json, fetched_at_utc, COALESCE(title, '') FROM yt_video_meta WHERE video_id = ?1",
        [video_id],
        |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, i64>(4)?,
                r.get::<_, String>(5)?,
            ))
        },
    )
    .ok()
    .filter(|(_, _, _, _, at, _)| now_utc() - at < VIDEO_META_TTL_SECONDS)
    .map(|(category, channel_id, channel, kw, _, title)| YtVideoMeta {
        video_id: video_id.to_string(),
        category,
        channel_id,
        channel,
        keywords: serde_json::from_str(&kw).unwrap_or_default(),
        title,
    })
}

pub fn save_cached_video(meta: &YtVideoMeta) {
    if let Some(c) = db::try_get_conn() {
        let conn = c.lock();
        let _ = conn.execute(
            "INSERT OR REPLACE INTO yt_video_meta (video_id, category, channel_id, channel, keywords_json, fetched_at_utc, title)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            (
                &meta.video_id,
                &meta.category,
                &meta.channel_id,
                &meta.channel,
                serde_json::to_string(&meta.keywords).unwrap_or_else(|_| "[]".into()),
                now_utc(),
                &meta.title,
            ),
        );
    }
}

fn load_cached_playlist(list_id: &str) -> Option<bool> {
    let conn = db::try_get_conn()?.lock();
    conn.query_row(
        "SELECT is_podcast, fetched_at_utc FROM yt_playlist_meta WHERE list_id = ?1",
        [list_id],
        |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?)),
    )
    .ok()
    .filter(|(_, at)| now_utc() - at < PLAYLIST_META_TTL_SECONDS)
    .map(|(p, _)| p != 0)
}

fn save_cached_playlist(list_id: &str, is_podcast: bool) {
    if let Some(c) = db::try_get_conn() {
        let _ = c.lock().execute(
            "INSERT OR REPLACE INTO yt_playlist_meta (list_id, is_podcast, fetched_at_utc) VALUES (?1, ?2, ?3)",
            (list_id, is_podcast as i64, now_utc()),
        );
    }
}

// ---------------------------------------------------------------------------
// Network

fn youtube_base() -> String {
    std::env::var("CHRONOS_YOUTUBE_BASE").unwrap_or_else(|_| "https://www.youtube.com".to_string())
}

fn client_version() -> String {
    db::try_get_conn()
        .and_then(|_| db::get_config("yt_client_version"))
        .filter(|v| !v.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_CLIENT_VERSION.to_string())
}

async fn refresh_client_version() -> Option<String> {
    let html = steam_api::http_request(
        "GET",
        &format!("{}/", youtube_base()),
        &[("Accept-Language", "en-US")],
        None,
    )
    .await
    .ok()?;
    let text = String::from_utf8_lossy(&html);
    let key = "\"INNERTUBE_CLIENT_VERSION\":\"";
    let start = text.find(key)? + key.len();
    let ver: String = text[start..].chars().take_while(|c| *c != '"').collect();
    if ver.is_empty() {
        return None;
    }
    if db::try_get_conn().is_some() {
        let _ = db::set_config("yt_client_version", &ver);
    }
    Some(ver)
}

async fn fetch_player(video_id: &str, version: &str) -> Result<Vec<u8>, String> {
    let body = serde_json::json!({
        "videoId": video_id,
        "context": {"client": {"clientName": "WEB", "clientVersion": version, "hl": "en", "gl": "US"}}
    })
    .to_string();
    tokio::time::timeout(
        std::time::Duration::from_secs(4),
        steam_api::http_request(
            "POST",
            &format!("{}/youtubei/v1/player?prettyPrint=false", youtube_base()),
            &[("Content-Type", "application/json")],
            Some(body.as_bytes()),
        ),
    )
    .await
    .map_err(|_| "timeout".to_string())?
}

/// Classifies a video via the network (cache-aware). `None` when unknown/offline.
pub async fn fetch_video_meta(video_id: &str) -> Option<YtVideoMeta> {
    if let Some(m) = load_cached_video(video_id) {
        return Some(m);
    }
    let body = match fetch_player(video_id, &client_version()).await {
        Ok(b) => b,
        Err(_) => {
            let fresh = refresh_client_version().await?;
            fetch_player(video_id, &fresh).await.ok()?
        }
    };
    let meta = parse_player_response(video_id, &body)?;
    save_cached_video(&meta);
    Some(meta)
}

pub async fn fetch_playlist_is_podcast(list_id: &str) -> Option<bool> {
    if let Some(p) = load_cached_playlist(list_id) {
        return Some(p);
    }
    let html = tokio::time::timeout(
        std::time::Duration::from_secs(6),
        steam_api::http_request(
            "GET",
            &format!("{}/playlist?list={list_id}", youtube_base()),
            &[("Accept-Language", "en-US")],
            None,
        ),
    )
    .await
    .ok()?
    .ok()?;
    let is_podcast = parse_playlist_is_podcast(&html);
    save_cached_playlist(list_id, is_podcast);
    Some(is_podcast)
}

/// Full async classification of a parsed reference.
pub async fn classify(yt: &YtRef) -> Option<Vec<String>> {
    let meta = fetch_video_meta(&yt.video_id).await?;
    let podcast = match &yt.list_id {
        Some(l) => fetch_playlist_is_podcast(l).await.unwrap_or(false),
        None => false,
    };
    Some(types_for(&meta, yt, podcast))
}

/// For async request paths (block checks): when the URL is a YouTube video that is not
/// classified yet and the whitelist has YouTube types, wait up to 2s for classification so
/// an exempt video is not shown the block page on its first visit.
pub async fn warm_classification(url: &str) {
    let Some(yt) = parse_youtube_url(url) else {
        return;
    };
    if load_cached_video(&yt.video_id).is_some()
        && yt.list_id.as_deref().map_or(true, |l| load_cached_playlist(l).is_some())
    {
        return;
    }
    if whitelist_exemptions().is_empty() {
        return;
    }
    let _ = tokio::time::timeout(std::time::Duration::from_secs(2), classify(&yt)).await;
}

/// Batch classification for feed cards: `{"items":[{"id":"c1","videoId":"…"}]}` →
/// `{"results":[{"id":"c1","types":["musica"],"known":true}]}`.
/// Cached videos answer immediately; up to 4 lookups run concurrently within ~5s.
/// Unknown videos (`known:false`) are hidden by "mostrar apenas" until classified.
pub async fn handle_classify_payload(body: &[u8]) -> serde_json::Value {
    let parsed: serde_json::Value = serde_json::from_slice(body).unwrap_or_default();
    let items: Vec<(String, YtRef)> = parsed
        .get("items")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .take(80)
                .filter_map(|it| {
                    let id = it.get("id").and_then(|v| v.as_str())?.to_string();
                    let vid = it.get("videoId").and_then(|v| v.as_str())?;
                    is_valid_video_id(vid).then(|| {
                        (id, YtRef { video_id: vid.to_string(), ..Default::default() })
                    })
                })
                .collect()
        })
        .unwrap_or_default();

    let custom = custom_rules();
    let mut results: HashMap<String, Option<Vec<String>>> = HashMap::new();
    let mut to_fetch: Vec<(String, YtRef)> = Vec::new();
    for (id, yt) in items.iter().cloned() {
        match load_cached_video(&yt.video_id) {
            Some(meta) => {
                results.insert(id, Some(types_for_with(&meta, &yt, false, &custom)));
            }
            None => to_fetch.push((id, yt)),
        }
    }

    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(5);
    let mut set = tokio::task::JoinSet::new();
    let mut queue = to_fetch.into_iter();
    for _ in 0..4 {
        if let Some((id, yt)) = queue.next() {
            set.spawn(async move { (id, fetch_video_meta(&yt.video_id).await, yt) });
        }
    }
    loop {
        let Ok(next) = tokio::time::timeout_at(deadline, set.join_next()).await else {
            // Out of budget: remaining lookups keep warming the cache in the background.
            set.detach_all();
            break;
        };
        let Some(joined) = next else { break };
        if let Ok((id, meta, yt)) = joined {
            results.insert(id, meta.map(|m| types_for_with(&m, &yt, false, &custom)));
        }
        if let Some((id, yt)) = queue.next() {
            set.spawn(async move { (id, fetch_video_meta(&yt.video_id).await, yt) });
        }
    }
    for (id, yt) in queue {
        // Not started within budget: warm the cache for the next scan.
        let _ = id;
        tokio::spawn(async move {
            let _ = fetch_video_meta(&yt.video_id).await;
        });
    }

    let out: Vec<serde_json::Value> = items
        .iter()
        .map(|(id, _)| match results.get(id) {
            Some(Some(types)) => serde_json::json!({"id": id, "types": types, "known": true}),
            _ => serde_json::json!({"id": id, "types": [], "known": false}),
        })
        .collect();
    serde_json::json!({"success": true, "results": out})
}

static PENDING: Mutex<Option<HashMap<String, i64>>> = Mutex::new(None);

/// Non-blocking classification for the 1 Hz engine tick: returns cached types,
/// otherwise schedules a background lookup and returns `None` (time counts normally).
pub fn classify_cached_or_spawn(yt: &YtRef) -> Option<Vec<String>> {
    if let Some(meta) = load_cached_video(&yt.video_id) {
        match &yt.list_id {
            None => return Some(types_for(&meta, yt, false)),
            Some(l) => {
                if let Some(p) = load_cached_playlist(l) {
                    return Some(types_for(&meta, yt, p));
                }
            }
        }
    }
    let key = format!("{}|{}", yt.video_id, yt.list_id.clone().unwrap_or_default());
    {
        let mut guard = PENDING.lock();
        let map = guard.get_or_insert_with(HashMap::new);
        let now = now_utc();
        if map.get(&key).is_some_and(|t| now - t < MISS_RETRY_SECONDS) {
            return None;
        }
        if map.len() > 500 {
            map.retain(|_, t| now - *t < MISS_RETRY_SECONDS);
        }
        map.insert(key, now);
    }
    let yt = yt.clone();
    std::thread::spawn(move || {
        let _ = steam_api::run_async_blocking(async move { classify(&yt).await });
    });
    None
}

// ---------------------------------------------------------------------------
// Whitelist exemptions

/// `type -> optional daily cap (seconds)` from all whitelist groups' `"yt_types"`.
/// Accepts `["educacional"]` or `[{"type":"educacional","cap_minutes":180}]`.
pub fn whitelist_exemptions() -> HashMap<String, Option<i64>> {
    parse_exemptions(&db::get_all_whitelist_groups())
}

pub fn parse_exemptions(groups: &[db::WhitelistGroupItem]) -> HashMap<String, Option<i64>> {
    let mut out: HashMap<String, Option<i64>> = HashMap::new();
    for g in groups {
        let raw = g.items.trim();
        if !raw.starts_with('{') {
            continue;
        }
        let Ok(v) = serde_json::from_str::<serde_json::Value>(raw) else {
            continue;
        };
        let Some(arr) = v.get("yt_types").and_then(|x| x.as_array()) else {
            continue;
        };
        for item in arr {
            let (ty, cap) = if let Some(s) = item.as_str() {
                (s.to_string(), None)
            } else {
                let ty = item.get("type").and_then(|t| t.as_str()).unwrap_or("").to_string();
                let cap = item
                    .get("cap_minutes")
                    .and_then(|c| c.as_i64())
                    .filter(|m| *m > 0)
                    .map(|m| m * 60);
                (ty, cap)
            };
            let ty = ty.trim().to_lowercase();
            if ty.is_empty() {
                continue;
            }
            // Several groups listing the same type: the most generous cap wins (None = no cap).
            out.entry(ty)
                .and_modify(|existing| {
                    *existing = match (*existing, cap) {
                        (None, _) | (_, None) => None,
                        (Some(a), Some(b)) => Some(a.max(b)),
                    }
                })
                .or_insert(cap);
        }
    }
    out
}

fn day_start(now: i64) -> i64 {
    now - (now % 86400)
}

pub fn exempt_seconds_today(yt_type: &str) -> i64 {
    let Some(c) = db::try_get_conn() else {
        return 0;
    };
    c.lock()
        .query_row(
            "SELECT COALESCE(SUM(ended_at_utc - started_at_utc), 0) FROM yt_exempt_intervals
             WHERE yt_type = ?1 AND started_at_utc >= ?2",
            (yt_type, day_start(now_utc())),
            |r| r.get(0),
        )
        .unwrap_or(0)
}

/// Picks the first whitelisted type of the video that is still under its cap.
pub fn pick_exempt_type(
    video_types: &[String],
    exemptions: &HashMap<String, Option<i64>>,
    used_today: impl Fn(&str) -> i64,
) -> Option<String> {
    video_types.iter().find_map(|t| {
        let cap = exemptions.get(t)?;
        match cap {
            Some(limit) if used_today(t) >= *limit => None,
            _ => Some(t.clone()),
        }
    })
}

/// Current YouTube page of the focused browser tab (`foreground`) or the audible tab.
pub fn active_tab_refs() -> (Option<YtRef>, Option<YtRef>) {
    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64;
    let Ok(content) = std::fs::read_to_string(ACTIVE_TAB_FILE) else {
        return (None, None);
    };
    let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) else {
        return (None, None);
    };
    let ts = json.get("timestamp_ms").and_then(|v| v.as_i64()).unwrap_or(0);
    // The audible tab is tracked with its own timestamp (merged by the local API).
    let audible_ts = json.get("audible_timestamp_ms").and_then(|v| v.as_i64()).unwrap_or(ts);
    let get = |k: &str| json.get(k).and_then(|v| v.as_str()).and_then(parse_youtube_url);
    let fg = ((now_ms - ts).abs() <= ACTIVE_TAB_FRESH_MS).then(|| get("url")).flatten();
    let audible = ((now_ms - audible_ts).abs() <= AUDIBLE_TAB_FRESH_MS).then(|| get("audible_url")).flatten();
    (fg, audible)
}

/// How long the reported focused tab stays valid (reports arrive every ~1.5s).
pub const ACTIVE_TAB_FRESH_MS: i64 = 6000;
/// How long the reported audible tab stays valid.
pub const AUDIBLE_TAB_FRESH_MS: i64 = 10000;

/// Decides whether this tick's activity is exempt because the YouTube content involved
/// is of a whitelisted type.
/// - `fg`: YouTube video in the focused browser tab (only when the focused window is a browser);
/// - `audible`: YouTube video in the tab currently playing audio.
///
/// Applies only when the activity is YouTube-related (`yt_related`) or came from the
/// focused browser. Exempt when at least one video is present and **all** present videos
/// are exempt (a non-exempt video playing alongside keeps counting). Returns the type to log.
pub fn exemption_decision(
    yt_related: bool,
    from_focused_browser: bool,
    fg: Option<&YtRef>,
    audible: Option<&YtRef>,
    exempt_of: impl Fn(&YtRef) -> Option<String>,
) -> Option<String> {
    if !yt_related && !from_focused_browser {
        return None;
    }
    let mut present: Vec<&YtRef> = Vec::new();
    if let Some(f) = fg {
        present.push(f);
    }
    if let Some(a) = audible {
        if fg.map_or(true, |f| f.video_id != a.video_id) {
            present.push(a);
        }
    }
    // A non-YouTube rule active through the focused browser only cares about that tab.
    if !yt_related {
        present.retain(|r| fg.is_some_and(|f| f.video_id == r.video_id));
    }
    if present.is_empty() {
        return None;
    }
    let mut chosen = None;
    for r in present {
        let t = exempt_of(r)?;
        chosen.get_or_insert(t);
    }
    chosen
}

/// Live version of [`exemption_decision`] using the reported tabs and the whitelist.
pub fn current_exemption(yt_related: bool, browser_focused: bool, from_focused_browser: bool) -> Option<String> {
    if whitelist_exemptions().is_empty() {
        return None;
    }
    let (fg, audible) = active_tab_refs();
    let fg = if browser_focused { fg } else { None };
    exemption_decision(yt_related, from_focused_browser, fg.as_ref(), audible.as_ref(), exempt_type_for)
}

/// True when a rule (by pattern / name / id) targets YouTube.
pub fn rule_is_youtube_related(entity_id: &str, display_name: &str, pattern: &str) -> bool {
    [entity_id, display_name, pattern]
        .iter()
        .any(|s| s.to_lowercase().contains("youtu"))
}

/// Exempt type for a YouTube reference given the current whitelist, or `None`.
pub fn exempt_type_for(yt: &YtRef) -> Option<String> {
    let exemptions = whitelist_exemptions();
    if exemptions.is_empty() {
        return None;
    }
    let types = classify_cached_or_spawn(yt)?;
    pick_exempt_type(&types, &exemptions, exempt_seconds_today)
}

static LAST_EXEMPT_SECOND: AtomicI64 = AtomicI64::new(0);

/// Logs one exempt second for `yt_type` (deduplicated across entities ticking the same second).
pub fn record_exempt_second(yt_type: &str) {
    let now = now_utc();
    if LAST_EXEMPT_SECOND.swap(now, Ordering::SeqCst) == now {
        return;
    }
    let Some(c) = db::try_get_conn() else {
        return;
    };
    let conn = c.lock();
    let active: Option<String> = conn
        .query_row(
            "SELECT interval_id FROM yt_exempt_intervals WHERE yt_type = ?1 AND ended_at_utc >= ?2
             ORDER BY ended_at_utc DESC LIMIT 1",
            (yt_type, now - 3),
            |r| r.get(0),
        )
        .ok();
    if let Some(id) = active {
        let _ = conn.execute("UPDATE yt_exempt_intervals SET ended_at_utc = ?1 WHERE interval_id = ?2", (now, id));
    } else {
        let _ = conn.execute(
            "INSERT INTO yt_exempt_intervals (interval_id, yt_type, started_at_utc, ended_at_utc) VALUES (?1, ?2, ?3, ?4)",
            (format!("yt_{yt_type}_{now}"), yt_type, now - 1, now),
        );
    }
}

/// Exempt seconds per type over the last `days` days (for analytics).
pub fn exempt_totals_since(since_utc: i64) -> Vec<(String, i64)> {
    let Some(c) = db::try_get_conn() else {
        return Vec::new();
    };
    let conn = c.lock();
    let Ok(mut st) = conn.prepare(
        "SELECT yt_type, COALESCE(SUM(ended_at_utc - started_at_utc), 0) FROM yt_exempt_intervals
         WHERE started_at_utc >= ?1 GROUP BY yt_type ORDER BY 2 DESC",
    ) else {
        return Vec::new();
    };
    st.query_map([since_utc], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))
        .map(|rows| rows.flatten().collect())
        .unwrap_or_default()
}

pub fn type_label(id: &str) -> String {
    if let Some((_, l)) = BUILTIN_TYPES.iter().find(|(t, _)| *t == id) {
        return l.to_string();
    }
    custom_rules()
        .into_iter()
        .find(|r| r.type_id == id && !r.name.is_empty())
        .map(|r| r.name)
        .unwrap_or_else(|| id.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_youtube_urls_and_types() {
        let w = parse_youtube_url("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLWM-D0VS9_EwRhOjdqSgqY-WNyV5rDpHb&t=3").unwrap();
        assert_eq!(w.video_id, "dQw4w9WgXcQ");
        assert_eq!(w.list_id.as_deref(), Some("PLWM-D0VS9_EwRhOjdqSgqY-WNyV5rDpHb"));
        assert!(!w.is_shorts && !w.is_music_host);
        assert!(parse_youtube_url("https://youtube.com/shorts/AbC_def-123").unwrap().is_shorts);
        assert_eq!(parse_youtube_url("https://youtu.be/AbC_def-123?si=x").unwrap().video_id, "AbC_def-123");
        assert!(parse_youtube_url("https://music.youtube.com/watch?v=AbC_def-123").unwrap().is_music_host);
        // Radio/mix lists are not podcasts
        assert!(parse_youtube_url("https://www.youtube.com/watch?v=AbC_def-123&list=RDAbC_def-123").unwrap().list_id.is_none());
        assert!(parse_youtube_url("https://www.youtube.com/").is_none());
        assert!(parse_youtube_url("https://www.youtube.com/results?search_query=x").is_none());
        assert!(parse_youtube_url("https://example.com/watch?v=AbC_def-123").is_none());
        assert!(parse_youtube_url("https://www.youtube.com/watch?v=short").is_none());

        let body = br#"{"videoDetails":{"channelId":"UC1","author":"Rick","keywords":["a","b"]},
            "microformat":{"playerMicroformatRenderer":{"category":"Music"}}}"#;
        let meta = parse_player_response("dQw4w9WgXcQ", body).unwrap();
        assert_eq!(meta.category, "Music");
        assert_eq!(meta.channel, "Rick");
        assert_eq!(meta.keywords, vec!["a", "b"]);
        assert!(parse_player_response("x", br#"{"playabilityStatus":{}}"#).is_none());

        assert_eq!(types_for(&meta, &w, false), vec!["musica"]);
        let edu = YtVideoMeta { category: "Education".into(), ..Default::default() };
        assert_eq!(types_for(&edu, &w, true), vec!["educacional", "podcasts"]);
        let news = YtVideoMeta { category: "News & Politics".into(), ..Default::default() };
        let music_host = YtRef { is_music_host: true, ..Default::default() };
        assert_eq!(types_for(&news, &music_host, false), vec!["musica"]);
        assert!(types_for(&news, &YtRef::default(), false).is_empty());

        assert!(parse_playlist_is_podcast(br#"x{"key":"is_podcast_show_page","value":"1"}y"#));
        assert!(!parse_playlist_is_podcast(b"<html>regular playlist</html>"));
    }

    /// Live network check (not run in CI): `cargo test --lib youtube_live -- --ignored`.
    #[test]
    #[ignore]
    fn youtube_live_classification() {
        steam_api::run_async_blocking(async {
            let music = parse_youtube_url("https://www.youtube.com/watch?v=dQw4w9WgXcQ").unwrap();
            assert_eq!(classify(&music).await, Some(vec!["musica".to_string()]));
            let pod = parse_youtube_url(
                "https://www.youtube.com/watch?v=e1jTdPTvu1E&list=PLWM-D0VS9_EwRhOjdqSgqY-WNyV5rDpHb",
            )
            .unwrap();
            assert_eq!(classify(&pod).await, Some(vec!["podcasts".to_string()]));
        });
    }

    #[test]
    fn test_exempt_video_bypasses_block_and_logs_exempt_time() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db_file = format!("/tmp/chronos_yt_exempt_{}.db", std::process::id());
        let _ = std::fs::remove_file(&db_file);
        db::init_db(&db_file).expect("init temp db");

        let edu_url = "https://www.youtube.com/watch?v=EduVid12345";
        let fun_url = "https://www.youtube.com/watch?v=FunVid12345";
        save_cached_video(&YtVideoMeta { video_id: "EduVid12345".into(), category: "Education".into(), ..Default::default() });
        save_cached_video(&YtVideoMeta { video_id: "FunVid12345".into(), category: "Gaming".into(), ..Default::default() });

        // No YouTube types whitelisted yet -> nothing exempt
        assert!(!crate::proxy::is_whitelisted_target(edu_url, ""));

        db::save_whitelist_group(
            "wl_yt",
            "YouTube estudo",
            r#"{"apps":[],"sites":[],"yt_types":[{"type":"educacional","cap_minutes":1}]}"#,
        )
        .unwrap();
        assert!(crate::proxy::is_whitelisted_target(edu_url, ""), "educational video stays reachable");
        assert!(!crate::proxy::is_whitelisted_target(fun_url, ""), "other types still follow the rule");
        assert_eq!(exempt_type_for(&parse_youtube_url(edu_url).unwrap()).as_deref(), Some("educacional"));

        record_exempt_second("educacional");
        assert_eq!(exempt_seconds_today("educacional"), 1);
        assert_eq!(exempt_totals_since(0), vec![("educacional".to_string(), 1)]);

        // Cap reached (1 minute) -> no longer exempt
        db::get_conn()
            .lock()
            .execute(
                "INSERT INTO yt_exempt_intervals (interval_id, yt_type, started_at_utc, ended_at_utc) VALUES ('x','educacional',?1,?2)",
                (now_utc() - 120, now_utc() - 60),
            )
            .unwrap();
        assert!(exempt_type_for(&parse_youtube_url(edu_url).unwrap()).is_none());
        assert!(!crate::proxy::is_whitelisted_target(edu_url, ""));

        let _ = std::fs::remove_file(db_file);
    }

    #[test]
    fn test_custom_rules_classify_batch_and_show_only_anti_cheat() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db_file = format!("/tmp/chronos_yt_custom_{}.db", std::process::id());
        let _ = std::fs::remove_file(&db_file);
        db::init_db(&db_file).expect("init temp db");

        save_cached_video(&YtVideoMeta {
            video_id: "PodEp123456".into(),
            category: "Entertainment".into(),
            channel: "Flow Podcast".into(),
            title: "Ep. 900".into(),
            ..Default::default()
        });
        save_cached_video(&YtVideoMeta {
            video_id: "Craft123456".into(),
            category: "Gaming".into(),
            channel: "Alguém".into(),
            title: "Construindo no Minecraft".into(),
            ..Default::default()
        });

        save_custom_rules(
            vec![
                YtCustomRule { type_id: "podcasts".into(), channels: vec!["@flow podcast".into()], ..Default::default() },
                YtCustomRule { type_id: "custom_minecraft".into(), name: "Minecraft".into(), keywords: vec!["minecraft".into()], ..Default::default() },
                YtCustomRule { type_id: "vazio".into(), ..Default::default() },
            ],
            false,
        )
        .unwrap();
        assert_eq!(custom_rules().len(), 2, "rules without channels/keywords are dropped");
        assert_eq!(type_label("custom_minecraft"), "Minecraft");

        let body = br#"{"items":[{"id":"a","videoId":"PodEp123456"},{"id":"b","videoId":"Craft123456"},{"id":"c","videoId":"bad"}]}"#;
        let out = steam_api::run_async_blocking(async { handle_classify_payload(body).await });
        let res = out["results"].as_array().unwrap();
        assert_eq!(res.len(), 2, "invalid ids are ignored");
        assert_eq!(res[0]["types"], serde_json::json!(["podcasts"]));
        assert_eq!(res[1]["types"], serde_json::json!(["custom_minecraft"]));
        assert_eq!(res[1]["known"], true);

        // Anti-cheat: removing is fine, adding a keyword is not
        assert!(save_custom_rules(
            vec![YtCustomRule { type_id: "podcasts".into(), channels: vec!["Flow Podcast".into()], ..Default::default() }],
            true
        )
        .is_ok());
        assert!(save_custom_rules(
            vec![YtCustomRule { type_id: "podcasts".into(), channels: vec!["Flow Podcast".into(), "Outro".into()], ..Default::default() }],
            true
        )
        .is_err());

        // "Mostrar apenas": cannot be turned off or widened under anti-cheat; narrowing is allowed
        let mut cur = db::FocusFilters::default();
        cur.yt_show_only_enabled = true;
        cur.yt_show_only_types = vec!["educacional".into(), "musica".into()];
        let mut off = cur.clone();
        off.yt_show_only_enabled = false;
        assert!(db::validate_focus_filters_anti_cheat(&cur, &off, true).is_err());
        let mut wider = cur.clone();
        wider.yt_show_only_types.push("podcasts".into());
        assert!(db::validate_focus_filters_anti_cheat(&cur, &wider, true).is_err());
        let mut narrower = cur.clone();
        narrower.yt_show_only_types = vec!["educacional".into()];
        assert!(db::validate_focus_filters_anti_cheat(&cur, &narrower, true).is_ok());
        assert!(db::validate_focus_filters_anti_cheat(&cur, &off, false).is_ok());

        // Empty list can never be enabled
        let mut empty = db::FocusFilters::default();
        empty.yt_show_only_enabled = true;
        empty.normalize_legacy();
        assert!(!empty.yt_show_only_enabled);

        let _ = std::fs::remove_file(db_file);
    }

    #[test]
    fn test_exemption_decision_all_paths() {
        let edu = YtRef { video_id: "EduVid12345".into(), ..Default::default() };
        let edu2 = YtRef { video_id: "EduVid99999".into(), ..Default::default() };
        let game = YtRef { video_id: "GameVid1234".into(), ..Default::default() };
        let exempt = |r: &YtRef| r.video_id.starts_with("Edu").then(|| "educacional".to_string());

        // YouTube rule matched by app/window/media: exempt when the only video is educational
        assert_eq!(exemption_decision(true, false, Some(&edu), None, exempt).as_deref(), Some("educacional"));
        assert_eq!(exemption_decision(true, false, None, Some(&edu), exempt).as_deref(), Some("educacional"), "audible tab while another app is focused");
        assert_eq!(exemption_decision(true, false, Some(&edu), Some(&edu2), exempt).as_deref(), Some("educacional"));
        // A non-exempt video alongside keeps counting
        assert!(exemption_decision(true, false, Some(&edu), Some(&game), exempt).is_none());
        assert!(exemption_decision(true, false, Some(&game), None, exempt).is_none());
        // No video (home/feed) counts
        assert!(exemption_decision(true, true, None, None, exempt).is_none());
        // Non-YouTube rule only exempt through the focused browser tab
        assert!(exemption_decision(false, false, Some(&edu), None, exempt).is_none());
        assert_eq!(exemption_decision(false, true, Some(&edu), Some(&game), exempt).as_deref(), Some("educacional"));
        assert!(exemption_decision(false, true, None, Some(&edu), exempt).is_none());

        assert!(rule_is_youtube_related("group_x", "Sessão", r#"{"apps":[{"name":"Youtube","exec":"youtube"}]}"#));
        assert!(rule_is_youtube_related("s", "Vídeos", "youtu.be"));
        assert!(!rule_is_youtube_related("g", "Estudo", r#"{"apps":["libreoffice"]}"#));
    }

    #[test]
    fn test_exemptions_caps_and_pick() {
        let g = |items: &str| db::WhitelistGroupItem {
            group_id: "g".into(),
            display_name: "g".into(),
            items: items.into(),
            created_at_utc: 0,
        };
        let ex = parse_exemptions(&[
            g(r#"{"apps":[],"sites":[],"yt_types":["musica",{"type":"educacional","cap_minutes":180}]}"#),
            g(r#"{"yt_types":[{"type":"educacional","cap_minutes":60}]}"#),
            g("legacy,csv"),
        ]);
        assert_eq!(ex.get("musica"), Some(&None));
        assert_eq!(ex.get("educacional"), Some(&Some(180 * 60)), "most generous cap wins");
        assert!(!ex.contains_key("podcasts"));

        let types = vec!["educacional".to_string(), "podcasts".to_string()];
        assert_eq!(pick_exempt_type(&types, &ex, |_| 0).as_deref(), Some("educacional"));
        assert_eq!(pick_exempt_type(&types, &ex, |_| 180 * 60), None, "cap reached -> counts again");
        assert_eq!(pick_exempt_type(&["musica".into()], &ex, |_| 999_999).as_deref(), Some("musica"), "no cap");
    }
}
