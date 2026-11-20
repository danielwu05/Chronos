pub mod adult;
pub mod api;
pub mod app_watchdog;
pub mod conflicts;
pub mod db;
pub mod detector;
pub mod engine;
pub mod firefox_updates;
pub mod holidays;
pub mod i18n;
pub mod launchers;
pub mod local_api;
pub mod profile;
pub mod proxy;
pub mod steam_api;
pub mod trusted_time;
pub mod vault;
pub mod youtube;
pub mod nsfw_net;
pub mod screen_guard;
pub mod wrappers;
mod frb_generated;

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::sync::Mutex;

    pub(crate) static TEST_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn test_quarantine_dedupes_and_remembers_reviews() {
        let _guard = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db_file = std::env::temp_dir().join(format!("chronos_quar_{}.db", std::process::id()));
        db::init_db(db_file.to_str().unwrap()).unwrap();
        {
            let conn = db::get_conn().lock();
            conn.execute("DELETE FROM install_quarantine", []).unwrap();
            // Old scans: same AppImage, different mounts, one row per scan.
            for (id, path, st) in [
                ("quar_obs_1", "/tmp/.mount_Obs1aB2c/obsidian", "APPROVED"),
                ("quar_obs_2", "/tmp/.mount_Obs9zZ8y/obsidian", "QUARANTINED"),
                ("quar_obs_3", "/tmp/.mount_Obs7qQ6w/obsidian", "QUARANTINED"),
            ] {
                conn.execute(
                    "INSERT INTO install_quarantine (request_id, app_identifier, display_name, platform, status, requested_at_utc) VALUES (?1, ?2, 'obsidian', 'linux', ?3, 0)",
                    (id, path, st),
                )
                .unwrap();
            }
        }
        // A scan (whatever runs on this machine) dedupes; the reviewed row is kept.
        let items = engine::scan_system_untrusted_processes();
        let obs: Vec<_> = items.iter().filter(|i| i.display_name == "obsidian").collect();
        assert_eq!(obs.len(), 1);
        assert_eq!(obs[0].status, "APPROVED");
        let _ = std::fs::remove_file(db_file);
    }

    #[test]
    fn test_db_lifecycle_and_resets() {
        let _guard = TEST_LOCK.lock().unwrap();
        // Usa arquivo em tmp para os testes unitários
        let temp_dir = std::env::temp_dir();
        let db_file = temp_dir.join(format!("chronos_test_{}.db", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));
        let db_path = db_file.to_str().unwrap();

        assert!(db::init_db(db_path).is_ok());

        // Estatísticas iniciais (sem regras preset automáticas)
        let stats = db::get_database_stats().expect("Stats must load");
        assert_eq!(stats.total_rules, 0, "Nenhuma regra preset deve ser criada automaticamente");
        assert_eq!(stats.emergency_tokens, 2, "Tokens iniciais devem ser 2");

        // Cria uma regra de teste para validar ciclo de vida e catraca
        assert!(engine::save_rule("youtube", "YouTube", 1800, "SELF_CONTROL", "SITE_GROUP", "{\"apps\":[],\"sites\":[\"youtube.com\",\"reels\"]}", None, None).is_ok());

        // Simula travamento da catraca
        assert!(engine::activate_ratchet_lock("youtube", 24));
        let rules_before = engine::get_all_rules();
        let yt = rules_before.iter().find(|r| r.entity_id == "youtube").unwrap();
        assert!(yt.ratchet_locked_until_utc.is_some());

        // Tentar aumentar a cota deve falhar devido à catraca
        let fail_res = engine::update_quota_ratchet("youtube", 99999);
        assert!(!fail_res.success, "Catraca ativa deve bloquear aumento de cota");

        // Reduzir cota deve ser permitido mesmo com catraca
        let ok_res = engine::update_quota_ratchet("youtube", 100);
        assert!(ok_res.success, "Redução de cota deve ser permitida");

        // Destravar catraca (Modo debug / teste)
        assert!(db::debug_unlock_ratchet("youtube").is_ok());
        let unblocked_res = engine::update_quota_ratchet("youtube", 5000);
        assert!(unblocked_res.success, "Após destravar, aumento deve ser permitido");

        // Consumir token de emergência
        let token_res = engine::use_emergency_token("youtube");
        assert!(token_res.success);
        let stats_after_token = db::get_database_stats().unwrap();
        assert_eq!(stats_after_token.emergency_tokens, 1);

        // Recarregar tokens
        assert!(db::refill_emergency_tokens().is_ok());
        let stats_refill = db::get_database_stats().unwrap();
        assert_eq!(stats_refill.emergency_tokens, 2);

        // Valida get_all_site_rules_status sem deadlock concorrente
        assert!(engine::save_rule("site_test", "Site Test", 1200, "SELF_CONTROL", "SITE", "example.com", None, None).is_ok());
        assert!(db::save_whitelist_group("wl_test", "Whitelist Test", "example.com,spotify").is_ok());
        let statuses = engine::get_all_site_rules_status();
        assert!(!statuses.is_empty(), "Status das regras deve carregar sem deadlock");

        // Reset completo do banco
        assert!(db::reset_database_full().is_ok());
        let stats_reset = db::get_database_stats().unwrap();
        assert_eq!(stats_reset.total_intervals, 0);
        assert_eq!(stats_reset.emergency_tokens, 2);

        // Limpa arquivo de teste
        let _ = std::fs::remove_file(db_file);
    }

    #[test]
    fn test_list_installed_apps() {
        let start = std::time::Instant::now();
        let apps = engine::list_installed_desktop_apps();
        println!("Found {} apps in {:?}", apps.len(), start.elapsed());
    }

    #[test]
    fn test_group_rich_apps_and_whitelist() {
        let _guard = TEST_LOCK.lock().unwrap();
        let pattern = r#"{"apps":[{"name":"Counter-Strike 2","exec":"steam"},{"name":"Discord","exec":"discord"}],"sites":["youtube.com","reels"]}"#;
        let (apps, sites) = engine::parse_group_pattern_rich(pattern);
        assert_eq!(apps.len(), 2);
        assert_eq!(apps[0].name, "Counter-Strike 2");
        assert_eq!(apps[0].exec, "steam");
        assert!(apps[0].is_launcher());
        assert!(!apps[1].is_launcher());
        assert_eq!(sites.len(), 2);
        assert_eq!(sites[0], "youtube.com");
        assert_eq!(sites[1], "reels");

        // Whitelist estruturada
        let temp_dir = std::env::temp_dir();
        let db_file = temp_dir.join(format!("chronos_wl_test_{}.db", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));
        assert!(db::init_db(db_file.to_str().unwrap()).is_ok());

        assert!(db::save_whitelist_group("wl_study", "Estudos", pattern).is_ok());
        let wl_groups = db::get_all_whitelist_groups();
        assert_eq!(wl_groups.len(), 1);
        assert!(db::is_item_in_whitelist_groups(&wl_groups, "Counter-Strike 2"));
        assert!(db::is_item_in_whitelist_groups(&wl_groups, "discord"));
        assert!(db::is_item_in_whitelist_groups(&wl_groups, "youtube.com"));
        assert!(!db::is_item_in_whitelist_groups(&wl_groups, "facebook.com"));

        let _ = std::fs::remove_file(db_file);
    }

    #[test]
    fn test_analytics_and_theme_mode() {
        let _guard = TEST_LOCK.lock().unwrap();
        let temp_dir = std::env::temp_dir();
        let db_file = temp_dir.join(format!("chronos_analytics_test_{}.db", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));
        let db_path = db_file.to_str().unwrap();

        assert!(db::init_db(db_path).is_ok());

        // Test theme mode defaults to dark and toggles correctly
        assert_eq!(db::get_theme_mode(), "dark");
        assert!(db::set_theme_mode("light"));
        assert_eq!(db::get_theme_mode(), "light");
        assert!(db::set_theme_mode("system"));
        assert_eq!(db::get_theme_mode(), "system");

        // Test analytics summary (empty DB initial state)
        let summary = db::get_analytics_summary().expect("Analytics summary should load");
        assert_eq!(summary.total_consumed_today_seconds, 0);
        assert_eq!(summary.total_consumed_7d_seconds, 0);
        assert_eq!(summary.daily_breakdown_7d.len(), 7);
        assert!(summary.top_entities_7d.is_empty());

        let _ = std::fs::remove_file(db_file);
    }

    #[test]
    fn test_focus_filters_persistence() {
        let _guard = TEST_LOCK.lock().unwrap();
        let temp_dir = std::env::temp_dir();
        let db_file = temp_dir.join(format!("chronos_filters_test_{}.db", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));
        let db_path = db_file.to_str().unwrap();

        assert!(db::init_db(db_path).is_ok());

        // Default: yt_block_shorts / ig_block_reels / tt_block_feed = true; legacy coarse flags = false
        let initial = db::get_focus_filters();
        assert!(!initial.block_shorts);
        assert!(initial.yt_block_shorts);
        assert!(initial.ig_block_reels);
        assert!(initial.tt_block_feed);
        assert!(!initial.grayscale_mode);
        assert!(!initial.global_grayscale);

        // Update filters and verify legacy coarse contamination is normalized away
        let mut updated = db::FocusFilters::default();
        updated.block_shorts = true;
        updated.grayscale_mode = false;
        updated.educational_only = true;
        updated.block_feed = true;
        updated.block_comments = true;
        updated.block_notifications = false;
        updated.yt_block_shorts = true;
        updated.yt_educational_mode = true;
        updated.ig_block_reels = true;
        updated.tt_block_feed = true;
        updated.rd_block_feed = true;
        updated.tw_block_feed = true;
        updated.li_block_feed = true;
        updated.global_grayscale = true;
        updated.global_block_notifications = true;
        updated.hud_scale = 2.4; // Clamped to 1.60
        updated.launcher_filter_enabled = true;
        updated.launcher_blocked_tags = vec![
            "Action".to_string(),
            "  ação ".to_string(),
            "Soulslike".to_string(),
        ];
        updated.launcher_blocked_names = vec!["Counter-Strike".to_string(), "counter-strike".to_string()];
        assert!(db::set_focus_filters(&updated));

        let loaded = db::get_focus_filters();
        assert!(!loaded.block_shorts);
        assert!(loaded.grayscale_mode);
        assert!(!loaded.educational_only);
        assert!(!loaded.block_feed);
        assert!(!loaded.block_comments);
        assert!(loaded.block_notifications);
        assert!(loaded.yt_block_shorts);
        assert!(loaded.yt_educational_mode);
        assert!(loaded.ig_block_reels);
        assert!(loaded.tt_block_feed);
        assert!(loaded.rd_block_feed);
        assert!(loaded.tw_block_feed);
        assert!(loaded.li_block_feed);
        assert!(loaded.global_grayscale);
        assert!(loaded.global_block_notifications);
        assert!((loaded.hud_scale - 1.6).abs() < 1e-6);
        assert!(loaded.launcher_filter_enabled);
        // Both "Action" and "ação" canonicalize to "Action" and deduplicate to 1 canonical entry; "Soulslike" canonicalizes to Steam's "Souls-like"
        assert_eq!(loaded.launcher_blocked_names, vec!["Counter-Strike".to_string()]);
        assert_eq!(
            loaded.launcher_blocked_tags,
            vec!["Action".to_string(), "Souls-like".to_string()]
        );

        // Verify primary language persistence & revision bump
        assert_eq!(db::get_primary_language(), "pt-BR");
        assert!(db::set_primary_language("en-US").is_ok());
        assert_eq!(db::get_primary_language(), "en-US");
        assert_eq!(db::normalize_primary_language("zh_TW"), "zh-Hant");
        assert_eq!(db::normalize_primary_language("zh-Hant"), "zh-Hant");
        assert_eq!(db::normalize_primary_language("zh_CN.UTF-8"), "zh-Hans");
        assert_eq!(db::normalize_primary_language("zh-Hans"), "zh-Hans");
        assert_eq!(db::get_steam_language_and_country(), ("english", "US"));
        assert!(db::set_primary_language("pt-BR").is_ok());
        assert_eq!(db::get_steam_language_and_country(), ("brazilian", "BR"));

        // Anti-Burla lock: adding rules is allowed when active; removing tags/names or turning OFF is blocked
        let mut with_extra = loaded.clone();
        with_extra.launcher_blocked_tags.push("FPS".to_string());
        with_extra.launcher_blocked_names.push("Dota 2".to_string());
        assert!(db::set_focus_filters_checked(&with_extra, true).is_ok());

        // Sending "Ação" instead of "Action" under Anti-Burla still maps to canonical "Action" and is allowed
        let mut localized_equiv = db::get_focus_filters();
        localized_equiv.launcher_blocked_tags = vec![
            "Ação".to_string(),
            "Souls-like".to_string(),
            "FPS".to_string(),
        ];
        assert!(db::set_focus_filters_checked(&localized_equiv, true).is_ok());

        let mut remove_tag = db::get_focus_filters();
        remove_tag.launcher_blocked_tags.retain(|t| t != "FPS");
        assert!(db::set_focus_filters_checked(&remove_tag, true).is_err());

        let mut remove_name = db::get_focus_filters();
        remove_name.launcher_blocked_names.retain(|n| n != "Dota 2");
        assert!(db::set_focus_filters_checked(&remove_name, true).is_err());

        let mut turn_off = db::get_focus_filters();
        turn_off.launcher_filter_enabled = false;
        assert!(db::set_focus_filters_checked(&turn_off, true).is_err());

        // Allowed when Anti-Burla is inactive
        assert!(db::set_focus_filters_checked(&remove_tag, false).is_ok());
        assert!(db::set_focus_filters_checked(&turn_off, false).is_ok());

        // Verify SQLite Steam metadata cache roundtrip
        let sample_meta = steam_api::GameMetadata {
            app_id: Some(730),
            title: "Counter-Strike 2".to_string(),
            tags: vec!["FPS".to_string(), "Multiplayer".to_string()],
            genres: vec!["Action".to_string()],
            categories: vec![],
            source: "test".to_string(),
        };
        steam_api::save_cached_metadata("appid:730", &sample_meta);
        let cached = steam_api::lookup_cached_only(Some(730), "Counter-Strike 2").expect("cache hit");
        assert_eq!(cached.title, "Counter-Strike 2");
        assert!(cached.tags.contains(&"FPS".to_string()));

        let _ = std::fs::remove_file(db_file);
    }
}
