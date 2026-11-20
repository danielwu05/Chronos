//! Root-owned vault (layered anti-cheat).
//!
//! `chronos_vault sync` runs as root (from the guard, every 5 s). It mirrors the
//! protected part of the user's database into `/var/lib/chronos/vault/<user>/state.json`
//! and, while anti-cheat is active, reverts any change the app itself would refuse
//! (turning anti-cheat off without the challenge, deleting/loosening rules, lowering
//! usage, turning filters off, ...). It also keeps the daemon/autostart alive, tracks the
//! trusted clock, and appends every tampering attempt to `tamper.log`.

use crate::trusted_time::{self, ClockState};
use rusqlite::{Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

/// app_config keys guarded by the vault.
pub const PROTECTED_KEYS: &[&str] = &[
    "anti_cheat_mode",
    "anti_cheat_nuke_until_utc",
    "anti_cheat_current_text",
    "anti_cheat_custom_texts",
    "app_mode",
    "focus_filters",
    "adult_filter",
    "block_private_browsing",
    "yt_custom_rules",
    "custom_holidays",
    "holiday_quotas",
    "tamper_reaction",
    "penalty_until",
];

pub const DAEMON_UNIT: &str = "chronos-proxy.service";
const NETWORK_CHECK_EVERY_S: i64 = 1800;

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct RuleRow {
    pub display_name: String,
    pub daily_quota_seconds: i64,
    pub is_blocked_completely: i64,
    pub mode: String,
    pub ratchet_locked_until_utc: Option<i64>,
    pub updated_at_utc: i64,
    pub target_type: String,
    pub pattern: Option<String>,
    pub weekend_quota_seconds: Option<i64>,
    pub schedule_json: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct WlRow {
    pub display_name: String,
    pub items: String,
    pub created_at_utc: i64,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct UsageRow {
    pub entity_id: String,
    pub device_id: String,
    pub started_at_utc: i64,
    pub ended_at_utc: i64,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Snapshot {
    #[serde(default)]
    pub config: BTreeMap<String, String>,
    #[serde(default)]
    pub rules: BTreeMap<String, RuleRow>,
    #[serde(default)]
    pub whitelist: BTreeMap<String, WlRow>,
    /// Today's usage intervals (trusted UTC day).
    #[serde(default)]
    pub usage: BTreeMap<String, UsageRow>,
    /// (remaining_tokens, leisure_locked_until_utc)
    #[serde(default)]
    pub tokens: Option<(i64, i64)>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct VaultState {
    #[serde(default)]
    pub snapshot: Snapshot,
    #[serde(default)]
    pub clock: ClockState,
    #[serde(default)]
    pub files: BTreeMap<String, String>,
    #[serde(default)]
    pub updated_at: i64,
}

// ---------------------------------------------------------------------------
// Paths

pub fn vault_root() -> PathBuf {
    std::env::var_os("CHRONOS_VAULT_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/var/lib/chronos/vault"))
}

pub fn user_dir(user: &str) -> PathBuf {
    vault_root().join(user)
}

pub fn state_path(user: &str) -> PathBuf {
    user_dir(user).join("state.json")
}

pub fn tamper_log_path(user: &str) -> PathBuf {
    user_dir(user).join("tamper.log")
}

/// Login name of the current (non-root) process.
pub fn current_user() -> String {
    for var in ["USER", "LOGNAME"] {
        if let Ok(v) = std::env::var(var) {
            if !v.trim().is_empty() {
                return v;
            }
        }
    }
    std::env::var("HOME")
        .ok()
        .and_then(|h| Path::new(&h).file_name().map(|n| n.to_string_lossy().to_string()))
        .unwrap_or_default()
}

pub fn read_state(user: &str) -> Option<VaultState> {
    let text = std::fs::read_to_string(state_path(user)).ok()?;
    serde_json::from_str(&text).ok()
}

/// Vault state for the current user (read by the engine for the clock offset).
pub fn read_published_state() -> Option<VaultState> {
    if crate::profile::is_dev() || (cfg!(test) && std::env::var_os("CHRONOS_VAULT_DIR").is_none()) {
        return None;
    }
    let user = current_user();
    if user.is_empty() {
        return None;
    }
    read_state(&user)
}

fn write_state(user: &str, state: &VaultState) -> Result<(), String> {
    let dir = user_dir(user);
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let tmp = dir.join("state.json.tmp");
    std::fs::write(&tmp, serde_json::to_vec_pretty(state).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, state_path(user)).map_err(|e| e.to_string())
}

// ---------------------------------------------------------------------------
// Tamper log

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TamperEvent {
    pub at: i64,
    pub kind: String,
    pub detail: String,
}

pub fn log_tamper(user: &str, at: i64, kind: &str, detail: &str) {
    use std::io::Write;
    let dir = user_dir(user);
    let _ = std::fs::create_dir_all(&dir);
    let line = serde_json::to_string(&TamperEvent { at, kind: kind.to_string(), detail: detail.to_string() })
        .unwrap_or_default();
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(tamper_log_path(user)) {
        let _ = writeln!(f, "{line}");
    }
}

/// Latest tamper events (newest first).
pub fn read_tamper_events(user: &str, limit: usize) -> Vec<TamperEvent> {
    let Ok(text) = std::fs::read_to_string(tamper_log_path(user)) else {
        return Vec::new();
    };
    let mut out: Vec<TamperEvent> = text.lines().filter_map(|l| serde_json::from_str(l).ok()).collect();
    out.reverse();
    out.truncate(limit);
    out
}

// ---------------------------------------------------------------------------
// Snapshot

pub fn day_start(now: i64) -> i64 {
    now - now.rem_euclid(86400)
}

pub fn read_snapshot(conn: &Connection, now: i64) -> rusqlite::Result<Snapshot> {
    let mut snap = Snapshot::default();
    {
        let mut st = conn.prepare("SELECT key, value FROM app_config")?;
        let rows = st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?;
        for (k, v) in rows.flatten() {
            if PROTECTED_KEYS.contains(&k.as_str()) {
                snap.config.insert(k, v);
            }
        }
    }
    {
        let mut st = conn.prepare(
            "SELECT entity_id, display_name, daily_quota_seconds, is_blocked_completely, mode, ratchet_locked_until_utc,
                    updated_at_utc, COALESCE(target_type, 'APP'), pattern, weekend_quota_seconds, schedule_json FROM rules",
        )?;
        let rows = st.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                RuleRow {
                    display_name: r.get(1)?,
                    daily_quota_seconds: r.get(2)?,
                    is_blocked_completely: r.get(3)?,
                    mode: r.get(4)?,
                    ratchet_locked_until_utc: r.get(5)?,
                    updated_at_utc: r.get(6)?,
                    target_type: r.get(7)?,
                    pattern: r.get(8)?,
                    weekend_quota_seconds: r.get(9)?,
                    schedule_json: r.get(10)?,
                },
            ))
        })?;
        for (k, v) in rows.flatten() {
            snap.rules.insert(k, v);
        }
    }
    {
        let mut st = conn.prepare("SELECT group_id, display_name, items, created_at_utc FROM whitelist_groups")?;
        let rows = st.query_map([], |r| {
            Ok((r.get::<_, String>(0)?, WlRow { display_name: r.get(1)?, items: r.get(2)?, created_at_utc: r.get(3)? }))
        })?;
        for (k, v) in rows.flatten() {
            snap.whitelist.insert(k, v);
        }
    }
    {
        let mut st = conn.prepare(
            "SELECT interval_id, entity_id, device_id, started_at_utc, ended_at_utc FROM usage_intervals WHERE started_at_utc >= ?1",
        )?;
        let rows = st.query_map([day_start(now)], |r| {
            Ok((
                r.get::<_, String>(0)?,
                UsageRow { entity_id: r.get(1)?, device_id: r.get(2)?, started_at_utc: r.get(3)?, ended_at_utc: r.get(4)? },
            ))
        })?;
        for (k, v) in rows.flatten() {
            snap.usage.insert(k, v);
        }
    }
    snap.tokens = conn
        .query_row("SELECT remaining_tokens, leisure_locked_until_utc FROM emergency_tokens WHERE id = 1", [], |r| {
            Ok((r.get(0)?, r.get(1)?))
        })
        .optional()?;
    Ok(snap)
}

// ---------------------------------------------------------------------------
// Rules

fn cfg<'a>(s: &'a Snapshot, k: &str) -> &'a str {
    s.config.get(k).map(String::as_str).unwrap_or("")
}

/// Anti-cheat active according to a snapshot and the trusted time.
pub fn anti_cheat_active(s: &Snapshot, now: i64) -> bool {
    match cfg(s, "anti_cheat_mode") {
        "CHALLENGE" => true,
        "NUKE" => cfg(s, "anti_cheat_nuke_until_utc").parse::<i64>().unwrap_or(0) > now,
        _ => false,
    }
}

pub fn parental(s: &Snapshot) -> bool {
    cfg(s, "app_mode") == "PARENTAL"
}

fn json_list(v: &str) -> Vec<serde_json::Value> {
    serde_json::from_str::<Vec<serde_json::Value>>(v).unwrap_or_default()
}

fn added_items(prev: &str, next: &str) -> bool {
    let p = json_list(prev);
    json_list(next).iter().any(|x| !p.contains(x))
}

/// Changes that are not allowed while anti-cheat is active (empty = everything allowed).
pub fn diff_violations(prev: &Snapshot, next: &Snapshot, now: i64) -> Vec<String> {
    let mut v: Vec<String> = Vec::new();
    if !anti_cheat_active(prev, now) {
        return v;
    }

    // Anti-cheat itself: only the vault `unlock` may turn it off; NUKE may only be extended.
    let (pm, nm) = (cfg(prev, "anti_cheat_mode"), cfg(next, "anti_cheat_mode"));
    let pn = cfg(prev, "anti_cheat_nuke_until_utc").parse::<i64>().unwrap_or(0);
    let nn = cfg(next, "anti_cheat_nuke_until_utc").parse::<i64>().unwrap_or(0);
    let mode_ok = pm == nm || (pm == "CHALLENGE" && nm == "NUKE" && nn > now);
    if !mode_ok || (nm == "NUKE" && nn < pn) {
        v.push("Anti-Burla desligado sem o desafio".to_string());
    }
    for k in ["anti_cheat_custom_texts", "app_mode"] {
        if cfg(prev, k) != cfg(next, k) {
            v.push(format!("Configuração protegida alterada ({k})"));
        }
    }
    // A new challenge text is drawn each time the challenge closes: it must come from the
    // pool (built-in + the user's texts saved before anti-cheat).
    let next_text = cfg(next, "anti_cheat_current_text");
    if next_text != cfg(prev, "anti_cheat_current_text")
        && !crate::engine::challenge_pool(cfg(prev, "anti_cheat_custom_texts")).iter().any(|t| t.trim() == next_text.trim())
    {
        v.push("Texto do desafio trocado por um texto fora da lista".to_string());
    }

    // Rules: existing rules can only be renamed or tightened.
    for (id, p) in &prev.rules {
        match next.rules.get(id) {
            None => v.push(format!("Regra '{}' apagada", p.display_name)),
            Some(n) => {
                let loosened = n.daily_quota_seconds > p.daily_quota_seconds
                    || n.mode != p.mode
                    || n.target_type != p.target_type
                    || !crate::engine::same_json_text(p.pattern.as_deref().unwrap_or(""), n.pattern.as_deref().unwrap_or(""))
                    || n.weekend_quota_seconds.unwrap_or(0) > p.weekend_quota_seconds.unwrap_or(0)
                    || !crate::engine::same_json_text(
                        p.schedule_json.as_deref().unwrap_or(""),
                        n.schedule_json.as_deref().unwrap_or(""),
                    )
                    || (p.is_blocked_completely == 1 && n.is_blocked_completely == 0)
                    || n.ratchet_locked_until_utc.unwrap_or(0) < p.ratchet_locked_until_utc.unwrap_or(0);
                if loosened {
                    v.push(format!("Regra '{}' afrouxada", p.display_name));
                }
            }
        }
    }

    // Whitelist: removing groups tightens; adding/changing loosens.
    for (id, n) in &next.whitelist {
        match prev.whitelist.get(id) {
            None => v.push(format!("Lista branca '{}' criada", n.display_name)),
            Some(p) if p.items != n.items => v.push(format!("Lista branca '{}' alterada", n.display_name)),
            _ => {}
        }
    }

    // Usage: today's time can only grow.
    let mut usage_lowered = false;
    for (id, p) in &prev.usage {
        match next.usage.get(id) {
            None => usage_lowered = true,
            Some(n) if n.ended_at_utc < p.ended_at_utc || n.started_at_utc > p.started_at_utc => usage_lowered = true,
            _ => {}
        }
    }
    if usage_lowered {
        v.push("Tempo de uso de hoje apagado".to_string());
    }

    if let (Some((pt, pl)), Some((nt, nl))) = (prev.tokens, next.tokens) {
        if nt > pt || nl < pl {
            v.push("Tokens de emergência alterados".to_string());
        }
    }

    // Filters (same rules the app enforces).
    let pf: crate::db::FocusFilters = serde_json::from_str(cfg(prev, "focus_filters")).unwrap_or_default();
    let nf: crate::db::FocusFilters = serde_json::from_str(cfg(next, "focus_filters")).unwrap_or_default();
    if !cfg(prev, "focus_filters").is_empty() && crate::db::validate_focus_filters_anti_cheat(&pf, &nf, true).is_err() {
        v.push("Filtros de conteúdo afrouxados".to_string());
    }
    if let (Ok(pa), Ok(na)) = (
        serde_json::from_str::<crate::adult::AdultFilterSettings>(cfg(prev, "adult_filter")),
        serde_json::from_str::<crate::adult::AdultFilterSettings>(cfg(next, "adult_filter")),
    ) {
        if crate::adult::is_loosening(&pa, &na) {
            v.push("Filtro de conteúdo adulto afrouxado".to_string());
        }
    } else if !cfg(prev, "adult_filter").is_empty() && cfg(next, "adult_filter").is_empty() {
        v.push("Filtro de conteúdo adulto apagado".to_string());
    }
    if cfg(prev, "block_private_browsing") != "0" && cfg(next, "block_private_browsing") == "0" {
        v.push("Bloqueio da guia anônima desligado".to_string());
    }
    if added_items(cfg(prev, "yt_custom_rules"), cfg(next, "yt_custom_rules")) {
        v.push("Tipos personalizados do YouTube adicionados".to_string());
    }
    if added_items(cfg(prev, "custom_holidays"), cfg(next, "custom_holidays")) {
        v.push("Feriado adicionado".to_string());
    }
    if cfg(prev, "holiday_quotas") != cfg(next, "holiday_quotas") {
        let pq: serde_json::Value = serde_json::from_str(cfg(prev, "holiday_quotas")).unwrap_or_default();
        let nq: serde_json::Value = serde_json::from_str(cfg(next, "holiday_quotas")).unwrap_or_default();
        let raised = nq.as_object().is_some_and(|nm| {
            nm.iter().any(|(k, nv)| {
                let p = pq.get(k).and_then(|x| x.as_i64());
                nv.as_i64().is_some_and(|n| p.is_none_or(|p| n > p))
            })
        });
        if raised {
            v.push("Cota de feriado aumentada".to_string());
        }
    }
    if cfg(prev, "tamper_reaction") == "restore_penalty" && cfg(next, "tamper_reaction") != "restore_penalty" {
        v.push("Penalidade por burla desligada".to_string());
    }
    if cfg(next, "penalty_until").parse::<i64>().unwrap_or(0) < cfg(prev, "penalty_until").parse::<i64>().unwrap_or(0) {
        v.push("Penalidade encerrada antes da hora".to_string());
    }
    v
}

fn now_ts() -> i64 {
    trusted_time::system_now_secs()
}

/// Puts the protected state of `prev` back into the database (new rules are kept).
pub fn restore(conn: &mut Connection, prev: &Snapshot, next: &Snapshot) -> rusqlite::Result<()> {
    let tx = conn.transaction()?;
    let ts = now_ts();
    for k in PROTECTED_KEYS {
        match prev.config.get(*k) {
            Some(val) => {
                tx.execute(
                    "INSERT INTO app_config (key, value, updated_at_utc) VALUES (?1, ?2, ?3)
                     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at_utc = excluded.updated_at_utc",
                    (k, val, ts),
                )?;
            }
            None => {
                tx.execute("DELETE FROM app_config WHERE key = ?1", [k])?;
            }
        }
    }
    for (id, r) in &prev.rules {
        // Keep a legitimate rename made in the meantime.
        let name = next.rules.get(id).map(|n| n.display_name.clone()).unwrap_or_else(|| r.display_name.clone());
        tx.execute(
            "INSERT OR REPLACE INTO rules (entity_id, display_name, daily_quota_seconds, is_blocked_completely, mode,
                ratchet_locked_until_utc, updated_at_utc, target_type, pattern, weekend_quota_seconds, schedule_json)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            rusqlite::params![
                id,
                name,
                r.daily_quota_seconds.min(next.rules.get(id).map_or(i64::MAX, |n| n.daily_quota_seconds)),
                r.is_blocked_completely.max(next.rules.get(id).map_or(0, |n| n.is_blocked_completely)),
                r.mode,
                r.ratchet_locked_until_utc,
                ts,
                r.target_type,
                r.pattern,
                r.weekend_quota_seconds,
                r.schedule_json
            ],
        )?;
    }
    for (id, n) in &next.whitelist {
        if prev.whitelist.get(id) != Some(n) {
            tx.execute("DELETE FROM whitelist_groups WHERE group_id = ?1", [id])?;
        }
    }
    for (id, w) in &prev.whitelist {
        if next.whitelist.contains_key(id) && next.whitelist.get(id) != Some(w) {
            tx.execute(
                "INSERT OR REPLACE INTO whitelist_groups (group_id, display_name, items, created_at_utc) VALUES (?1, ?2, ?3, ?4)",
                (id, &w.display_name, &w.items, w.created_at_utc),
            )?;
        }
    }
    for (id, u) in &prev.usage {
        let ended = u.ended_at_utc.max(next.usage.get(id).map_or(0, |n| n.ended_at_utc));
        tx.execute(
            "INSERT OR REPLACE INTO usage_intervals (interval_id, entity_id, device_id, started_at_utc, ended_at_utc)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            (id, &u.entity_id, &u.device_id, u.started_at_utc, ended),
        )?;
    }
    if let Some((t, l)) = prev.tokens {
        tx.execute(
            "UPDATE emergency_tokens SET remaining_tokens = MIN(remaining_tokens, ?1), leisure_locked_until_utc = MAX(leisure_locked_until_utc, ?2) WHERE id = 1",
            (t, l),
        )?;
    }
    tx.commit()
}

fn set_config_conn(conn: &Connection, key: &str, value: &str) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO app_config (key, value, updated_at_utc) VALUES (?1, ?2, ?3)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at_utc = excluded.updated_at_utc",
        (key, value, now_ts()),
    )?;
    Ok(())
}

/// Next local midnight after `now` (unix seconds).
fn next_local_midnight(conn: &Connection, now: i64) -> i64 {
    conn.query_row(
        "SELECT CAST(strftime('%s', ?1, 'unixepoch', 'localtime', 'start of day', '+1 day', 'utc') AS INTEGER)",
        [now],
        |r| r.get(0),
    )
    .unwrap_or(day_start(now) + 86400)
}

// ---------------------------------------------------------------------------
// System helpers (root side)

pub struct UserInfo {
    pub name: String,
    pub uid: u32,
    pub gid: u32,
    pub home: PathBuf,
}

pub fn lookup_user(name: &str) -> Option<UserInfo> {
    let passwd = std::fs::read_to_string("/etc/passwd").ok()?;
    for line in passwd.lines() {
        let f: Vec<&str> = line.split(':').collect();
        if f.len() >= 6 && f[0] == name {
            return Some(UserInfo {
                name: name.to_string(),
                uid: f[2].parse().ok()?,
                gid: f[3].parse().ok()?,
                home: PathBuf::from(f[5]),
            });
        }
    }
    None
}

fn chown_db_files(db: &Path, user: &UserInfo) {
    for suffix in ["", "-wal", "-shm", "-journal"] {
        let p = PathBuf::from(format!("{}{}", db.display(), suffix));
        if p.exists() {
            let _ = std::os::unix::fs::chown(&p, Some(user.uid), Some(user.gid));
        }
    }
}

fn write_user_file(path: &Path, content: &str, user: &UserInfo) {
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
        let _ = std::os::unix::fs::chown(parent, Some(user.uid), Some(user.gid));
    }
    if std::fs::write(path, content).is_ok() {
        let _ = std::os::unix::fs::chown(path, Some(user.uid), Some(user.gid));
    }
}

fn user_systemctl(user: &str, args: &[&str]) -> Option<String> {
    let target = format!("{user}@");
    let out = std::process::Command::new("systemctl")
        .args(["--user", "-M", &target])
        .args(args)
        .output()
        .ok()?;
    Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// Watched user files: (vault key, path, required marker in the content).
fn watched_files(home: &Path) -> Vec<(&'static str, PathBuf, &'static str)> {
    vec![
        ("daemon_unit", home.join(".config/systemd/user").join(DAEMON_UNIT), "chronos_proxy"),
        ("autostart", home.join(".config/autostart/chronos.desktop"), "chronos_app"),
    ]
}

// ---------------------------------------------------------------------------
// Commands

pub struct SyncReport {
    pub violations: Vec<String>,
    pub events: Vec<(String, String)>,
}

/// One vault round for `user` (root). See module docs.
pub fn sync(user: &str, db_path: &Path) -> Result<SyncReport, String> {
    let info = lookup_user(user).ok_or_else(|| format!("usuário desconhecido: {user}"))?;
    let mut state = read_state(user).unwrap_or_default();
    let first_run = state.updated_at == 0;
    let mut events: Vec<(String, String)> = Vec::new();
    let mut dirty = first_run;

    // 1. Trusted clock.
    let wall = trusted_time::system_now_secs();
    let (clock, ev) = trusted_time::advance(&state.clock, &trusted_time::read_boot_id(), wall, trusted_time::read_uptime());
    if let Some(e) = ev {
        events.push(("clock_changed".into(), e));
    }
    let mut clock = clock;
    if wall - clock.last_network_check > NETWORK_CHECK_EVERY_S || clock.last_network_check > wall + 60 {
        let net = crate::steam_api::run_async_blocking(crate::steam_api::fetch_server_date("www.google.com"));
        match net {
            Ok(t) => {
                let (c2, ev) = trusted_time::apply_network(&clock, wall, t);
                clock = c2;
                if let Some(e) = ev {
                    events.push(("clock_changed".into(), e));
                }
            }
            Err(_) => clock.last_network_check = wall - NETWORK_CHECK_EVERY_S + 300, // retry in 5 min
        }
    }
    if clock.offset != state.clock.offset || clock.boot_id != state.clock.boot_id || wall - state.updated_at > 60 {
        dirty = true;
    }
    state.clock = clock;
    let now = wall + state.clock.offset;

    let protected_db = anti_cheat_active(&state.snapshot, now);
    let protected_runtime = protected_db || parental(&state.snapshot);

    // 2. Database.
    let mut violations = Vec::new();
    if !db_path.exists() {
        if protected_runtime && !first_run {
            events.push(("db_deleted".into(), "Banco de dados do Chronos apagado".into()));
        }
    } else {
        let mut conn = Connection::open(db_path).map_err(|e| e.to_string())?;
        let _ = conn.busy_timeout(std::time::Duration::from_millis(2000));
        match read_snapshot(&conn, now) {
            Ok(next) => {
                violations = if first_run { Vec::new() } else { diff_violations(&state.snapshot, &next, now) };
                if violations.is_empty() {
                    if next != state.snapshot {
                        state.snapshot = next;
                        dirty = true;
                    }
                } else {
                    let prev = state.snapshot.clone();
                    restore(&mut conn, &prev, &next).map_err(|e| e.to_string())?;
                    events.push(("db_edit".into(), violations.join("; ")));
                    if cfg(&prev, "tamper_reaction") == "restore_penalty" {
                        let until = next_local_midnight(&conn, now);
                        let _ = set_config_conn(&conn, "penalty_until", &until.to_string());
                    }
                    state.snapshot = read_snapshot(&conn, now).unwrap_or(prev);
                    dirty = true;
                }
            }
            Err(e) => {
                if protected_runtime {
                    events.push(("db_deleted".into(), format!("Banco de dados ilegível: {e}")));
                }
            }
        }
        drop(conn);
        chown_db_files(db_path, &info);
    }

    // 3. Daemon + autostart (runtime protection).
    for (key, path, marker) in watched_files(&info.home) {
        let current = std::fs::read_to_string(&path).ok();
        match (&current, state.files.get(key)) {
            (Some(c), _) if c.contains(marker) => {
                if state.files.get(key) != Some(c) {
                    state.files.insert(key.to_string(), c.clone());
                    dirty = true;
                }
            }
            (_, Some(saved)) if protected_runtime => {
                let saved = saved.clone();
                write_user_file(&path, &saved, &info);
                events.push((format!("{key}_removed"), format!("{} apagado ou alterado; restaurado", path.display())));
            }
            _ => {}
        }
    }
    if protected_runtime && state.files.contains_key("daemon_unit") {
        let enabled = user_systemctl(user, &["is-enabled", DAEMON_UNIT]).unwrap_or_default();
        let active = user_systemctl(user, &["is-active", DAEMON_UNIT]).unwrap_or_default();
        // Only act when the user manager answered (session running).
        if !enabled.is_empty() && (enabled != "enabled" || active != "active") {
            let _ = user_systemctl(user, &["unmask", DAEMON_UNIT]);
            let _ = user_systemctl(user, &["daemon-reload"]);
            let _ = user_systemctl(user, &["enable", "--now", DAEMON_UNIT]);
            events.push((
                "daemon_stopped".into(),
                format!("Serviço do Chronos estava {enabled}/{active}; religado"),
            ));
        }
    }

    for (kind, detail) in &events {
        log_tamper(user, now, kind, detail);
    }
    if dirty || !events.is_empty() {
        state.updated_at = wall;
        write_state(user, &state)?;
    }
    Ok(SyncReport { violations, events })
}

/// Turns anti-cheat off after the challenge (or when a NUKE has expired by trusted time).
pub fn unlock(user: &str, db_path: &Path, typed: &str) -> Result<(), String> {
    let info = lookup_user(user).ok_or_else(|| format!("usuário desconhecido: {user}"))?;
    let mut state = read_state(user).unwrap_or_default();
    let now = trusted_time::system_now_secs() + state.clock.offset;
    let snap = &state.snapshot;
    if anti_cheat_active(snap, now) {
        if cfg(snap, "anti_cheat_mode") == "NUKE" {
            let until = cfg(snap, "anti_cheat_nuke_until_utc").parse::<i64>().unwrap_or(0);
            log_tamper(user, now, "unlock_failed", "Tentativa de encerrar o Modo Nuke antes da hora");
            return Err(format!("Modo Nuke ativo por mais {} min.", (until - now).max(0) / 60 + 1));
        }
        let expected = snap
            .config
            .get("anti_cheat_current_text")
            .filter(|t| !t.trim().is_empty())
            .cloned()
            .unwrap_or_else(|| crate::engine::STAYFOCUSD_CHALLENGE_TEXT.to_string());
        if !crate::i18n::variants(&expected).iter().any(|v| v.trim() == typed.trim()) {
            log_tamper(user, now, "unlock_failed", "Texto do desafio incorreto");
            return Err("Texto do desafio incorreto.".to_string());
        }
    }
    let conn = Connection::open(db_path).map_err(|e| e.to_string())?;
    let _ = conn.busy_timeout(std::time::Duration::from_millis(2000));
    set_config_conn(&conn, "anti_cheat_mode", "OFF").map_err(|e| e.to_string())?;
    set_config_conn(&conn, "anti_cheat_nuke_until_utc", "0").map_err(|e| e.to_string())?;
    state.snapshot = read_snapshot(&conn, now).map_err(|e| e.to_string())?;
    drop(conn);
    chown_db_files(db_path, &info);
    state.updated_at = trusted_time::system_now_secs();
    write_state(user, &state)
}

/// Whether the vault currently protects the user (anti-cheat on, by trusted time).
pub fn status(user: &str) -> (bool, bool) {
    let Some(state) = read_state(user) else { return (false, false) };
    let now = trusted_time::system_now_secs() + state.clock.offset;
    (anti_cheat_active(&state.snapshot, now), parental(&state.snapshot))
}

/// Removes the vault (refused while anti-cheat is active).
pub fn uninstall(user: &str) -> Result<(), String> {
    if status(user).0 {
        return Err("Anti-Burla ativo: o Chronos não pode ser desinstalado agora.".to_string());
    }
    let dir = user_dir(user);
    if dir.exists() {
        std::fs::remove_dir_all(&dir).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn base() -> Snapshot {
        let mut s = Snapshot::default();
        s.config.insert("anti_cheat_mode".into(), "CHALLENGE".into());
        s.config.insert("anti_cheat_current_text".into(), "texto".into());
        s.rules.insert(
            "g1".into(),
            RuleRow {
                display_name: "Grupo".into(),
                daily_quota_seconds: 600,
                mode: "QUOTA".into(),
                target_type: "GROUP".into(),
                pattern: Some(r#"{"apps":[],"sites":["x.com"]}"#.into()),
                ..Default::default()
            },
        );
        s.usage.insert(
            "u1".into(),
            UsageRow { entity_id: "g1".into(), device_id: "d".into(), started_at_utc: 100, ended_at_utc: 200 },
        );
        s.tokens = Some((2, 0));
        s
    }

    #[test]
    fn violations_by_kind() {
        let now = 1000;
        let p = base();
        assert!(diff_violations(&p, &p, now).is_empty());

        let mut n = p.clone();
        n.config.insert("anti_cheat_mode".into(), "OFF".into());
        assert!(diff_violations(&p, &n, now)[0].contains("Anti-Burla"));

        let mut n = p.clone();
        n.rules.clear();
        assert!(diff_violations(&p, &n, now).iter().any(|v| v.contains("apagada")));

        let mut n = p.clone();
        n.rules.get_mut("g1").unwrap().daily_quota_seconds = 900;
        assert!(diff_violations(&p, &n, now).iter().any(|v| v.contains("afrouxada")));

        let mut n = p.clone();
        n.rules.get_mut("g1").unwrap().display_name = "Novo".into();
        n.rules.get_mut("g1").unwrap().daily_quota_seconds = 300;
        n.rules.insert("g2".into(), RuleRow { display_name: "Nova".into(), ..Default::default() });
        n.usage.get_mut("u1").unwrap().ended_at_utc = 260;
        assert!(diff_violations(&p, &n, now).is_empty(), "rename, tighten, new rule, usage growing are fine");

        let mut n = p.clone();
        n.config.insert("anti_cheat_current_text".into(), crate::engine::BUILTIN_CHALLENGE_TEXTS[1].into());
        assert!(diff_violations(&p, &n, now).is_empty(), "redraw from the pool is fine");
        n.config.insert("anti_cheat_current_text".into(), "a".into());
        assert!(diff_violations(&p, &n, now).iter().any(|v| v.contains("fora da lista")));

        let mut n = p.clone();
        n.usage.clear();
        assert!(diff_violations(&p, &n, now).iter().any(|v| v.contains("uso")));

        let mut n = p.clone();
        n.tokens = Some((5, 0));
        assert!(!diff_violations(&p, &n, now).is_empty());

        let mut pp = p.clone();
        pp.config.insert("tamper_reaction".into(), "restore_penalty".into());
        let mut n = pp.clone();
        n.config.insert("tamper_reaction".into(), "restore".into());
        assert!(diff_violations(&pp, &n, now).iter().any(|v| v.contains("Penalidade")));

        let mut pa = p.clone();
        pa.config.insert("adult_filter".into(), r#"{"enabled":true,"use_domain_list":true}"#.into());
        let mut n = pa.clone();
        n.config.insert("adult_filter".into(), r#"{"enabled":false}"#.into());
        assert!(diff_violations(&pa, &n, now).iter().any(|v| v.contains("adulto")));

        // Anti-cheat off: nothing is a violation.
        let mut off = p.clone();
        off.config.insert("anti_cheat_mode".into(), "OFF".into());
        let mut n = off.clone();
        n.rules.clear();
        assert!(diff_violations(&off, &n, now).is_empty());

        // Nuke expired by trusted time: not protected.
        let mut nuke = p.clone();
        nuke.config.insert("anti_cheat_mode".into(), "NUKE".into());
        nuke.config.insert("anti_cheat_nuke_until_utc".into(), "900".into());
        assert!(!anti_cheat_active(&nuke, now));
        assert!(anti_cheat_active(&nuke, 800));
    }

    #[test]
    fn restore_puts_back_rules_and_usage() {
        let file = std::env::temp_dir().join(format!("chronos_vault_restore_{}.db", std::process::id()));
        let _ = std::fs::remove_file(&file);
        let mut conn = Connection::open(&file).unwrap();
        conn.execute_batch(
            "CREATE TABLE app_config (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at_utc INTEGER NOT NULL);
             CREATE TABLE rules (entity_id TEXT PRIMARY KEY, display_name TEXT NOT NULL, daily_quota_seconds INTEGER NOT NULL,
                is_blocked_completely INTEGER NOT NULL DEFAULT 0, mode TEXT NOT NULL, ratchet_locked_until_utc INTEGER,
                updated_at_utc INTEGER NOT NULL, target_type TEXT NOT NULL DEFAULT 'APP', pattern TEXT,
                weekend_quota_seconds INTEGER, schedule_json TEXT);
             CREATE TABLE usage_intervals (interval_id TEXT PRIMARY KEY, entity_id TEXT NOT NULL, device_id TEXT NOT NULL,
                started_at_utc INTEGER NOT NULL, ended_at_utc INTEGER NOT NULL, synced INTEGER NOT NULL DEFAULT 0);
             CREATE TABLE whitelist_groups (group_id TEXT PRIMARY KEY, display_name TEXT NOT NULL, items TEXT NOT NULL, created_at_utc INTEGER NOT NULL);
             CREATE TABLE emergency_tokens (id INTEGER PRIMARY KEY, remaining_tokens INTEGER NOT NULL, leisure_locked_until_utc INTEGER NOT NULL, last_reset_month INTEGER NOT NULL);
             INSERT INTO emergency_tokens VALUES (1, 2, 0, 0);",
        )
        .unwrap();
        let now = 1000;
        let prev = base();
        restore(&mut conn, &prev, &Snapshot::default()).unwrap();
        let snap = read_snapshot(&conn, now).unwrap();
        assert_eq!(snap.rules.len(), 1);
        assert_eq!(snap.config.get("anti_cheat_mode").map(String::as_str), Some("CHALLENGE"));
        // Tamper: anti-cheat off, rule deleted, usage deleted -> restored
        conn.execute("UPDATE app_config SET value='OFF' WHERE key='anti_cheat_mode'", []).unwrap();
        conn.execute("DELETE FROM rules", []).unwrap();
        conn.execute("DELETE FROM usage_intervals", []).unwrap();
        let tampered = read_snapshot(&conn, now).unwrap();
        assert!(!diff_violations(&prev, &tampered, now).is_empty());
        restore(&mut conn, &prev, &tampered).unwrap();
        let fixed = read_snapshot(&conn, now).unwrap();
        assert!(diff_violations(&prev, &fixed, now).is_empty(), "after restore: {:?}", diff_violations(&prev, &fixed, now));
        drop(conn);
        let _ = std::fs::remove_file(file);
    }
}
