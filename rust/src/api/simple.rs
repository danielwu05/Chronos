use crate::db;
use crate::engine;
use crate::frb_generated::StreamSink;
use std::io::Write;
use std::net::{SocketAddr, TcpStream};
use std::thread;
use std::time::Duration;

fn trigger_daemon_nudge() {
    crate::local_api::notify_state_changed();
    thread::spawn(|| {
        let addr: SocketAddr = "127.0.0.1:4545".parse().unwrap();
        if let Ok(mut stream) = TcpStream::connect_timeout(&addr, Duration::from_millis(120)) {
            let _ = stream.set_write_timeout(Some(Duration::from_millis(120)));
            let _ = stream.write_all(
                b"POST /api/nudge HTTP/1.1\r\nHost: 127.0.0.1:4545\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
            );
            let _ = stream.flush();
        }
    });
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

pub struct EngineStatus {
    pub platform: String,
    pub is_daemon_running: bool,
    pub current_timestamp_utc: i64,
}

pub fn get_engine_status() -> EngineStatus {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;

    EngineStatus {
        platform: std::env::consts::OS.to_string(),
        is_daemon_running: true,
        current_timestamp_utc: now,
    }
}

pub fn setup_database(app_data_dir: String) -> bool {
    let db_path = format!("{}/chronos.db", app_data_dir);
    let ok = db::init_db(&db_path).is_ok();
    if ok {
        crate::proxy::ensure_proxy_running();
        std::thread::spawn(|| {
            std::thread::sleep(std::time::Duration::from_millis(900));
            let _ = crate::launchers::sync_launcher_proxy_if_configured();
        });
    }
    ok
}

// ----------------- ONBOARDING E PAREAMENTO -----------------

pub struct OnboardingStateDto {
    pub is_onboarded: bool,
    pub app_mode: String,
    pub device_role: String,
    pub device_id: String,
    pub pairing_code: String,
    pub is_paired: bool,
    pub pairing_payload_qr: String,
}

pub fn get_onboarding_state() -> OnboardingStateDto {
    match db::get_onboarding_state() {
        Ok(state) => OnboardingStateDto {
            is_onboarded: state.is_onboarded,
            app_mode: state.app_mode,
            device_role: state.device_role,
            device_id: state.device_id,
            pairing_code: state.pairing_code,
            is_paired: state.is_paired,
            pairing_payload_qr: state.pairing_payload_qr,
        },
        Err(_) => OnboardingStateDto {
            is_onboarded: false,
            app_mode: "SELF_CONTROL".to_string(),
            device_role: "NONE".to_string(),
            device_id: "DEV-0001".to_string(),
            pairing_code: "CHR-1000".to_string(),
            is_paired: false,
            pairing_payload_qr: "".to_string(),
        },
    }
}

pub fn save_onboarding_choice(
    app_mode: String,
    device_role: String,
    pairing_secret: Option<String>,
) -> ActionFeedback {
    match db::save_onboarding_choice(&app_mode, &device_role, pairing_secret.as_deref()) {
        Ok(_) => ActionFeedback {
            success: true,
            message: "Configuração inicial concluída com sucesso!".to_string(),
        },
        Err(e) => ActionFeedback {
            success: false,
            message: format!("Erro ao salvar configuração: {}", e),
        },
    }
}

pub fn verify_and_pair_device(code_or_password: String) -> ActionFeedback {
    match db::pair_device(&code_or_password) {
        Ok(true) => ActionFeedback {
            success: true,
            message: "Dispositivo pareado com sucesso!".to_string(),
        },
        Ok(false) => ActionFeedback {
            success: false,
            message: "Código ou senha de pareamento incorretos.".to_string(),
        },
        Err(e) => ActionFeedback {
            success: false,
            message: format!("Erro ao processar pareamento: {}", e),
        },
    }
}

pub fn reset_onboarding_state() -> ActionFeedback {
    match db::reset_onboarding_state() {
        Ok(_) => ActionFeedback {
            success: true,
            message: "Onboarding reiniciado! A tela de configuração será exibida no próximo início.".to_string(),
        },
        Err(e) => ActionFeedback {
            success: false,
            message: format!("Erro ao reiniciar onboarding: {}", e),
        },
    }
}

pub struct LiveEngineTick {
    pub entity_id: String,
    pub display_name: String,
    pub remaining_seconds: i64,
    pub daily_quota_seconds: i64,
    pub consumed_seconds: i64,
    pub is_active_now: bool,
    pub is_background_playback: bool,
    pub is_blocked: bool,
    pub detected_activity_label: String,
    pub ratchet_locked_until_utc: Option<i64>,
    pub emergency_tokens_remaining: i64,
    pub leisure_locked_until_utc: i64,
    pub target_type: String,
    pub is_weekend: bool,
    pub weekend_quota_seconds: Option<i64>,
    pub active_sessions_json: String,
}

static TRACKING_STREAM_ID: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

pub fn start_tracking_stream(sink: StreamSink<LiveEngineTick>, entity_id: String) {
    let current_id = TRACKING_STREAM_ID.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1;
    thread::spawn(move || {
        while TRACKING_STREAM_ID.load(std::sync::atomic::Ordering::SeqCst) == current_id {
            let ent_id = entity_id.clone();
            let tick_res = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                if ent_id.is_empty() || ent_id == "auto" {
                    engine::tick_auto()
                } else {
                    engine::tick_entity(&ent_id).or_else(|| engine::tick_auto())
                }
            }));

            let maybe_tick = match tick_res {
                Ok(opt) => opt,
                Err(err) => {
                    eprintln!("Chronos tracking loop transient panic caught: {:?}", err);
                    None
                }
            };

            if let Some(tick) = maybe_tick {
                let event = LiveEngineTick {
                    entity_id: tick.entity_id,
                    display_name: tick.display_name,
                    remaining_seconds: tick.remaining_seconds,
                    daily_quota_seconds: tick.daily_quota_seconds,
                    consumed_seconds: tick.consumed_seconds,
                    is_active_now: tick.is_active_now,
                    is_background_playback: tick.is_background_playback,
                    is_blocked: tick.is_blocked,
                    detected_activity_label: tick.detected_activity_label,
                    ratchet_locked_until_utc: tick.ratchet_locked_until_utc,
                    emergency_tokens_remaining: tick.emergency_tokens_remaining,
                    leisure_locked_until_utc: tick.leisure_locked_until_utc,
                    target_type: tick.target_type,
                    is_weekend: tick.is_weekend,
                    weekend_quota_seconds: tick.weekend_quota_seconds,
                    active_sessions_json: tick.active_sessions_json,
                };

                if sink.add(event).is_err() {
                    break;
                }
            }
            thread::sleep(Duration::from_secs(1));
        }
    });
}

pub struct ActionFeedback {
    pub success: bool,
    pub message: String,
}

pub fn change_quota(entity_id: String, new_quota_seconds: i64) -> ActionFeedback {
    let res = engine::update_quota_ratchet(&entity_id, new_quota_seconds);
    if res.success {
        trigger_daemon_nudge();
    }
    ActionFeedback {
        success: res.success,
        message: res.message,
    }
}

pub fn lock_ratchet(entity_id: String, hours: i64) -> bool {
    let ok = engine::activate_ratchet_lock(&entity_id, hours);
    if ok {
        trigger_daemon_nudge();
    }
    ok
}

pub fn consume_emergency_token(entity_id: String) -> ActionFeedback {
    let res = engine::use_emergency_token(&entity_id);
    if res.success {
        trigger_daemon_nudge();
    }
    ActionFeedback {
        success: res.success,
        message: res.message,
    }
}

// ----------------- OPERAÇÕES DE BANCO DE DADOS (TESTES E MANUTENÇÃO) -----------------

pub struct DatabaseStatsDto {
    pub total_rules: i64,
    pub total_intervals: i64,
    pub total_quarantine_items: i64,
    pub emergency_tokens: i64,
}

pub fn reset_database_full() -> ActionFeedback {
    match db::reset_database_full() {
        Ok(_) => ActionFeedback {
            success: true,
            message: "Banco de dados reiniciado com sucesso! Regras e tokens restaurados.".to_string(),
        },
        Err(e) => ActionFeedback {
            success: false,
            message: format!("Erro ao reiniciar banco: {}", e),
        },
    }
}

pub fn reset_daily_usage(entity_id: Option<String>) -> ActionFeedback {
    match db::reset_daily_usage(entity_id.as_deref()) {
        Ok(_) => ActionFeedback {
            success: true,
            message: "Consumo diário zerado com sucesso! Cota renovada.".to_string(),
        },
        Err(e) => ActionFeedback {
            success: false,
            message: format!("Erro ao zerar consumo diário: {}", e),
        },
    }
}

pub fn debug_unlock_ratchet(entity_id: String) -> ActionFeedback {
    match db::debug_unlock_ratchet(&entity_id) {
        Ok(_) => ActionFeedback {
            success: true,
            message: format!("Catraca da entidade '{}' destravada com sucesso!", entity_id),
        },
        Err(e) => ActionFeedback {
            success: false,
            message: format!("Erro ao destravar catraca: {}", e),
        },
    }
}

pub fn refill_emergency_tokens() -> ActionFeedback {
    match db::refill_emergency_tokens() {
        Ok(_) => ActionFeedback {
            success: true,
            message: "Tokens de emergência restaurados para 2!".to_string(),
        },
        Err(e) => ActionFeedback {
            success: false,
            message: format!("Erro ao recarregar tokens: {}", e),
        },
    }
}

pub fn get_database_stats() -> DatabaseStatsDto {
    match db::get_database_stats() {
        Ok(stats) => DatabaseStatsDto {
            total_rules: stats.total_rules,
            total_intervals: stats.total_intervals,
            total_quarantine_items: stats.total_quarantine_items,
            emergency_tokens: stats.emergency_tokens,
        },
        Err(_) => DatabaseStatsDto {
            total_rules: 0,
            total_intervals: 0,
            total_quarantine_items: 0,
            emergency_tokens: 0,
        },
    }
}

// ----------------- GERENCIAMENTO DE REGRAS & ANTI-CHEAT -----------------

pub struct AntiCheatStateDto {
    pub is_active: bool,
    pub mode: String, // "OFF", "CHALLENGE", "NUKE"
    pub nuke_remaining_seconds: i64,
    pub challenge_text: String,
}

pub fn get_anti_cheat_state() -> AntiCheatStateDto {
    let s = engine::get_anti_cheat_state();
    AntiCheatStateDto {
        is_active: s.is_active,
        mode: s.mode,
        nuke_remaining_seconds: s.nuke_remaining_seconds,
        challenge_text: s.challenge_text,
    }
}

pub fn enable_anti_cheat(mode: String, nuke_seconds: Option<i64>) -> ActionFeedback {
    match engine::enable_anti_cheat(&mode, nuke_seconds) {
        Ok(_) => {
            trigger_daemon_nudge();
            ActionFeedback {
                success: true,
                message: if mode == "NUKE" {
                    "Modo Nuclear ativado! Nenhuma regra pode ser modificada até o tempo expirar.".to_string()
                } else {
                    "Modo Anti-Cheat ativado! Para desativar, conclua o desafio de digitação estrito.".to_string()
                },
            }
        }
        Err(e) => ActionFeedback {
            success: false,
            message: e,
        },
    }
}

pub fn disable_anti_cheat(verification_token: String) -> ActionFeedback {
    match engine::disable_anti_cheat(&verification_token) {
        Ok(_) => {
            trigger_daemon_nudge();
            ActionFeedback {
                success: true,
                message: "Modo Anti-Cheat desativado com sucesso!".to_string(),
            }
        }
        Err(e) => ActionFeedback {
            success: false,
            message: e,
        },
    }
}

pub struct InstalledAppDto {
    pub id: String,
    pub name: String,
    pub exec: String,
    pub icon_name: String,
    pub icon_path: String,
}

pub fn get_installed_applications() -> Vec<InstalledAppDto> {
    engine::list_installed_desktop_apps()
        .into_iter()
        .map(|a| InstalledAppDto {
            id: a.id,
            name: a.name,
            exec: a.exec,
            icon_name: a.icon_name,
            icon_path: a.icon_path,
        })
        .collect()
}

pub struct RuleItemDto {
    pub entity_id: String,
    pub display_name: String,
    pub daily_quota_seconds: i64,
    pub is_blocked_completely: bool,
    pub mode: String,
    pub ratchet_locked_until_utc: Option<i64>,
    pub updated_at_utc: i64,
    pub target_type: String,
    pub pattern: String,
    pub weekend_quota_seconds: Option<i64>,
    pub schedule_json: Option<String>,
}

pub struct SiteStatusDto {
    pub entity_id: String,
    pub display_name: String,
    pub target_type: String,
    pub pattern: String,
    pub daily_quota_seconds: i64,
    pub consumed_seconds: i64,
    pub remaining_seconds: i64,
    pub is_blocked: bool,
    pub emergency_tokens_remaining: i64,
    pub is_weekend: bool,
    pub weekend_quota_seconds: Option<i64>,
}

pub fn get_all_rules() -> Vec<RuleItemDto> {
    engine::get_all_rules()
        .into_iter()
        .map(|r| RuleItemDto {
            entity_id: r.entity_id,
            display_name: r.display_name,
            daily_quota_seconds: r.daily_quota_seconds,
            is_blocked_completely: r.is_blocked_completely,
            mode: r.mode,
            ratchet_locked_until_utc: r.ratchet_locked_until_utc,
            updated_at_utc: r.updated_at_utc,
            target_type: r.target_type,
            pattern: r.pattern,
            weekend_quota_seconds: r.weekend_quota_seconds,
            schedule_json: r.schedule_json,
        })
        .collect()
}

pub fn get_all_site_rules_status() -> Vec<SiteStatusDto> {
    engine::get_all_site_rules_status()
        .into_iter()
        .map(|s| SiteStatusDto {
            entity_id: s.entity_id,
            display_name: s.display_name,
            target_type: s.target_type,
            pattern: s.pattern,
            daily_quota_seconds: s.daily_quota_seconds,
            consumed_seconds: s.consumed_seconds,
            remaining_seconds: s.remaining_seconds,
            is_blocked: s.is_blocked,
            emergency_tokens_remaining: s.emergency_tokens_remaining,
            is_weekend: s.is_weekend,
            weekend_quota_seconds: s.weekend_quota_seconds,
        })
        .collect()
}

pub fn save_rule(
    entity_id: String,
    display_name: String,
    daily_quota_seconds: i64,
    mode: String,
    target_type: String,
    pattern: String,
    weekend_quota_seconds: Option<i64>,
    schedule_json: Option<String>,
) -> ActionFeedback {
    match engine::save_rule(
        &entity_id,
        &display_name,
        daily_quota_seconds,
        &mode,
        &target_type,
        &pattern,
        weekend_quota_seconds,
        schedule_json.as_deref(),
    ) {
        Ok(_) => {
            trigger_daemon_nudge();
            ActionFeedback {
                success: true,
                message: format!("Regra '{}' salva com sucesso!", display_name),
            }
        }
        Err(e) => ActionFeedback {
            success: false,
            message: format!("Erro ao salvar regra: {}", e),
        },
    }
}

pub fn delete_rule(entity_id: String) -> ActionFeedback {
    match engine::delete_rule(&entity_id) {
        Ok(_) => {
            trigger_daemon_nudge();
            ActionFeedback {
                success: true,
                message: format!("Regra '{}' removida com sucesso!", entity_id),
            }
        }
        Err(e) => ActionFeedback {
            success: false,
            message: format!("Erro ao remover regra: {}", e),
        },
    }
}

pub fn toggle_entity_block(entity_id: String, blocked: bool) -> ActionFeedback {
    match engine::toggle_entity_block(&entity_id, blocked) {
        Ok(_) => {
            trigger_daemon_nudge();
            ActionFeedback {
                success: true,
                message: if blocked {
                    format!("Entidade '{}' bloqueada completamente!", entity_id)
                } else {
                    format!("Bloqueio total de '{}' desativado!", entity_id)
                },
            }
        }
        Err(e) => ActionFeedback {
            success: false,
            message: format!("Erro ao atualizar bloqueio: {}", e),
        },
    }
}

// ----------------- QUARENTENA E INTEGRIDADE DE PROCESSOS -----------------

pub struct QuarantineItemDto {
    pub request_id: String,
    pub app_identifier: String,
    pub display_name: String,
    pub platform: String,
    pub status: String,
    pub requested_at_utc: i64,
}

pub fn get_quarantine_items() -> Vec<QuarantineItemDto> {
    engine::get_quarantine_items()
        .into_iter()
        .map(|q| QuarantineItemDto {
            request_id: q.request_id,
            app_identifier: q.app_identifier,
            display_name: q.display_name,
            platform: q.platform,
            status: q.status,
            requested_at_utc: q.requested_at_utc,
        })
        .collect()
}

pub fn debug_disable_anti_cheat() -> ActionFeedback {
    match engine::debug_disable_anti_cheat() {
        Ok(_) => {
            trigger_daemon_nudge();
            ActionFeedback {
                success: true,
                message: "Anti-Cheat desativado com sucesso (Modo Debug)!".to_string(),
            }
        }
        Err(e) => ActionFeedback {
            success: false,
            message: format!("Erro ao desativar Anti-Cheat: {}", e),
        },
    }
}

pub struct WhitelistGroupDto {
    pub group_id: String,
    pub display_name: String,
    pub items: String,
    pub created_at_utc: i64,
}

pub fn get_all_whitelist_groups() -> Vec<WhitelistGroupDto> {
    db::get_all_whitelist_groups()
        .into_iter()
        .map(|g| WhitelistGroupDto {
            group_id: g.group_id,
            display_name: g.display_name,
            items: g.items,
            created_at_utc: g.created_at_utc,
        })
        .collect()
}

pub fn save_whitelist_group(group_id: String, display_name: String, items: String) -> ActionFeedback {
    match db::save_whitelist_group(&group_id, &display_name, &items) {
        Ok(_) => {
            trigger_daemon_nudge();
            ActionFeedback {
                success: true,
                message: format!("Grupo de Lista Branca '{}' salvo com sucesso!", display_name),
            }
        }
        Err(e) => ActionFeedback {
            success: false,
            message: format!("Erro ao salvar Grupo de Lista Branca: {}", e),
        },
    }
}

pub fn delete_whitelist_group(group_id: String) -> ActionFeedback {
    match db::delete_whitelist_group(&group_id) {
        Ok(_) => {
            trigger_daemon_nudge();
            ActionFeedback {
                success: true,
                message: "Grupo de Lista Branca removido com sucesso!".to_string(),
            }
        }
        Err(e) => ActionFeedback {
            success: false,
            message: format!("Erro ao remover Grupo de Lista Branca: {}", e),
        },
    }
}

pub fn review_quarantine_item(request_id: String, approved: bool) -> ActionFeedback {
    match engine::review_quarantine(&request_id, approved) {
        Ok(_) => ActionFeedback {
            success: true,
            message: if approved {
                "Item de quarentena APROVADO para execução.".to_string()
            } else {
                "Item de quarentena REJEITADO e bloqueado.".to_string()
            },
        },
        Err(e) => ActionFeedback {
            success: false,
            message: format!("Erro ao revisar quarentena: {}", e),
        },
    }
}

pub fn scan_system_processes() -> Vec<QuarantineItemDto> {
    engine::scan_system_untrusted_processes()
        .into_iter()
        .map(|q| QuarantineItemDto {
            request_id: q.request_id,
            app_identifier: q.app_identifier,
            display_name: q.display_name,
            platform: q.platform,
            status: q.status,
            requested_at_utc: q.requested_at_utc,
        })
        .collect()
}

// ----------------- ESTATÍSTICAS E TEMA -----------------

pub struct TopEntityDto {
    pub entity_id: String,
    pub display_name: String,
    pub target_type: String,
    pub consumed_seconds: i64,
    pub percentage: f64,
}

pub struct DailyUsageDto {
    pub day_label: String,
    pub date_str: String,
    pub consumed_seconds: i64,
    pub is_today: bool,
}

pub struct AnalyticsSummaryDto {
    pub total_consumed_today_seconds: i64,
    pub total_consumed_7d_seconds: i64,
    pub daily_average_7d_seconds: i64,
    pub peak_day_label: String,
    pub peak_day_seconds: i64,
    pub comparison_vs_prev_week_percent: f64,
    pub top_entities_7d: Vec<TopEntityDto>,
    pub daily_breakdown_7d: Vec<DailyUsageDto>,
}

pub fn get_analytics_summary() -> AnalyticsSummaryDto {
    match db::get_analytics_summary() {
        Ok(s) => AnalyticsSummaryDto {
            total_consumed_today_seconds: s.total_consumed_today_seconds,
            total_consumed_7d_seconds: s.total_consumed_7d_seconds,
            daily_average_7d_seconds: s.daily_average_7d_seconds,
            peak_day_label: s.peak_day_label,
            peak_day_seconds: s.peak_day_seconds,
            comparison_vs_prev_week_percent: s.comparison_vs_prev_week_percent,
            top_entities_7d: s
                .top_entities_7d
                .into_iter()
                .map(|t| TopEntityDto {
                    entity_id: t.entity_id,
                    display_name: t.display_name,
                    target_type: t.target_type,
                    consumed_seconds: t.consumed_seconds,
                    percentage: t.percentage,
                })
                .collect(),
            daily_breakdown_7d: s
                .daily_breakdown_7d
                .into_iter()
                .map(|d| DailyUsageDto {
                    day_label: d.day_label,
                    date_str: d.date_str,
                    consumed_seconds: d.consumed_seconds,
                    is_today: d.is_today,
                })
                .collect(),
        },
        Err(_) => AnalyticsSummaryDto {
            total_consumed_today_seconds: 0,
            total_consumed_7d_seconds: 0,
            daily_average_7d_seconds: 0,
            peak_day_label: "Sem dados".to_string(),
            peak_day_seconds: 0,
            comparison_vs_prev_week_percent: 0.0,
            top_entities_7d: Vec::new(),
            daily_breakdown_7d: Vec::new(),
        },
    }
}

pub fn get_theme_mode() -> String {
    db::get_theme_mode()
}

pub fn set_theme_mode(mode: String) -> ActionFeedback {
    if db::set_theme_mode(&mode) {
        ActionFeedback {
            success: true,
            message: format!("Tema alterado para '{}'.", mode),
        }
    } else {
        ActionFeedback {
            success: false,
            message: "Falha ao salvar preferência de tema no banco.".to_string(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct FocusFiltersDto {
    pub block_shorts: bool,
    pub grayscale_mode: bool,
    pub educational_only: bool,
    pub block_feed: bool,
    pub block_comments: bool,
    pub block_notifications: bool,

    // YouTube
    pub yt_block_shorts: bool,
    pub yt_educational_mode: bool,
    pub yt_block_sidebar: bool,
    pub yt_block_comments: bool,

    // Instagram
    pub ig_block_reels: bool,
    pub ig_block_feed: bool,
    pub ig_block_comments: bool,

    // TikTok
    pub tt_block_feed: bool,

    // Reddit
    pub rd_block_feed: bool,
    pub rd_block_comments: bool,

    // Twitter / X
    pub tw_block_feed: bool,
    pub tw_block_trends: bool,

    // LinkedIn
    pub li_block_feed: bool,

    // Global
    pub global_grayscale: bool,
    pub global_block_notifications: bool,

    // HUD Flutuante no navegador
    pub hud_alpha: f64,
    pub hud_hide_to_eye: bool,
    pub hud_scale: f64,

    // Launchers & Lojas de Jogos (Steam API + Launchers Genéricos)
    pub launcher_filter_enabled: bool,
    pub launcher_blocked_tags: Vec<String>,
    pub launcher_blocked_names: Vec<String>,
}

pub fn get_focus_filters() -> FocusFiltersDto {
    let f = db::get_focus_filters();
    FocusFiltersDto {
        block_shorts: f.block_shorts,
        grayscale_mode: f.grayscale_mode,
        educational_only: f.educational_only,
        block_feed: f.block_feed,
        block_comments: f.block_comments,
        block_notifications: f.block_notifications,

        yt_block_shorts: f.yt_block_shorts,
        yt_educational_mode: f.yt_educational_mode,
        yt_block_sidebar: f.yt_block_sidebar,
        yt_block_comments: f.yt_block_comments,

        ig_block_reels: f.ig_block_reels,
        ig_block_feed: f.ig_block_feed,
        ig_block_comments: f.ig_block_comments,

        tt_block_feed: f.tt_block_feed,

        rd_block_feed: f.rd_block_feed,
        rd_block_comments: f.rd_block_comments,

        tw_block_feed: f.tw_block_feed,
        tw_block_trends: f.tw_block_trends,

        li_block_feed: f.li_block_feed,

        global_grayscale: f.global_grayscale,
        global_block_notifications: f.global_block_notifications,

        hud_alpha: db::clamp_hud_alpha(f.hud_alpha),
        hud_hide_to_eye: f.hud_hide_to_eye,
        hud_scale: db::clamp_hud_scale(f.hud_scale),

        launcher_filter_enabled: f.launcher_filter_enabled,
        launcher_blocked_tags: f.launcher_blocked_tags,
        launcher_blocked_names: f.launcher_blocked_names,
    }
}

pub fn set_focus_filters(filters: FocusFiltersDto) -> ActionFeedback {
    let native = db::FocusFilters {
        block_shorts: filters.block_shorts,
        grayscale_mode: filters.grayscale_mode,
        educational_only: filters.educational_only,
        block_feed: filters.block_feed,
        block_comments: filters.block_comments,
        block_notifications: filters.block_notifications,

        yt_block_shorts: filters.yt_block_shorts,
        yt_educational_mode: filters.yt_educational_mode,
        yt_block_sidebar: filters.yt_block_sidebar,
        yt_block_comments: filters.yt_block_comments,

        ig_block_reels: filters.ig_block_reels,
        ig_block_feed: filters.ig_block_feed,
        ig_block_comments: filters.ig_block_comments,

        tt_block_feed: filters.tt_block_feed,

        rd_block_feed: filters.rd_block_feed,
        rd_block_comments: filters.rd_block_comments,

        tw_block_feed: filters.tw_block_feed,
        tw_block_trends: filters.tw_block_trends,

        li_block_feed: filters.li_block_feed,

        global_grayscale: filters.global_grayscale,
        global_block_notifications: filters.global_block_notifications,

        hud_alpha: db::clamp_hud_alpha(filters.hud_alpha),
        hud_hide_to_eye: filters.hud_hide_to_eye,
        hud_scale: db::clamp_hud_scale(filters.hud_scale),

        launcher_filter_enabled: filters.launcher_filter_enabled,
        launcher_blocked_tags: filters.launcher_blocked_tags,
        launcher_blocked_names: filters.launcher_blocked_names,
    };
    let anti_cheat_active = engine::get_anti_cheat_state().is_active;
    match db::set_focus_filters_checked(&native, anti_cheat_active) {
        Ok(_) => {
            trigger_daemon_nudge();
            if native.launcher_filter_enabled && crate::launchers::has_launcher_proxy_configured() {
                std::thread::spawn(|| {
                    let _ = crate::launchers::sync_launcher_proxy_if_configured();
                });
            }
            ActionFeedback {
                success: true,
                message: "Filtros de foco atualizados com sucesso.".to_string(),
            }
        }
        Err(msg) => ActionFeedback {
            success: false,
            message: msg,
        },
    }
}

#[derive(Debug, Clone)]
pub struct SteamTagSuggestionDto {
    pub tag_id: i64,
    pub canonical_en: String,
    pub display_name: String,
}

#[derive(Debug, Clone)]
pub struct SteamGameSuggestionDto {
    pub app_id: i64,
    pub title: String,
    pub tiny_image: String,
    pub source: String,
}

#[derive(Debug, Clone)]
pub struct TagDisplayEntryDto {
    pub canonical_en: String,
    pub display_name: String,
}

fn resolve_steam_lang_pair(lang: Option<String>) -> (&'static str, &'static str) {
    if let Some(raw) = lang.as_deref() {
        let norm = db::normalize_primary_language(raw);
        if norm == "en-US" {
            return ("english", "US");
        }
        if norm == "pt-BR" {
            return ("brazilian", "BR");
        }
    }
    db::get_steam_language_and_country()
}

pub fn get_primary_language() -> String {
    db::get_primary_language()
}

pub fn set_primary_language(lang: String) -> ActionFeedback {
    match db::set_primary_language(&lang) {
        Ok(saved) => {
            trigger_daemon_nudge();
            ActionFeedback {
                success: true,
                message: saved,
            }
        }
        Err(e) => ActionFeedback {
            success: false,
            message: format!("Erro ao salvar idioma: {e}"),
        },
    }
}

pub fn get_popular_steam_tags_localized(lang: Option<String>) -> Vec<SteamTagSuggestionDto> {
    let (steam_lang, _) = resolve_steam_lang_pair(lang);
    crate::steam_api::get_popular_steam_tags_localized(steam_lang)
        .into_iter()
        .map(|t| SteamTagSuggestionDto {
            tag_id: t.tag_id,
            canonical_en: t.canonical_en,
            display_name: t.display_name,
        })
        .collect()
}

pub fn search_steam_tags_autocomplete(
    query: String,
    lang: Option<String>,
) -> Vec<SteamTagSuggestionDto> {
    let (steam_lang, _) = resolve_steam_lang_pair(lang);
    crate::steam_api::search_tag_suggestions_sync(&query, steam_lang, 14)
        .into_iter()
        .map(|t| SteamTagSuggestionDto {
            tag_id: t.tag_id,
            canonical_en: t.canonical_en,
            display_name: t.display_name,
        })
        .collect()
}

pub fn search_steam_games_autocomplete(
    query: String,
    lang: Option<String>,
) -> Vec<SteamGameSuggestionDto> {
    let (steam_lang, country) = resolve_steam_lang_pair(lang);
    crate::steam_api::search_game_suggestions_sync(&query, steam_lang, country, 10)
        .into_iter()
        .map(|g| SteamGameSuggestionDto {
            app_id: g.app_id,
            title: g.title,
            tiny_image: g.tiny_image,
            source: g.source,
        })
        .collect()
}

pub fn get_tag_display_map(
    tags: Vec<String>,
    lang: Option<String>,
) -> Vec<TagDisplayEntryDto> {
    let (steam_lang, _) = resolve_steam_lang_pair(lang);
    let map = crate::steam_api::translate_tags_for_display(&tags, steam_lang);
    tags.into_iter()
        .map(|raw| {
            let canonical = crate::steam_api::canonical_tag_to_english(&raw);
            let display_name = map
                .get(&canonical)
                .cloned()
                .unwrap_or_else(|| crate::steam_api::display_name_for_canonical_tag(&canonical, steam_lang));
            TagDisplayEntryDto {
                canonical_en: canonical,
                display_name,
            }
        })
        .collect()
}

#[derive(Debug, Clone)]
pub struct LauncherGameDto {
    pub id: String,
    pub launcher: String,
    pub app_id: Option<i64>,
    pub title: String,
    pub tags: Vec<String>,
    pub genres: Vec<String>,
    pub categories: Vec<String>,
}

pub fn get_installed_launcher_games(enrich_via_steam: bool) -> Vec<LauncherGameDto> {
    crate::launchers::discover_installed_games(enrich_via_steam)
        .into_iter()
        .map(|g| LauncherGameDto {
            id: g.id,
            launcher: g.launcher,
            app_id: g.app_id,
            title: g.title,
            tags: g.tags,
            genres: g.genres,
            categories: g.categories,
        })
        .collect()
}

pub fn lookup_steam_game_metadata(query: String, app_id: Option<i64>) -> Option<LauncherGameDto> {
    let meta = crate::steam_api::resolve_game_metadata_blocking(app_id, &query)?;
    Some(LauncherGameDto {
        id: meta
            .app_id
            .map(|id| format!("steam:{id}"))
            .unwrap_or_else(|| format!("search:{}", query.trim().to_lowercase())),
        launcher: if meta.app_id.is_some() {
            "Steam API".to_string()
        } else {
            crate::steam_api::source_display_label(&meta.source).to_string()
        },
        app_id: meta.app_id,
        title: meta.title,
        tags: meta.tags,
        genres: meta.genres,
        categories: meta.categories,
    })
}

pub fn get_popular_steam_tags() -> Vec<String> {
    crate::steam_api::get_popular_steam_tags()
}

pub fn configure_launcher_store_proxy(enable: bool) -> ActionFeedback {
    if !enable && engine::get_anti_cheat_state().is_active {
        return ActionFeedback {
            success: false,
            message: "Modo Anti-Cheat está ativo! Desativar a proteção de loja dos launchers exige desativar o Anti-Cheat primeiro.".to_string(),
        };
    }
    match crate::launchers::configure_native_launcher_proxy(enable) {
        Ok(msg) => ActionFeedback {
            success: true,
            message: msg,
        },
        Err(msg) => ActionFeedback {
            success: false,
            message: msg,
        },
    }
}
