use rusqlite::{Connection, Result};
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::OnceLock;
use parking_lot::Mutex;

static DB_CONN: OnceLock<Mutex<Connection>> = OnceLock::new();
static STATE_REVISION: AtomicI64 = AtomicI64::new(1);

pub struct DatabaseStats {
    pub total_rules: i64,
    pub total_intervals: i64,
    pub total_quarantine_items: i64,
    pub emergency_tokens: i64,
}

#[derive(Clone, Debug)]
pub struct OnboardingState {
    pub is_onboarded: bool,
    pub app_mode: String,       // "SELF_CONTROL" ou "PARENTAL"
    pub device_role: String,    // "NONE", "PARENT" ou "CHILD"
    pub device_id: String,
    pub pairing_code: String,
    pub is_paired: bool,
    pub pairing_payload_qr: String,
}

pub fn init_db(db_path: &str) -> Result<()> {
    let conn = Connection::open(db_path)?;

    // Evita esperas bloqueantes indefinidas em transações concorrentes
    let _ = conn.busy_timeout(std::time::Duration::from_millis(500));

    // Otimizações para gravação concorrente e integridade
    conn.execute_batch(
        "PRAGMA journal_mode = WAL;
         PRAGMA synchronous = NORMAL;
         PRAGMA foreign_keys = ON;"
    )?;

    // Tabelas fundamentais
    conn.execute_batch(
        "
        -- Configurações de onboarding, identidade e pareamento
        CREATE TABLE IF NOT EXISTS app_config (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at_utc INTEGER NOT NULL
        );

        -- Regras e cotas de entidades universais
        CREATE TABLE IF NOT EXISTS rules (
            entity_id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            daily_quota_seconds INTEGER NOT NULL,
            is_blocked_completely INTEGER NOT NULL DEFAULT 0,
            mode TEXT NOT NULL, -- 'PARENTAL' ou 'SELF_CONTROL'
            ratchet_locked_until_utc INTEGER,
            updated_at_utc INTEGER NOT NULL,
            target_type TEXT NOT NULL DEFAULT 'APP', -- 'APP', 'SITE', 'KEYWORD'
            pattern TEXT
        );

        -- Intervalos consumidos (Modelo União de Intervalos / Deltas)
        CREATE TABLE IF NOT EXISTS usage_intervals (
            interval_id TEXT PRIMARY KEY,
            entity_id TEXT NOT NULL,
            device_id TEXT NOT NULL,
            started_at_utc INTEGER NOT NULL,
            ended_at_utc INTEGER NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (entity_id) REFERENCES rules (entity_id)
        );

        -- Fila de quarentena / solicitações de instalação
        CREATE TABLE IF NOT EXISTS install_quarantine (
            request_id TEXT PRIMARY KEY,
            app_identifier TEXT NOT NULL,
            display_name TEXT NOT NULL,
            platform TEXT NOT NULL,
            status TEXT NOT NULL, -- 'QUARANTINED', 'PENDING', 'APPROVED', 'REJECTED'
            requested_at_utc INTEGER NOT NULL
        );

        -- Tokens de emergência (Modo Pessoal)
        CREATE TABLE IF NOT EXISTS emergency_tokens (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            remaining_tokens INTEGER NOT NULL DEFAULT 2,
            leisure_locked_until_utc INTEGER NOT NULL DEFAULT 0,
            last_reset_month INTEGER NOT NULL
        );

        -- Garante a linha única de tokens
        INSERT OR IGNORE INTO emergency_tokens (id, remaining_tokens, leisure_locked_until_utc, last_reset_month)
        VALUES (1, 2, 0, 0);

        -- Grupos de Lista Branca (Whitelist)
        CREATE TABLE IF NOT EXISTS whitelist_groups (
            group_id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            items TEXT NOT NULL,
            created_at_utc INTEGER NOT NULL
        );

        -- Catálogo de Tags da Steam API (EN / PT-BR)
        CREATE TABLE IF NOT EXISTS steam_tag_catalog (
            language TEXT NOT NULL,
            tag_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            updated_at_utc INTEGER NOT NULL,
            PRIMARY KEY (language, tag_id)
        );

        -- Cache local de metadados de jogos resolvidos pela Steam API
        CREATE TABLE IF NOT EXISTS game_metadata_cache (
            cache_key TEXT PRIMARY KEY,
            app_id INTEGER,
            title TEXT NOT NULL,
            tags_json TEXT NOT NULL,
            genres_json TEXT NOT NULL,
            categories_json TEXT NOT NULL,
            source TEXT NOT NULL,
            updated_at_utc INTEGER NOT NULL
        );
        "
    )?;

    // Migração de schema se tabela rules já existia sem target_type, pattern, weekend_quota_seconds, schedule_json
    let _ = conn.execute("ALTER TABLE rules ADD COLUMN target_type TEXT NOT NULL DEFAULT 'APP'", []);
    let _ = conn.execute("ALTER TABLE rules ADD COLUMN pattern TEXT", []);
    let _ = conn.execute("ALTER TABLE rules ADD COLUMN weekend_quota_seconds INTEGER", []);
    let _ = conn.execute("ALTER TABLE rules ADD COLUMN schedule_json TEXT", []);

    // Remove presets antigos inseridos automaticamente em versões anteriores
    let _ = conn.execute(
        "DELETE FROM usage_intervals WHERE entity_id IN ('youtube', 'discord', 'steam', 'twitter', 'reddit', 'group_youtube__v_deos___shorts_', 'group_redes_sociais__instagram_x_tiktok_', 'group_steam___jogos', 'group_discord___mensageiros')",
        [],
    );
    let _ = conn.execute(
        "DELETE FROM rules WHERE entity_id IN ('youtube', 'discord', 'steam', 'twitter', 'reddit') OR display_name IN ('YouTube (Vídeos & Shorts)', 'Redes Sociais (Instagram/X/TikTok)', 'Steam & Jogos', 'Discord / Mensageiros')",
        [],
    );

    if let Some(existing) = DB_CONN.get() {
        *existing.lock() = conn;
    } else {
        let _ = DB_CONN.set(Mutex::new(conn));
    }
    init_default_config()?;
    Ok(())
}

pub fn get_conn() -> &'static Mutex<Connection> {
    DB_CONN.get().expect("Banco de dados não foi inicializado!")
}

pub fn try_get_conn() -> Option<&'static Mutex<Connection>> {
    DB_CONN.get()
}

fn init_default_config() -> Result<()> {
    let conn = get_conn().lock();
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;

    let dev_id = format!("DEV-{:04X}", (now ^ 0xCAFE) & 0xFFFF);
    let pair_code = format!("CHR-{:04}", (now % 9000) + 1000);

    conn.execute(
        "INSERT OR IGNORE INTO app_config (key, value, updated_at_utc) VALUES ('is_onboarded', 'false', ?1)",
        [now],
    )?;
    conn.execute(
        "INSERT OR IGNORE INTO app_config (key, value, updated_at_utc) VALUES ('app_mode', 'SELF_CONTROL', ?1)",
        [now],
    )?;
    conn.execute(
        "INSERT OR IGNORE INTO app_config (key, value, updated_at_utc) VALUES ('device_role', 'NONE', ?1)",
        [now],
    )?;
    conn.execute(
        "INSERT OR IGNORE INTO app_config (key, value, updated_at_utc) VALUES ('device_id', ?1, ?2)",
        (&dev_id, now),
    )?;
    conn.execute(
        "INSERT OR IGNORE INTO app_config (key, value, updated_at_utc) VALUES ('pairing_code', ?1, ?2)",
        (&pair_code, now),
    )?;
    conn.execute(
        "INSERT OR IGNORE INTO app_config (key, value, updated_at_utc) VALUES ('is_paired', 'false', ?1)",
        [now],
    )?;
    conn.execute(
        "INSERT OR IGNORE INTO app_config (key, value, updated_at_utc) VALUES ('primary_language', 'pt-BR', ?1)",
        [now],
    )?;

    Ok(())
}

pub fn normalize_primary_language(raw: &str) -> &'static str {
    let lower = raw.trim().to_ascii_lowercase();
    if lower.starts_with("en") {
        "en-US"
    } else {
        "pt-BR"
    }
}

pub fn get_primary_language() -> String {
    if try_get_conn().is_none() {
        return "pt-BR".to_string();
    }
    let raw = get_config("primary_language").unwrap_or_else(|| "pt-BR".to_string());
    normalize_primary_language(&raw).to_string()
}

pub fn set_primary_language(lang: &str) -> Result<String> {
    let canonical = normalize_primary_language(lang).to_string();
    set_config("primary_language", &canonical)?;
    bump_state_revision();
    Ok(canonical)
}

/// Retorna o par `(language, country_code)` aceito pelos endpoints da Steam Web/Store API
/// de acordo com o idioma principal do aplicativo (`pt-BR` -> `("brazilian", "BR")`, `en-US` -> `("english", "US")`).
pub fn get_steam_language_and_country() -> (&'static str, &'static str) {
    if get_primary_language().starts_with("en") {
        ("english", "US")
    } else {
        ("brazilian", "BR")
    }
}

/// Incrementa revisão monotônica em memória e SQLite para propagação imediata via SSE/watchdog.
pub fn bump_state_revision() -> i64 {
    let local_next = STATE_REVISION.fetch_add(1, Ordering::SeqCst) + 1;
    let Some(conn_mutex) = try_get_conn() else {
        return local_next;
    };
    let conn = conn_mutex.lock();
    let db_curr: i64 = conn
        .query_row(
            "SELECT CAST(value AS INTEGER) FROM app_config WHERE key = 'state_revision'",
            [],
            |r| r.get(0),
        )
        .unwrap_or(0);
    let next = local_next.max(db_curr + 1);
    STATE_REVISION.store(next, Ordering::SeqCst);
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;
    let _ = conn.execute(
        "INSERT INTO app_config (key, value, updated_at_utc) VALUES ('state_revision', ?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at_utc = excluded.updated_at_utc",
        (next.to_string(), now),
    );
    next
}

pub fn get_state_revision() -> i64 {
    let local = STATE_REVISION.load(Ordering::SeqCst);
    let Some(conn_mutex) = try_get_conn() else {
        return local;
    };
    let conn = conn_mutex.lock();
    let db_curr: i64 = conn
        .query_row(
            "SELECT CAST(value AS INTEGER) FROM app_config WHERE key = 'state_revision'",
            [],
            |r| r.get(0),
        )
        .unwrap_or(0);
    let data_ver: i64 = conn
        .query_row("PRAGMA data_version", [], |r| r.get(0))
        .unwrap_or(0);
    db_curr.max(local).saturating_add(data_ver)
}

pub fn get_config(key: &str) -> Option<String> {
    let conn = get_conn().lock();
    conn.query_row(
        "SELECT value FROM app_config WHERE key = ?1",
        [key],
        |r| r.get(0),
    )
    .ok()
}

pub fn set_config(key: &str, value: &str) -> Result<()> {
    let conn = get_conn().lock();
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;

    conn.execute(
        "INSERT INTO app_config (key, value, updated_at_utc)
         VALUES (?1, ?2, ?3)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at_utc = excluded.updated_at_utc",
        (key, value, now),
    )?;
    Ok(())
}

pub fn get_onboarding_state() -> Result<OnboardingState> {
    let is_onboarded = get_config("is_onboarded").unwrap_or_else(|| "false".to_string()) == "true";
    let app_mode = get_config("app_mode").unwrap_or_else(|| "SELF_CONTROL".to_string());
    let device_role = get_config("device_role").unwrap_or_else(|| "NONE".to_string());
    let device_id = get_config("device_id").unwrap_or_else(|| "DEV-0001".to_string());
    let pairing_code = get_config("pairing_code").unwrap_or_else(|| "CHR-1000".to_string());
    let is_paired = get_config("is_paired").unwrap_or_else(|| "false".to_string()) == "true";

    let pairing_payload_qr = format!(
        "chronos://pair?id={}&role={}&code={}&mode={}",
        device_id, device_role, pairing_code, app_mode
    );

    Ok(OnboardingState {
        is_onboarded,
        app_mode,
        device_role,
        device_id,
        pairing_code,
        is_paired,
        pairing_payload_qr,
    })
}

pub fn save_onboarding_choice(
    app_mode: &str,
    device_role: &str,
    pairing_secret: Option<&str>,
) -> Result<()> {
    set_config("is_onboarded", "true")?;
    set_config("app_mode", app_mode)?;
    set_config("device_role", device_role)?;

    if let Some(secret) = pairing_secret {
        if !secret.trim().is_empty() {
            set_config("pairing_secret", secret.trim())?;
        }
    }

    let conn = get_conn().lock();
    let mode_str = if app_mode == "PARENTAL" { "PARENTAL" } else { "SELF_CONTROL" };
    let _ = conn.execute("UPDATE rules SET mode = ?1", [mode_str]);

    Ok(())
}

pub fn pair_device(input_code_or_pass: &str) -> Result<bool> {
    let clean_input = input_code_or_pass.trim().to_uppercase();
    let current_code = get_config("pairing_code").unwrap_or_default().to_uppercase();
    let stored_secret = get_config("pairing_secret").unwrap_or_default();

    let matched = clean_input == current_code
        || (!stored_secret.is_empty() && input_code_or_pass.trim() == stored_secret);

    if matched {
        set_config("is_paired", "true")?;
        Ok(true)
    } else {
        Ok(false)
    }
}

pub fn reset_onboarding_state() -> Result<()> {
    set_config("is_onboarded", "false")?;
    set_config("is_paired", "false")?;
    set_config("app_mode", "SELF_CONTROL")?;
    set_config("device_role", "NONE")?;
    Ok(())
}

/// Reset completo para ambiente de testes
pub fn reset_database_full() -> Result<()> {
    let conn = get_conn().lock();

    conn.execute_batch(
        "
        DELETE FROM usage_intervals;
        DELETE FROM install_quarantine;
        UPDATE emergency_tokens 
        SET remaining_tokens = 2, leisure_locked_until_utc = 0, last_reset_month = 0 
        WHERE id = 1;
        UPDATE rules 
        SET ratchet_locked_until_utc = NULL, is_blocked_completely = 0;
        "
    )?;

    drop(conn);
    reset_onboarding_state()?;

    Ok(())
}

/// Zera apenas o consumo diário (intervalos gravados), permitindo renovar a cota imediatamente
pub fn reset_daily_usage(entity_id: Option<&str>) -> Result<()> {
    let conn = get_conn().lock();
    if let Some(eid) = entity_id {
        conn.execute("DELETE FROM usage_intervals WHERE entity_id = ?1", [eid])?;
    } else {
        conn.execute("DELETE FROM usage_intervals", [])?;
    }
    Ok(())
}

/// Destrava a catraca da entidade (modo teste/debug)
pub fn debug_unlock_ratchet(entity_id: &str) -> Result<()> {
    let conn = get_conn().lock();
    conn.execute(
        "UPDATE rules SET ratchet_locked_until_utc = NULL WHERE entity_id = ?1",
        [entity_id],
    )?;
    Ok(())
}

/// Restaura os tokens de emergência para 2 e cancela trava de lazer
pub fn refill_emergency_tokens() -> Result<()> {
    let conn = get_conn().lock();
    conn.execute(
        "UPDATE emergency_tokens SET remaining_tokens = 2, leisure_locked_until_utc = 0 WHERE id = 1",
        [],
    )?;
    Ok(())
}

/// Retorna estatísticas atuais do banco para auditoria em tempo real
pub fn get_database_stats() -> Result<DatabaseStats> {
    let conn = get_conn().lock();

    let total_rules: i64 = conn.query_row("SELECT COUNT(*) FROM rules", [], |r| r.get(0)).unwrap_or(0);
    let total_intervals: i64 = conn.query_row("SELECT COUNT(*) FROM usage_intervals", [], |r| r.get(0)).unwrap_or(0);
    let total_quarantine_items: i64 = conn.query_row("SELECT COUNT(*) FROM install_quarantine", [], |r| r.get(0)).unwrap_or(0);
    let emergency_tokens: i64 = conn.query_row("SELECT remaining_tokens FROM emergency_tokens WHERE id = 1", [], |r| r.get(0)).unwrap_or(0);

    Ok(DatabaseStats {
        total_rules,
        total_intervals,
        total_quarantine_items,
        emergency_tokens,
    })
}

#[derive(Clone, Debug)]
pub struct WhitelistGroupItem {
    pub group_id: String,
    pub display_name: String,
    pub items: String,
    pub created_at_utc: i64,
}

pub fn get_all_whitelist_groups() -> Vec<WhitelistGroupItem> {
    let conn = get_conn().lock();
    let mut stmt = match conn.prepare("SELECT group_id, display_name, items, created_at_utc FROM whitelist_groups ORDER BY display_name ASC") {
        Ok(s) => s,
        Err(_) => return Vec::new(),
    };
    let rows = stmt.query_map([], |row| {
        Ok(WhitelistGroupItem {
            group_id: row.get(0)?,
            display_name: row.get(1)?,
            items: row.get(2)?,
            created_at_utc: row.get(3)?,
        })
    });
    match rows {
        Ok(mapped) => mapped.filter_map(Result::ok).collect(),
        Err(_) => Vec::new(),
    }
}

pub fn save_whitelist_group(group_id: &str, display_name: &str, items: &str) -> Result<()> {
    {
        let conn = get_conn().lock();
        let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_secs() as i64;
        let clean_id = if group_id.trim().is_empty() {
            format!("wl_{}", now)
        } else {
            group_id.trim().to_string()
        };
        conn.execute(
            "INSERT INTO whitelist_groups (group_id, display_name, items, created_at_utc)
             VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(group_id) DO UPDATE SET display_name = excluded.display_name, items = excluded.items",
            (&clean_id, display_name.trim(), items.trim(), now),
        )?;
    }
    let _ = bump_state_revision();
    Ok(())
}

pub fn delete_whitelist_group(group_id: &str) -> Result<()> {
    {
        let conn = get_conn().lock();
        conn.execute("DELETE FROM whitelist_groups WHERE group_id = ?1", [group_id])?;
    }
    let _ = bump_state_revision();
    Ok(())
}

pub fn is_item_in_whitelist_groups(groups: &[WhitelistGroupItem], identifier: &str) -> bool {
    let clean = identifier.trim().to_lowercase();
    if clean.is_empty() {
        return false;
    }
    for g in groups {
        let mut entries = Vec::new();
        let raw = g.items.trim();
        if raw.starts_with('{') {
            if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(raw) {
                if let Some(apps) = parsed.get("apps").and_then(|v| v.as_array()) {
                    for a in apps {
                        if let Some(s) = a.as_str() {
                            entries.push(s.trim().to_lowercase());
                        } else if let Some(obj) = a.as_object() {
                            if let Some(n) = obj.get("name").and_then(|v| v.as_str()) {
                                entries.push(n.trim().to_lowercase());
                            }
                            if let Some(e) = obj.get("exec").and_then(|v| v.as_str()) {
                                entries.push(e.trim().to_lowercase());
                            }
                        }
                    }
                }
                if let Some(sites) = parsed.get("sites").and_then(|v| v.as_array()) {
                    for s in sites {
                        if let Some(st) = s.as_str() {
                            entries.push(st.trim().to_lowercase());
                        }
                    }
                }
            }
        } else {
            for part in raw.split(',') {
                entries.push(part.trim().to_lowercase());
            }
        }

        for p_clean in entries {
            if !p_clean.is_empty() && (clean == p_clean || clean.contains(&p_clean) || p_clean.contains(&clean)) {
                return true;
            }
        }
    }
    false
}

pub fn is_item_whitelisted(identifier: &str) -> bool {
    let groups = get_all_whitelist_groups();
    is_item_in_whitelist_groups(&groups, identifier)
}

// ----------------- ESTATÍSTICAS E TEMA -----------------

#[derive(Clone, Debug, Default)]
pub struct TopEntityItem {
    pub entity_id: String,
    pub display_name: String,
    pub target_type: String,
    pub consumed_seconds: i64,
    pub percentage: f64,
}

#[derive(Clone, Debug, Default)]
pub struct DailyUsageItem {
    pub day_label: String,
    pub date_str: String,
    pub consumed_seconds: i64,
    pub is_today: bool,
}

#[derive(Clone, Debug, Default)]
pub struct AnalyticsSummary {
    pub total_consumed_today_seconds: i64,
    pub total_consumed_7d_seconds: i64,
    pub daily_average_7d_seconds: i64,
    pub peak_day_label: String,
    pub peak_day_seconds: i64,
    pub comparison_vs_prev_week_percent: f64,
    pub top_entities_7d: Vec<TopEntityItem>,
    pub daily_breakdown_7d: Vec<DailyUsageItem>,
}

pub fn get_analytics_summary() -> Result<AnalyticsSummary> {
    let conn = get_conn().lock();
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;

    let (today_start, dow): (i64, i32) = conn
        .query_row(
            "SELECT CAST(strftime('%s', 'now', 'localtime', 'start of day', 'utc') AS INTEGER), CAST(strftime('%w', 'now', 'localtime') AS INTEGER)",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap_or_else(|_| (now - (now % 86400), 1));

    let seven_days_ago = today_start - (6 * 86400);
    let fourteen_days_ago = today_start - (13 * 86400);

    let total_today: i64 = conn
        .query_row(
            "SELECT COALESCE(SUM(ended_at_utc - started_at_utc), 0) FROM usage_intervals WHERE started_at_utc >= ?1",
            [today_start],
            |r| r.get(0),
        )
        .unwrap_or(0);

    let total_7d: i64 = conn
        .query_row(
            "SELECT COALESCE(SUM(ended_at_utc - started_at_utc), 0) FROM usage_intervals WHERE started_at_utc >= ?1",
            [seven_days_ago],
            |r| r.get(0),
        )
        .unwrap_or(0);

    let prev_7d: i64 = conn
        .query_row(
            "SELECT COALESCE(SUM(ended_at_utc - started_at_utc), 0) FROM usage_intervals WHERE started_at_utc >= ?1 AND started_at_utc < ?2",
            [fourteen_days_ago, seven_days_ago],
            |r| r.get(0),
        )
        .unwrap_or(0);

    let comparison_percent = if prev_7d > 0 {
        ((total_7d as f64 - prev_7d as f64) / prev_7d as f64) * 100.0
    } else {
        0.0
    };

    let daily_average_7d = total_7d / 7;

    let day_names = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"];
    let mut daily_breakdown = Vec::new();
    let mut peak_day_label = String::new();
    let mut peak_day_seconds: i64 = 0;

    for i in (0..=6).rev() {
        let d_start = today_start - (i * 86400);
        let d_end = d_start + 86400;

        let consumed: i64 = conn
            .query_row(
                "SELECT COALESCE(SUM(ended_at_utc - started_at_utc), 0) FROM usage_intervals WHERE started_at_utc >= ?1 AND started_at_utc < ?2",
                [d_start, d_end],
                |r| r.get(0),
            )
            .unwrap_or(0);

        let slot_dow = ((dow - i as i32) % 7 + 7) % 7;
        let day_label = if i == 0 {
            "Hoje".to_string()
        } else {
            day_names[slot_dow as usize].to_string()
        };

        let date_str = {
            let stmt = conn.prepare_cached("SELECT strftime('%d/%m', datetime(?1, 'unixepoch', 'localtime'))").ok();
            stmt.and_then(|mut s| s.query_row([d_start], |r| r.get(0)).ok()).unwrap_or_else(|| "".to_string())
        };

        if consumed >= peak_day_seconds {
            peak_day_seconds = consumed;
            peak_day_label = format!("{} ({})", day_label, date_str);
        }

        daily_breakdown.push(DailyUsageItem {
            day_label,
            date_str,
            consumed_seconds: consumed,
            is_today: i == 0,
        });
    }

    if peak_day_seconds == 0 {
        peak_day_label = "Nenhum consumo registrado".to_string();
    }

    let mut top_entities = Vec::new();
    let mut top_stmt = conn.prepare(
        "SELECT u.entity_id, COALESCE(r.display_name, u.entity_id), COALESCE(r.target_type, 'APP'), COALESCE(SUM(u.ended_at_utc - u.started_at_utc), 0) as total
         FROM usage_intervals u
         LEFT JOIN rules r ON u.entity_id = r.entity_id
         WHERE u.started_at_utc >= ?1
         GROUP BY u.entity_id
         ORDER BY total DESC
         LIMIT 5",
    )?;

    let rows = top_stmt.query_map([seven_days_ago], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
            r.get::<_, i64>(3)?,
        ))
    })?;

    for row in rows.flatten() {
        let (eid, dname, ttype, c_secs) = row;
        let percentage = if total_7d > 0 {
            (c_secs as f64 / total_7d as f64) * 100.0
        } else {
            0.0
        };
        top_entities.push(TopEntityItem {
            entity_id: eid,
            display_name: dname,
            target_type: ttype,
            consumed_seconds: c_secs,
            percentage,
        });
    }

    Ok(AnalyticsSummary {
        total_consumed_today_seconds: total_today,
        total_consumed_7d_seconds: total_7d,
        daily_average_7d_seconds: daily_average_7d,
        peak_day_label,
        peak_day_seconds,
        comparison_vs_prev_week_percent: comparison_percent,
        top_entities_7d: top_entities,
        daily_breakdown_7d: daily_breakdown,
    })
}

pub fn get_theme_mode() -> String {
    let conn = get_conn().lock();
    conn.query_row(
        "SELECT value FROM app_config WHERE key = 'theme_mode'",
        [],
        |r| r.get(0),
    )
    .unwrap_or_else(|_| "dark".to_string())
}

pub fn set_theme_mode(mode: &str) -> bool {
    let conn = get_conn().lock();
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;
    conn.execute(
        "INSERT INTO app_config (key, value, updated_at_utc) VALUES ('theme_mode', ?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = ?1, updated_at_utc = ?2",
        (mode, now),
    )
    .is_ok()
}

fn default_true() -> bool {
    true
}

fn default_hud_alpha() -> f64 {
    0.94
}

pub fn clamp_hud_alpha(v: f64) -> f64 {
    if !v.is_finite() {
        0.94
    } else {
        v.clamp(0.15, 1.0)
    }
}

fn default_hud_scale() -> f64 {
    1.0
}

pub fn clamp_hud_scale(v: f64) -> f64 {
    if !v.is_finite() {
        1.0
    } else {
        v.clamp(0.70, 1.60)
    }
}

pub fn normalize_term_list(items: &[String]) -> Vec<String> {
    let mut out = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for raw in items {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            continue;
        }
        let key = trimmed.to_lowercase();
        if seen.insert(key) {
            out.push(trimmed.to_string());
        }
    }
    out
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct FocusFilters {
    // Legado / Global
    #[serde(default)]
    pub block_shorts: bool,
    #[serde(default)]
    pub grayscale_mode: bool,
    #[serde(default)]
    pub educational_only: bool,
    #[serde(default)]
    pub block_feed: bool,
    #[serde(default)]
    pub block_comments: bool,
    #[serde(default)]
    pub block_notifications: bool,

    // YouTube
    #[serde(default = "default_true")]
    pub yt_block_shorts: bool,
    #[serde(default)]
    pub yt_educational_mode: bool,
    #[serde(default)]
    pub yt_block_sidebar: bool,
    #[serde(default)]
    pub yt_block_comments: bool,

    // Instagram
    #[serde(default = "default_true")]
    pub ig_block_reels: bool,
    #[serde(default)]
    pub ig_block_feed: bool,
    #[serde(default)]
    pub ig_block_comments: bool,

    // TikTok
    #[serde(default = "default_true")]
    pub tt_block_feed: bool,

    // Reddit
    #[serde(default)]
    pub rd_block_feed: bool,
    #[serde(default)]
    pub rd_block_comments: bool,

    // Twitter / X
    #[serde(default)]
    pub tw_block_feed: bool,
    #[serde(default)]
    pub tw_block_trends: bool,

    // LinkedIn
    #[serde(default)]
    pub li_block_feed: bool,

    // Global / Detox
    #[serde(default)]
    pub global_grayscale: bool,
    #[serde(default)]
    pub global_block_notifications: bool,

    // HUD Flutuante no navegador
    #[serde(default = "default_hud_alpha")]
    pub hud_alpha: f64,
    #[serde(default = "default_true")]
    pub hud_hide_to_eye: bool,
    #[serde(default = "default_hud_scale")]
    pub hud_scale: f64,

    // Launchers & Lojas de Jogos (Steam API + Launchers Genéricos)
    #[serde(default = "default_true")]
    pub launcher_filter_enabled: bool,
    #[serde(default)]
    pub launcher_blocked_tags: Vec<String>,
    #[serde(default)]
    pub launcher_blocked_names: Vec<String>,
}

impl FocusFilters {
    /// Clears legacy coarse booleans so per-platform toggles cannot leak across
    /// unrelated sites, while keeping the legacy global mirrors synchronized.
    pub fn normalize_legacy(&mut self) {
        self.block_shorts = false;
        self.educational_only = false;
        self.block_feed = false;
        self.block_comments = false;
        self.grayscale_mode = self.global_grayscale;
        self.block_notifications = self.global_block_notifications;
        self.hud_alpha = clamp_hud_alpha(self.hud_alpha);
        self.hud_scale = clamp_hud_scale(self.hud_scale);
        self.launcher_blocked_tags = normalize_term_list(&self.launcher_blocked_tags);
        self.launcher_blocked_names = normalize_term_list(&self.launcher_blocked_names);
    }
}

impl Default for FocusFilters {
    fn default() -> Self {
        Self {
            block_shorts: false,
            grayscale_mode: false,
            educational_only: false,
            block_feed: false,
            block_comments: false,
            block_notifications: false,

            yt_block_shorts: true,
            yt_educational_mode: false,
            yt_block_sidebar: false,
            yt_block_comments: false,

            ig_block_reels: true,
            ig_block_feed: false,
            ig_block_comments: false,

            tt_block_feed: true,

            rd_block_feed: false,
            rd_block_comments: false,

            tw_block_feed: false,
            tw_block_trends: false,

            li_block_feed: false,

            global_grayscale: false,
            global_block_notifications: false,

            hud_alpha: 0.94,
            hud_hide_to_eye: true,
            hud_scale: 1.0,

            launcher_filter_enabled: true,
            launcher_blocked_tags: Vec::new(),
            launcher_blocked_names: Vec::new(),
        }
    }
}

pub fn validate_focus_filters_anti_cheat(
    current: &FocusFilters,
    next: &FocusFilters,
    anti_cheat_active: bool,
) -> Result<(), String> {
    if !anti_cheat_active {
        return Ok(());
    }
    if current.launcher_filter_enabled && !next.launcher_filter_enabled {
        return Err(
            "Modo Anti-Cheat está ativo! Não é possível desativar o filtro de jogos/launchers enquanto o Anti-Cheat estiver ligado."
                .to_string(),
        );
    }
    let next_tags: std::collections::HashSet<String> = next
        .launcher_blocked_tags
        .iter()
        .map(|s| crate::steam_api::canonical_tag_to_english(s).trim().to_lowercase())
        .filter(|s| !s.is_empty())
        .collect();
    for old_tag in &current.launcher_blocked_tags {
        let key = crate::steam_api::canonical_tag_to_english(old_tag)
            .trim()
            .to_lowercase();
        if !key.is_empty() && !next_tags.contains(&key) {
            return Err(format!(
                "Modo Anti-Cheat está ativo! A remoção da tag '{old_tag}' exige desativar o Anti-Cheat primeiro."
            ));
        }
    }
    let next_names: std::collections::HashSet<String> = next
        .launcher_blocked_names
        .iter()
        .map(|s| s.trim().to_lowercase())
        .filter(|s| !s.is_empty())
        .collect();
    for old_name in &current.launcher_blocked_names {
        let key = old_name.trim().to_lowercase();
        if !key.is_empty() && !next_names.contains(&key) {
            return Err(format!(
                "Modo Anti-Cheat está ativo! A remoção de '{old_name}' exige desativar o Anti-Cheat primeiro."
            ));
        }
    }
    Ok(())
}

pub fn get_focus_filters() -> FocusFilters {
    let conn = get_conn().lock();
    let json_str: Result<String, _> = conn.query_row(
        "SELECT value FROM app_config WHERE key = 'focus_filters'",
        [],
        |r| r.get(0),
    );
    let mut filters = match json_str {
        Ok(s) => serde_json::from_str(&s).unwrap_or_default(),
        Err(_) => FocusFilters::default(),
    };
    filters.normalize_legacy();
    filters
}

pub fn set_focus_filters(filters: &FocusFilters) -> bool {
    let mut normalized = filters.clone();
    normalized.normalize_legacy();
    normalized.launcher_blocked_tags =
        crate::steam_api::canonicalize_tags_to_english(&normalized.launcher_blocked_tags);
    let ok = {
        let conn = get_conn().lock();
        let json_str = serde_json::to_string(&normalized).unwrap_or_default();
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;
        conn.execute(
            "INSERT INTO app_config (key, value, updated_at_utc) VALUES ('focus_filters', ?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = ?1, updated_at_utc = ?2",
            (json_str, now),
        )
        .is_ok()
    };
    if ok {
        bump_state_revision();
    }
    ok
}

pub fn set_focus_filters_checked(
    filters: &FocusFilters,
    anti_cheat_active: bool,
) -> Result<FocusFilters, String> {
    let current = get_focus_filters();
    let mut normalized = filters.clone();
    normalized.normalize_legacy();
    normalized.launcher_blocked_tags =
        crate::steam_api::canonicalize_tags_to_english(&normalized.launcher_blocked_tags);
    validate_focus_filters_anti_cheat(&current, &normalized, anti_cheat_active)?;
    if set_focus_filters(&normalized) {
        Ok(normalized)
    } else {
        Err("Falha ao salvar filtros de foco no banco de dados.".to_string())
    }
}
