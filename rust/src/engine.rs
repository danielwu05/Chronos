use crate::db;
use crate::detector::ActivityDetector;
use parking_lot::Mutex;
use std::sync::OnceLock;

static DETECTOR: OnceLock<Mutex<ActivityDetector>> = OnceLock::new();

fn get_detector() -> &'static Mutex<ActivityDetector> {
    DETECTOR.get_or_init(|| Mutex::new(ActivityDetector::new()))
}

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct ActiveSessionItem {
    pub entity_id: String,
    pub display_name: String,
    pub remaining_seconds: i64,
    pub daily_quota_seconds: i64,
    pub consumed_seconds: i64,
    pub is_blocked: bool,
    pub target_type: String,
    pub detected_activity_label: String,
    pub notify_mode: String,
    pub notify_interval_mins: i64,
    pub notify_remaining_mins: Vec<i64>,
}

#[derive(Clone, Debug)]
pub struct TickState {
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

#[derive(Clone, Debug)]
pub struct RuleItem {
    pub entity_id: String,
    pub display_name: String,
    pub daily_quota_seconds: i64,
    pub is_blocked_completely: bool,
    pub mode: String,
    pub ratchet_locked_until_utc: Option<i64>,
    pub updated_at_utc: i64,
    pub target_type: String, // "APP", "SITE", "KEYWORD", "GROUP"
    pub pattern: String,
    pub weekend_quota_seconds: Option<i64>,
    pub schedule_json: Option<String>,
}

#[derive(Clone, Debug)]
pub struct SiteStatusItem {
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

#[derive(Clone, Debug)]
pub struct QuarantineItem {
    pub request_id: String,
    pub app_identifier: String,
    pub display_name: String,
    pub platform: String,
    pub status: String,
    pub requested_at_utc: i64,
}

#[derive(Clone, Debug)]
pub struct InstalledAppItem {
    pub id: String,
    pub name: String,
    pub exec: String,
    pub icon_name: String,
    pub icon_path: String,
}

/// Resolve o caminho real do ícone (.png ou .svg) nos diretórios padrão do Linux
pub fn resolve_icon_path(icon_name: &str) -> String {
    if icon_name.is_empty() {
        return String::new();
    }
    let p = std::path::Path::new(icon_name);
    if p.is_absolute() && p.exists() {
        return icon_name.to_string();
    }

    let sizes = ["48x48", "64x64", "128x128", "256x256", "32x32", "scalable"];
    let extensions = [".png", ".svg", ""];

    // 1. /usr/share/icons/hicolor/{size}/apps/{icon}
    for size in &sizes {
        for ext in &extensions {
            let candidate = format!("/usr/share/icons/hicolor/{}/apps/{}{}", size, icon_name, ext);
            if std::path::Path::new(&candidate).exists() {
                return candidate;
            }
        }
    }

    // 2. /usr/share/pixmaps/{icon}
    for ext in &extensions {
        let candidate = format!("/usr/share/pixmaps/{}{}", icon_name, ext);
        if std::path::Path::new(&candidate).exists() {
            return candidate;
        }
    }

    // 3. ~/.local/share/icons
    if let Ok(home) = std::env::var("HOME") {
        for size in &sizes {
            for ext in &extensions {
                let candidate = format!("{}/.local/share/icons/hicolor/{}/apps/{}{}", home, size, icon_name, ext);
                if std::path::Path::new(&candidate).exists() {
                    return candidate;
                }
            }
        }
    }

    String::new()
}

fn map_xdg_categories_to_tags(categories_raw: &str) -> String {
    let mut tags = Vec::new();
    for cat in categories_raw.split(';').map(|c| c.trim().to_lowercase()).filter(|c| !c.is_empty()) {
        let mapped = match cat.as_str() {
            "game" | "actiongame" | "adventuregame" | "arcade" | "boardgame" | "cardgame" | "emulator" | "roleplaying" | "simulation" | "sportsgame" | "strategygame" => Some("Jogos"),
            "webbrowser" => Some("Navegadores"),
            "instantmessaging" | "chat" | "ircclient" | "email" | "telephony" | "videoconference" => Some("Comunicação"),
            "network" | "filetransfer" | "p2p" | "remoteaccess" => Some("Internet"),
            "audiovideo" | "audio" | "video" | "music" | "player" | "recorder" | "tv" => Some("Mídia"),
            "development" | "ide" | "debugger" | "revisioncontrol" | "webdevelopment" => Some("Desenvolvimento"),
            "office" | "wordprocessor" | "spreadsheet" | "presentation" | "viewer" | "publishing" => Some("Escritório"),
            "graphics" | "2dgraphics" | "3dgraphics" | "photography" | "vectorgraphics" | "rastergraphics" => Some("Gráficos"),
            "education" | "science" | "math" => Some("Educação"),
            "system" | "settings" | "desktopsettings" | "hardwaresettings" | "monitor" | "security" => Some("Sistema"),
            "utility" | "accessories" | "archiving" | "filetools" | "texteditor" | "terminalemulator" => Some("Utilitários"),
            _ => None,
        };
        if let Some(tag) = mapped {
            if !tags.contains(&tag) {
                tags.push(tag);
            }
        }
    }
    if tags.is_empty() {
        tags.push("Outros");
    }
    tags.join(",")
}

/// Varre o sistema Linux (XDG) em busca de aplicativos instalados com arquivos .desktop
pub fn list_installed_desktop_apps() -> Vec<InstalledAppItem> {
    let mut apps = Vec::new();
    let mut seen = std::collections::HashSet::new();

    let mut search_dirs = vec![
        std::path::PathBuf::from("/usr/share/applications"),
        std::path::PathBuf::from("/usr/local/share/applications"),
        std::path::PathBuf::from("/var/lib/flatpak/exports/share/applications"),
    ];
    if let Ok(home) = std::env::var("HOME") {
        search_dirs.push(std::path::PathBuf::from(&home).join(".local/share/applications"));
        search_dirs.push(std::path::PathBuf::from(&home).join(".local/share/flatpak/exports/share/applications"));
    }

    for dir in search_dirs {
        let entries = match std::fs::read_dir(dir) {
            Ok(e) => e,
            Err(_) => continue,
        };

        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|s| s.to_str()) != Some("desktop") {
                continue;
            }

            if let Ok(content) = std::fs::read_to_string(&path) {
                let mut name: Option<String> = None;
                let mut exec: Option<String> = None;
                let mut icon: Option<String> = None;
                let mut categories = String::new();
                let mut no_display = false;
                let mut is_app = false;

                for line in content.lines() {
                    let line = line.trim();
                    if line.starts_with("Type=") && line[5..].trim().eq_ignore_ascii_case("Application") {
                        is_app = true;
                    } else if line.starts_with("NoDisplay=") && line[10..].trim().eq_ignore_ascii_case("true") {
                        no_display = true;
                    } else if line.starts_with("Name=") && name.is_none() {
                        name = Some(line[5..].trim().to_string());
                    } else if line.starts_with("Exec=") && exec.is_none() {
                        exec = normalize_desktop_exec(line[5..].trim());
                    } else if line.starts_with("Icon=") && icon.is_none() {
                        icon = Some(line[5..].trim().to_string());
                    } else if line.starts_with("Categories=") && categories.is_empty() {
                        categories = line[11..].trim().to_string();
                    }
                }

                if no_display || !is_app {
                    continue;
                }

                if let (Some(n), Some(e)) = (name, exec) {
                    let unique_key = format!("{}:::{}", n.to_lowercase(), e.to_lowercase());
                    if seen.insert(unique_key) {
                        let id = e.to_lowercase();
                        let raw_icon_name = icon.unwrap_or_default();
                        let icon_path = resolve_icon_path(&raw_icon_name);
                        let tags_str = map_xdg_categories_to_tags(&categories);
                        apps.push(InstalledAppItem {
                            id,
                            name: n,
                            exec: e,
                            // Armazena as tags extraídas do .desktop em icon_name para uso direto no filtro da UI
                            icon_name: tags_str,
                            icon_path,
                        });
                    }
                }
            }
        }
    }

    apps.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    apps
}

fn parse_hhmm_to_mins(time_val: &str) -> Option<i32> {
    let mut parts = time_val.trim().split(':');
    let h: i32 = parts.next()?.parse().ok()?;
    let m: i32 = parts.next()?.parse().ok()?;
    Some(h * 60 + m)
}

/// Avalia se a regra está bloqueada por janela de horário ou fora dos dias permitidos.
pub fn evaluate_schedule_window(schedule_json: Option<&str>, cur_h: i32, cur_m: i32, sqlite_dow: i32) -> (bool, bool) {
    let sched_str = match schedule_json {
        Some(s) if !s.trim().is_empty() => s.trim(),
        _ => return (true, false),
    };

    let parsed: serde_json::Value = match serde_json::from_str(sched_str) {
        Ok(v) => v,
        Err(_) => return (true, false),
    };

    // sqlite_dow: 0 = Dom, 1 = Seg ... 6 = Sab -> converte para 1 = Seg ... 7 = Dom
    let iso_day = if sqlite_dow == 0 { 7 } else { sqlite_dow };
    let mut active_day = true;
    if let Some(days_arr) = parsed.get("days").and_then(|d| d.as_array()) {
        if !days_arr.is_empty() {
            active_day = days_arr.iter().any(|v| v.as_i64() == Some(iso_day as i64));
        }
    }

    if !active_day {
        // Se hoje não está nos dias ativos da regra, não bloqueia por janela nem aplica a regra hoje
        return (false, false);
    }

    let tw_enabled = parsed
        .get("time_window_enabled")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    if !tw_enabled {
        return (true, false);
    }

    let start_str = parsed
        .get("time_window_start")
        .and_then(|v| v.as_str())
        .unwrap_or("08:00");
    let end_str = parsed
        .get("time_window_end")
        .and_then(|v| v.as_str())
        .unwrap_or("18:00");
    let mode = parsed
        .get("time_window_mode")
        .and_then(|v| v.as_str())
        .unwrap_or("BLOCK_INSIDE");

    let start = parse_hhmm_to_mins(start_str).unwrap_or(8 * 60);
    let end = parse_hhmm_to_mins(end_str).unwrap_or(18 * 60);
    let cur_mins = cur_h * 60 + cur_m;

    let inside = if start <= end {
        cur_mins >= start && cur_mins < end
    } else {
        cur_mins >= start || cur_mins < end
    };

    let blocked_by_window = if mode == "BLOCK_INSIDE" {
        inside
    } else {
        !inside
    };

    (true, blocked_by_window)
}

pub fn parse_notification_settings(schedule_json: Option<&str>) -> (String, i64, Vec<i64>) {
    let default_remaining = vec![15, 5, 1];
    let sched_str = match schedule_json {
        Some(s) if !s.trim().is_empty() => s.trim(),
        _ => return ("both".to_string(), 15, default_remaining),
    };

    let parsed: serde_json::Value = match serde_json::from_str(sched_str) {
        Ok(v) => v,
        Err(_) => return ("both".to_string(), 15, default_remaining),
    };

    let mode = parsed
        .get("notify_mode")
        .and_then(|v| v.as_str())
        .unwrap_or("both")
        .to_string();
    let interval = parsed
        .get("notify_interval_mins")
        .and_then(|v| v.as_i64())
        .unwrap_or(15)
        .max(1);
    let mut rem_list = Vec::new();
    if let Some(arr) = parsed.get("notify_remaining_mins").and_then(|v| v.as_array()) {
        for item in arr {
            if let Some(n) = item.as_i64() {
                rem_list.push(n);
            }
        }
    }
    if rem_list.is_empty() {
        rem_list = default_remaining;
    }

    (mode, interval, rem_list)
}

pub fn matches_site_or_keyword(
    pattern_item: &str,
    win_lower: &str,
    browser_url_lower: &str,
    browser_title_lower: &str,
) -> bool {
    let clean = pattern_item
        .trim()
        .trim_start_matches("https://")
        .trim_start_matches("http://")
        .trim_start_matches("www.")
        .trim_end_matches('/')
        .to_lowercase();
    if clean.is_empty() {
        return false;
    }

    // 1. Checa URL ativa do navegador e título da aba ativa
    if !browser_url_lower.is_empty() && browser_url_lower.contains(&clean) {
        return true;
    }
    if !browser_title_lower.is_empty() && browser_title_lower.contains(&clean) {
        return true;
    }

    // 2. Checa título da janela ativa do sistema operacional
    if !win_lower.is_empty() && win_lower.contains(&clean) {
        return true;
    }

    // 3. Se for domínio simples sem caminho específico (ex: "youtube.com", não "instagram.com/reels"),
    // também aceita o nome principal do domínio no título da janela (ex: "youtube" em "YouTube - Google Chrome")
    if clean.contains('.') && !clean.contains('/') {
        let short = clean.split('.').next().unwrap_or("");
        if short.len() >= 3 && !win_lower.is_empty() && win_lower.contains(short) {
            return true;
        }
    }

    false
}

pub fn normalize_desktop_exec(raw_exec: &str) -> Option<String> {
    let cmd = raw_exec.trim();
    if cmd.is_empty() {
        return None;
    }

    // Preserva URIs específicos de jogos em launchers (ex: steam steam://rungameid/730)
    let lower = cmd.to_lowercase();
    for scheme in [
        "steam://rungameid/",
        "heroic://launch/",
        "lutris:rungame/",
        "lutris:rungameid/",
    ] {
        if let Some(pos) = lower.find(scheme) {
            let slice = &cmd[pos..];
            let token = slice
                .split_whitespace()
                .next()
                .unwrap_or(slice)
                .trim_matches('"')
                .trim_matches('\'');
            if !token.is_empty() {
                return Some(token.to_string());
            }
        }
    }

    // Suporte a `steam -applaunch <appid>`
    let tokens: Vec<&str> = cmd.split_whitespace().collect();
    for w in tokens.windows(2) {
        if w[0].eq_ignore_ascii_case("-applaunch") {
            let id_clean = w[1].trim_matches('"').trim_matches('\'');
            if id_clean.chars().all(|c| c.is_ascii_digit()) && !id_clean.is_empty() {
                return Some(format!("steam://rungameid/{id_clean}"));
            }
        }
    }

    // Suporte a `flatpak run com.app.Id ...`
    if tokens.len() >= 3
        && std::path::Path::new(tokens[0].trim_matches('"'))
            .file_name()
            .and_then(|f| f.to_str())
            .map(|b| b.eq_ignore_ascii_case("flatpak"))
            .unwrap_or(false)
        && tokens[1] == "run"
    {
        return Some(tokens[2].trim_matches('"').to_string());
    }

    let is_wrapper_token = |raw: &str| -> bool {
        let clean = raw.trim_matches('"').trim_matches('\'');
        let base = clean
            .rsplit(['/', '\\'])
            .next()
            .unwrap_or(clean)
            .to_lowercase();
        matches!(base.as_str(), "env" | "chronos-launcher-env")
    };
    let first = tokens
        .iter()
        .copied()
        .find(|t| !t.starts_with('%') && !t.contains('=') && !is_wrapper_token(t))
        .unwrap_or(cmd)
        .trim_matches('"')
        .trim_matches('\'');
    let clean = std::path::Path::new(first)
        .file_name()
        .and_then(|f| f.to_str())
        .unwrap_or(first);
    if clean.is_empty() {
        None
    } else {
        Some(clean.to_string())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppTarget {
    pub name: String,
    pub exec: String,
}

impl AppTarget {
    pub fn extract_steam_app_id(&self) -> Option<i64> {
        let lower = self.exec.trim().to_lowercase();
        if let Some(rest) = lower.strip_prefix("steam://rungameid/") {
            let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
            if let Ok(id) = digits.parse::<i64>() {
                if id > 0 {
                    return Some(id);
                }
            }
        }
        if let Some(pos) = lower.find("steam_app_") {
            let rest = &lower[pos + "steam_app_".len()..];
            let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
            if let Ok(id) = digits.parse::<i64>() {
                if id > 0 {
                    return Some(id);
                }
            }
        }
        let tokens: Vec<&str> = lower.split_whitespace().collect();
        for w in tokens.windows(2) {
            if w[0] == "-applaunch" {
                if let Ok(id) = w[1].parse::<i64>() {
                    if id > 0 {
                        return Some(id);
                    }
                }
            }
        }
        None
    }

    pub fn is_launcher(&self) -> bool {
        let e = self.exec.trim().to_lowercase();
        let base = crate::detector::extract_binary_basename(&e);
        e.starts_with("steam://")
            || e.starts_with("heroic://")
            || e.starts_with("lutris:")
            || matches!(
                e.as_str(),
                "steam" | "steamwebhelper" | "heroic" | "lutris" | "wine" | "wine64" | "proton" | "bottles"
            )
            || matches!(
                base.as_str(),
                "steam" | "steamwebhelper" | "heroic" | "lutris" | "wine" | "wine64" | "proton" | "bottles"
            )
    }

    /// Verdadeiro quando o alvo representa um JOGO executado dentro de um launcher
    /// (ex: `{name: "Counter-Strike 2", exec: "steam"}` ou `exec: "steam://rungameid/730"`),
    /// e NÃO o próprio aplicativo launcher adicionado explicitamente (ex: `{name: "Steam", exec: "steam"}`).
    pub fn is_launcher_hosted_game(&self) -> bool {
        if !self.is_launcher() {
            return false;
        }
        if self.extract_steam_app_id().is_some() {
            return true;
        }
        let e = self.exec.trim().to_lowercase();
        if e.starts_with("steam://") || e.starts_with("heroic://") || e.starts_with("lutris:") {
            return true;
        }
        let n = self.name.trim();
        !n.is_empty() && !crate::detector::is_generic_launcher_token(n)
    }
}

pub fn evaluate_app_target_activity(
    app: &AppTarget,
    active_details: &crate::detector::ActiveWindowDetails,
    win_lower: &str,
    all_windows_info: &[crate::detector::WindowInfo],
) -> Option<String> {
    if app.is_launcher_hosted_game() {
        let steam_app_id = app.extract_steam_app_id();
        let active_win = active_details.as_window_info();
        if active_win.matches_game_window(&app.name, steam_app_id) {
            return Some(format!("Jogo '{}' em foco", app.name));
        }
        if all_windows_info
            .iter()
            .any(|w| w.matches_game_window(&app.name, steam_app_id))
        {
            return Some(format!("Jogo '{}' com janela aberta", app.name));
        }
        if let Some(appid) = steam_app_id {
            if get_detector().lock().is_steam_appid_running(appid) {
                return Some(format!("Jogo '{}' em execução (AppID {})", app.name, appid));
            }
        }
        return None;
    }

    let name_lower = app.name.to_lowercase();
    let exec_lower = app.exec.to_lowercase();
    let is_launcher = app.is_launcher();

    let is_focused = (!active_details.class.is_empty()
        && (active_details.class == name_lower || active_details.class == exec_lower))
        || (!active_details.initial_class.is_empty()
            && (active_details.initial_class == name_lower
                || active_details.initial_class == exec_lower))
        || (!win_lower.is_empty()
            && !active_details.is_browser
            && (win_lower == name_lower || win_lower.starts_with(&format!("{name_lower} - "))));

    // App used as a site in the focused browser tab (youtube.com for "YouTube", ...).
    let in_browser_tab = !is_launcher && active_details.is_browser && {
        let mut domains: Vec<&str> = crate::proxy::known_domains_for_app(&name_lower).to_vec();
        domains.extend_from_slice(crate::proxy::known_domains_for_app(&exec_lower));
        !domains.is_empty()
            && crate::detector::WindowInfo::active_browser_tab_host()
                .is_some_and(|h| domains.iter().any(|d| h == *d || h.ends_with(&format!(".{d}"))))
    };

    let has_window = all_windows_info
        .iter()
        .any(|w| w.matches_app(&app.name, &app.exec));
    let is_running_bg = if !is_launcher {
        get_detector().lock().is_process_running(&app.exec)
    } else {
        false
    };

    if is_focused {
        Some(format!("App '{}' em foco", app.name))
    } else if in_browser_tab {
        Some(format!("App '{}' no navegador", app.name))
    } else if has_window {
        Some(format!("App '{}' com janela aberta", app.name))
    } else if is_running_bg {
        Some(format!("App '{}' em 2º plano", app.name))
    } else {
        None
    }
}

fn enforce_app_target_block(
    app: &AppTarget,
    wl_groups: &[db::WhitelistGroupItem],
    reason: &str,
    windows: &[crate::detector::WindowInfo],
) {
    if db::is_item_in_whitelist_groups(wl_groups, &app.name)
        || db::is_item_in_whitelist_groups(wl_groups, &app.exec)
    {
        return;
    }

    // Block screen (like the +18 cover) only when the app was really open.
    let was_open = (!app.is_launcher() && get_detector().lock().is_process_running(&app.exec))
        || windows.iter().any(|w| w.matches_app(&app.name, &app.exec));
    if was_open {
        crate::screen_guard::publish_app_block(&app.name, reason);
    }

    if app.is_launcher_hosted_game() {
        let app_id = app.extract_steam_app_id();
        get_detector()
            .lock()
            .kill_steam_appid_processes(app_id.unwrap_or(0), &app.name);
        ActivityDetector::close_game_window_only(&app.name, app_id);
    } else if app.is_launcher() {
        ActivityDetector::close_window_by_title(&app.name);
        ActivityDetector::close_window_by_title(&app.exec);
    } else {
        get_detector().lock().kill_processes(&app.exec);
        // Its windows, whatever process / wrapper owns them (never a browser: web-apps
        // share the browser's process and are closed by window instead).
        // Matched by window class only: a terminal titled "discord - nvim" is not Discord.
        let by_class = |w: &crate::detector::WindowInfo| {
            crate::detector::WindowInfo { title: String::new(), ..w.clone() }.matches_app(&app.name, &app.exec)
        };
        for w in windows.iter().filter(|w| w.pid > 1 && !w.is_browser() && by_class(w)) {
            get_detector().lock().kill_pid_tree(w.pid);
        }
        ActivityDetector::close_window_by_title(&app.name);
        ActivityDetector::close_window_by_title(&app.exec);
    }
}

pub fn parse_group_pattern_rich(pattern: &str) -> (Vec<AppTarget>, Vec<String>) {
    let pattern_trimmed = pattern.trim();
    if pattern_trimmed.starts_with('{') {
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(pattern_trimmed) {
            let mut apps = Vec::new();
            let mut sites = Vec::new();
            if let Some(app_list) = v.get("apps").and_then(|a| a.as_array()) {
                for item in app_list {
                    if let Some(s) = item.as_str() {
                        let t = s.trim();
                        if !t.is_empty() {
                            apps.push(AppTarget {
                                name: t.to_string(),
                                exec: t.to_string(),
                            });
                        }
                    } else if let Some(obj) = item.as_object() {
                        let name = obj.get("name").and_then(|n| n.as_str()).unwrap_or("").trim();
                        let exec = obj.get("exec").and_then(|e| e.as_str()).unwrap_or("").trim();
                        if !name.is_empty() || !exec.is_empty() {
                            apps.push(AppTarget {
                                name: if !name.is_empty() { name.to_string() } else { exec.to_string() },
                                exec: if !exec.is_empty() { exec.to_string() } else { name.to_string() },
                            });
                        }
                    }
                }
            }
            if let Some(site_list) = v.get("sites").and_then(|s| s.as_array()) {
                for item in site_list {
                    if let Some(s) = item.as_str() {
                        let t = s.trim();
                        if !t.is_empty() {
                            sites.push(t.to_string());
                        }
                    }
                }
            }
            return (apps, sites);
        }
    }
    // Fallback: CSV pattern
    let mut apps = Vec::new();
    let mut sites = Vec::new();
    for item in pattern.split(',').map(|s| s.trim()).filter(|s| !s.is_empty()) {
        if item.contains('.') && !item.ends_with(".exe") && !item.ends_with(".bin") {
            sites.push(item.to_string());
        } else {
            apps.push(AppTarget {
                name: item.to_string(),
                exec: item.to_string(),
            });
        }
    }
    (apps, sites)
}

pub fn parse_group_pattern(pattern: &str) -> (Vec<String>, Vec<String>) {
    let (rich_apps, sites) = parse_group_pattern_rich(pattern);
    let apps = rich_apps.into_iter().map(|a| a.name).collect();
    (apps, sites)
}

/// Which of `patterns` the playing media (tab title/url label) belongs to.
fn media_matched_pattern(media_title: Option<&str>, patterns: &[String]) -> Vec<String> {
    let t = media_title.unwrap_or("").to_lowercase();
    if t.is_empty() {
        return Vec::new();
    }
    patterns
        .iter()
        .find(|p| {
            let clean = p.trim().trim_start_matches("www.").to_lowercase();
            let root = clean.split('.').next().unwrap_or("");
            (!clean.is_empty() && t.contains(&clean)) || (root.len() >= 3 && t.contains(root))
        })
        .cloned()
        .into_iter()
        .collect()
}

/// Tamper penalty (set by the root vault): every session stays blocked until local midnight.
pub fn penalty_active(now: i64) -> bool {
    db::try_get_conn().is_some()
        && db::get_config("penalty_until")
            .and_then(|v| v.parse::<i64>().ok())
            .is_some_and(|until| until > now)
}

/// Reaction to tampering chosen by the user: "restore" (default) or "restore_penalty".
pub fn tamper_reaction() -> String {
    db::get_config("tamper_reaction").unwrap_or_else(|| "restore".to_string())
}

/// Changing to the lighter reaction is refused while anti-cheat is active.
pub fn set_tamper_reaction(reaction: &str) -> Result<(), String> {
    if reaction != "restore" && reaction != "restore_penalty" {
        return Err("Reação inválida.".to_string());
    }
    if reaction == "restore" && tamper_reaction() == "restore_penalty" && get_anti_cheat_state().is_active {
        return Err("Anti-Burla ativo: a penalidade por burla não pode ser desligada agora.".to_string());
    }
    db::set_config("tamper_reaction", reaction).map_err(|e| e.to_string())
}

pub fn tick_entity(entity_id: &str) -> Option<TickState> {
    let now = crate::trusted_time::now_secs();
    let penalty = penalty_active(now);

    // 1. Consulta rápida dos parâmetros da regra e horário local em um único lock rápido
    let (display_name, daily_quota, forced_blocked, ratchet_locked_until, target_type, pattern, weekend_quota, schedule_json, day_of_week, cur_h, cur_m, is_weekend) = {
        let conn = db::get_conn().lock();
        let (dow, h, m): (i32, i32, i32) = conn
            .query_row(
                "SELECT CAST(strftime('%w', ?1, 'unixepoch', 'localtime') AS INTEGER), CAST(strftime('%H', ?1, 'unixepoch', 'localtime') AS INTEGER), CAST(strftime('%M', ?1, 'unixepoch', 'localtime') AS INTEGER)",
                [crate::trusted_time::now_secs()],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .unwrap_or((1, 12, 0));

        let mut stmt = conn
            .prepare("SELECT display_name, daily_quota_seconds, is_blocked_completely, ratchet_locked_until_utc, COALESCE(target_type, 'APP'), COALESCE(pattern, ''), weekend_quota_seconds, schedule_json FROM rules WHERE entity_id = ?1")
            .ok()?;

        let (name, daily_raw, blocked, ratchet, ttype, pat, w_quota, sched) = stmt.query_row([entity_id], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, i32>(2)?,
                row.get::<_, Option<i64>>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, String>(5)?,
                row.get::<_, Option<i64>>(6)?,
                row.get::<_, Option<String>>(7)?,
            ))
        }).ok()?;

        let weekend = dow == 0 || dow == 6;
        let quota = if weekend && w_quota.unwrap_or(0) > 0 {
            w_quota.unwrap()
        } else {
            daily_raw
        };

        (name, quota, blocked, ratchet, ttype, pat, w_quota, sched, dow, h, m, weekend)
    };
    // Holiday > weekend > weekday (outside the DB lock: reads app_config).
    let (daily_quota, _holiday_name) = crate::holidays::apply_holiday_quota(entity_id, daily_quota);

    let (is_active_day, is_blocked_by_window) =
        evaluate_schedule_window(schedule_json.as_deref(), cur_h, cur_m, day_of_week);

    // 2. Detecção com base no Tipo de Alvo (APP, SITE, KEYWORD, GROUP)
    let active_details = ActivityDetector::get_active_window_details();
    let win_lower = active_details.title.to_lowercase();
    let (browser_url_lower, browser_title_lower) =
        ActivityDetector::get_active_browser_context(&active_details);
    let all_windows_info = ActivityDetector::get_all_windows_info();

    let mut is_active = false;
    let mut is_bg_media = false;
    // Where the activity came from: foreground (focused/open window, focused browser tab)
    // vs media. `matched_items` are the app/site identifiers that made the rule active,
    // used for per-item whitelisting.
    let mut via_foreground = false;
    let mut matched_items: Vec<String> = Vec::new();
    let mut activity_label = "Nenhuma atividade detectada".to_string();

    if is_active_day {
        match target_type.as_str() {
            "GROUP" => {
                // Sessão / Grupo Unificado (Apps e Sites/Palavras combinados)
                let (apps, sites) = parse_group_pattern_rich(&pattern);
                for app in &apps {
                    if let Some(label) =
                        evaluate_app_target_activity(app, &active_details, &win_lower, &all_windows_info)
                    {
                        is_active = true;
                        via_foreground = true;
                        matched_items.push(app.name.clone());
                        matched_items.push(app.exec.clone());
                        activity_label = label;
                        break;
                    }
                }
                if !is_active {
                    let app_names: Vec<String> = apps.iter().map(|a| a.name.clone()).collect();
                    let (has_app_media, app_media_title) = ActivityDetector::is_media_playing_for_patterns(&app_names);
                    if has_app_media {
                        is_active = true;
                        is_bg_media = true;
                        let t = app_media_title.clone().unwrap_or_default().to_lowercase();
                        if let Some(a) = apps.iter().find(|a| !a.name.is_empty() && t.contains(&a.name.to_lowercase())) {
                            matched_items.push(a.name.clone());
                            matched_items.push(a.exec.clone());
                        }
                        activity_label = format!("Sessão '{}' em reprodução: {}", display_name, app_media_title.unwrap_or_default());
                    }
                }
                if !is_active {
                    for d in &sites {
                        if matches_site_or_keyword(d, &win_lower, &browser_url_lower, &browser_title_lower) {
                            is_active = true;
                            via_foreground = true;
                            matched_items.push(d.clone());
                            activity_label = format!("Sessão '{}' ativa via web/palavra '{}'", display_name, d);
                            break;
                        }
                    }
                }
                if !is_active && !sites.is_empty() {
                    let (has_media, media_title) = ActivityDetector::is_media_playing_for_patterns(&sites);
                    if has_media {
                        is_active = true;
                        is_bg_media = true;
                        matched_items.extend(media_matched_pattern(media_title.as_deref(), &sites));
                        activity_label = format!("Sessão '{}' em reprodução: {}", display_name, media_title.unwrap_or_default());
                    }
                }
            }
            "SITE_GROUP" | "KEYWORD" | "SITE" => {
                let items: Vec<String> = if pattern.is_empty() {
                    vec![entity_id.to_string()]
                } else if pattern.trim().starts_with('{') {
                    parse_group_pattern(&pattern).1
                } else {
                    pattern
                        .split(',')
                        .map(|s| s.trim().to_string())
                        .filter(|s| !s.is_empty())
                        .collect()
                };
                for item in &items {
                    if matches_site_or_keyword(item, &win_lower, &browser_url_lower, &browser_title_lower) {
                        is_active = true;
                        via_foreground = true;
                        matched_items.push(item.clone());
                        activity_label = format!("'{}' ativo via '{}'", display_name, item);
                        break;
                    }
                }
                if !is_active {
                    let (has_media, media_title) = ActivityDetector::is_media_playing_for_patterns(&items);
                    if has_media {
                        is_active = true;
                        is_bg_media = true;
                        matched_items.extend(media_matched_pattern(media_title.as_deref(), &items));
                        activity_label = format!("'{}' em reprodução: {}", display_name, media_title.unwrap_or_default());
                    }
                }
            }
            _ => {
                // Modo "APP": janela em foco, janela aberta ou processo em segundo plano
                let proc_target = if pattern.is_empty() { entity_id } else { &pattern };
                let app = AppTarget {
                    name: display_name.clone(),
                    exec: proc_target.to_string(),
                };
                if let Some(label) =
                    evaluate_app_target_activity(&app, &active_details, &win_lower, &all_windows_info)
                {
                    is_active = true;
                    via_foreground = true;
                    matched_items.push(display_name.clone());
                    matched_items.push(proc_target.to_string());
                    activity_label = label;
                } else {
                    let (has_media, media_title) =
                        ActivityDetector::is_media_playing_in_background(proc_target);
                    if has_media {
                        is_active = true;
                        is_bg_media = true;
                        matched_items.push(display_name.clone());
                        matched_items.push(proc_target.to_string());
                        activity_label = format!(
                            "Tocando em 2º plano: {}",
                            media_title.unwrap_or_default()
                        );
                    }
                }
            }
        }
    } else {
        activity_label = "Regra inativa no dia de hoje".to_string();
    }

    let wl_groups = db::get_all_whitelist_groups();
    // Whitelist applies to the item that is actually in use (or the whole rule when the
    // rule itself is whitelisted): whitelisted activity is neither counted nor blocked,
    // while the rule's other items keep counting.
    let is_whitelisted = db::is_item_in_whitelist_groups(&wl_groups, entity_id)
        || matched_items
            .iter()
            .any(|m| !m.trim().is_empty() && db::is_item_in_whitelist_groups(&wl_groups, m));

    // YouTube content-type whitelist: watching an exempt type (under its daily cap)
    // keeps the entity "active" but does not consume its quota.
    let yt_exempt_type = if is_active && !is_whitelisted {
        let yt_related = crate::youtube::rule_is_youtube_related(entity_id, &display_name, &pattern);
        crate::youtube::current_exemption(
            yt_related,
            active_details.is_browser,
            via_foreground && active_details.is_browser,
        )
    } else {
        None
    };
    if let Some(t) = &yt_exempt_type {
        crate::youtube::record_exempt_second(t);
        activity_label = format!("{} • Isento: {}", activity_label, crate::youtube::type_label(t));
    }

    // 3. Atualização de consumo no SQLite
    let (emergency_tokens, leisure_locked_until, consumed_seconds) = {
        let conn = db::get_conn().lock();

        let (emergency_tokens, leisure_locked_until): (i64, i64) = conn
            .query_row(
                "SELECT remaining_tokens, leisure_locked_until_utc FROM emergency_tokens WHERE id = 1",
                [],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .unwrap_or((2, 0));

        let day_start = now - (now % 86400);

        let mut sum_stmt = conn
            .prepare(
                "SELECT COALESCE(SUM(ended_at_utc - started_at_utc), 0)
                 FROM usage_intervals
                 WHERE entity_id = ?1 AND started_at_utc >= ?2",
            )
            .ok()?;

        let mut consumed: i64 = sum_stmt
            .query_row((entity_id, day_start), |row| row.get(0))
            .unwrap_or(0);

        let is_leisure_locked = leisure_locked_until > now;
        let blocked_now = if is_whitelisted || !is_active_day {
            false
        } else {
            forced_blocked == 1 || penalty || consumed >= daily_quota || is_leisure_locked || is_blocked_by_window
        };

        if is_active && !blocked_now && yt_exempt_type.is_none() && !is_whitelisted {
            let mut active_stmt = conn
                .prepare(
                    "SELECT interval_id, ended_at_utc FROM usage_intervals
                     WHERE entity_id = ?1 AND ended_at_utc >= ?2
                     ORDER BY ended_at_utc DESC LIMIT 1",
                )
                .ok()?;

            let active: Option<(String, i64)> = active_stmt
                .query_row((entity_id, now - 3), |row| Ok((row.get(0)?, row.get(1)?)))
                .ok();
            let last_nc = LAST_NONCOUNTED.lock().get(entity_id).copied();
            let active_id = active
                .filter(|(_, ended)| should_extend_interval(*ended, now, last_nc))
                .map(|(id, _)| id);

            if let Some(id) = active_id {
                let _ = conn.execute(
                    "UPDATE usage_intervals SET ended_at_utc = ?1 WHERE interval_id = ?2",
                    (now, id),
                );
            } else {
                let interval_id = format!("{}_{}", entity_id, now);
                let _ = conn.execute(
                    "INSERT INTO usage_intervals (interval_id, entity_id, device_id, started_at_utc, ended_at_utc)
                     VALUES (?1, ?2, 'local_device', ?3, ?4)",
                    (&interval_id, entity_id, now - 1, now),
                );
            }

            consumed += 1;
        } else if is_active {
            // Active but not counted (exempt, whitelisted, blocked): the next counted tick
            // must not bridge over this second.
            LAST_NONCOUNTED.lock().insert(entity_id.to_string(), now);
        }

        (emergency_tokens, leisure_locked_until, consumed)
    };

    let is_leisure_locked = leisure_locked_until > now;
    let is_blocked = if is_whitelisted || !is_active_day {
        false
    } else {
        forced_blocked == 1 || penalty || consumed_seconds >= daily_quota || is_leisure_locked || is_blocked_by_window
    };

    if is_blocked_by_window && is_blocked {
        activity_label = format!("{} • Bloqueado por Janela de Horário", activity_label);
    }

    // 4. Ações ativas de bloqueio quando esgotado ou dentro da janela bloqueada
    if is_blocked && is_active && !is_whitelisted && yt_exempt_type.is_none() {
        // Shown on the block screen (translated by the app).
        let block_reason = if forced_blocked == 1 {
            "forced"
        } else if penalty {
            "penalty"
        } else if is_blocked_by_window {
            "window"
        } else if is_leisure_locked {
            "leisure"
        } else {
            "quota"
        };
        let windows = ActivityDetector::get_all_windows_info();
        if is_bg_media || target_type == "GROUP" || target_type == "SITE_GROUP" || target_type == "SITE" || target_type == "KEYWORD" {
            ActivityDetector::pause_background_media(entity_id);
        }
        if target_type == "GROUP" {
            let (apps, _) = parse_group_pattern_rich(&pattern);
            for app in apps {
                enforce_app_target_block(&app, &wl_groups, block_reason, &windows);
            }
        } else if target_type == "APP" && entity_id != "youtube" {
            let proc_target = if pattern.is_empty() { entity_id } else { &pattern };
            let app = AppTarget {
                name: display_name.clone(),
                exec: proc_target.to_string(),
            };
            enforce_app_target_block(&app, &wl_groups, block_reason, &windows);
        }
    }

    let remaining = (daily_quota - consumed_seconds).max(0);

    Some(TickState {
        entity_id: entity_id.to_string(),
        display_name,
        remaining_seconds: remaining,
        daily_quota_seconds: daily_quota,
        consumed_seconds,
        is_active_now: is_active,
        is_background_playback: is_bg_media,
        is_blocked: yt_exempt_type.is_none()
            && (is_blocked || (remaining == 0 && !is_whitelisted && is_active_day)),
        detected_activity_label: activity_label,
        ratchet_locked_until_utc: ratchet_locked_until,
        emergency_tokens_remaining: emergency_tokens,
        leisure_locked_until_utc: leisure_locked_until,
        target_type,
        is_weekend,
        weekend_quota_seconds: weekend_quota,
        active_sessions_json: "[]".to_string(),
    })
}

#[derive(Clone)]
pub struct QuotaUpdateResult {
    pub success: bool,
    pub message: String,
}

pub fn update_quota_ratchet(entity_id: &str, new_quota_seconds: i64) -> QuotaUpdateResult {
    let now = crate::trusted_time::now_secs();

    let (current_quota, locked_until) = {
        let conn = db::get_conn().lock();
        let row: Option<(i64, Option<i64>)> = conn
            .query_row(
                "SELECT daily_quota_seconds, ratchet_locked_until_utc FROM rules WHERE entity_id = ?1",
                [entity_id],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .ok();

        match row {
            Some(data) => data,
            None => {
                return QuotaUpdateResult {
                    success: false,
                    message: "Regra não encontrada.".to_string(),
                }
            }
        }
    };

    let is_locked = locked_until.unwrap_or(0) > now;

    if get_anti_cheat_state().is_active && new_quota_seconds > current_quota {
        return QuotaUpdateResult {
            success: false,
            message: "Modo Anti-Burla está ativo! Aumentos de cota são estritamente proibidos até a desativação do Anti-Burla.".to_string(),
        };
    }

    if is_locked && new_quota_seconds > current_quota {
        let remaining_lock_hours = ((locked_until.unwrap_or(0) - now) / 3600).max(1);
        return QuotaUpdateResult {
            success: false,
            message: format!(
                "Catraca ativa! Proibido aumentar a cota pelas próximas {}h. Você só pode reduzir.",
                remaining_lock_hours
            ),
        };
    }

    let conn = db::get_conn().lock();
    let _ = conn.execute(
        "UPDATE rules SET daily_quota_seconds = ?1, updated_at_utc = ?2 WHERE entity_id = ?3",
        (new_quota_seconds, now, entity_id),
    );

    QuotaUpdateResult {
        success: true,
        message: format!("Cota atualizada para {} segundos.", new_quota_seconds),
    }
}

pub fn activate_ratchet_lock(entity_id: &str, duration_hours: i64) -> bool {
    let conn = db::get_conn().lock();
    let now = crate::trusted_time::now_secs();

    let unlock_at = now + (duration_hours * 3600);

    conn.execute(
        "UPDATE rules SET ratchet_locked_until_utc = MAX(COALESCE(ratchet_locked_until_utc, 0), ?1) WHERE entity_id = ?2",
        (unlock_at, entity_id),
    )
    .is_ok()
}

pub fn use_emergency_token(entity_id: &str) -> QuotaUpdateResult {
    let conn = db::get_conn().lock();
    let now = crate::trusted_time::now_secs();

    let tokens: i64 = conn
        .query_row(
            "SELECT remaining_tokens FROM emergency_tokens WHERE id = 1",
            [],
            |r| r.get(0),
        )
        .unwrap_or(0);

    if tokens <= 0 {
        return QuotaUpdateResult {
            success: false,
            message: "Você não possui mais Tokens de Emergência neste mês!".to_string(),
        };
    }

    let _ = conn.execute(
        "UPDATE emergency_tokens SET remaining_tokens = remaining_tokens - 1, leisure_locked_until_utc = ?1 WHERE id = 1",
        [now + 86400],
    );

    let _ = conn.execute(
        "UPDATE rules SET daily_quota_seconds = daily_quota_seconds + 3600 WHERE entity_id = ?1",
        [entity_id],
    );

    QuotaUpdateResult {
        success: true,
        message: format!(
            "Token consumido! +1h liberada. Penalidade: Modo Lazer travado por 24h. Restam {} token(s).",
            tokens - 1
        ),
    }
}

pub fn get_all_rules() -> Vec<RuleItem> {
    let conn = db::get_conn().lock();
    let mut stmt = match conn.prepare("SELECT entity_id, display_name, daily_quota_seconds, is_blocked_completely, mode, ratchet_locked_until_utc, updated_at_utc, COALESCE(target_type, 'APP'), COALESCE(pattern, ''), weekend_quota_seconds, schedule_json FROM rules ORDER BY display_name ASC") {
        Ok(s) => s,
        Err(_) => return Vec::new(),
    };

    let rows = stmt.query_map([], |row| {
        Ok(RuleItem {
            entity_id: row.get(0)?,
            display_name: row.get(1)?,
            daily_quota_seconds: row.get(2)?,
            is_blocked_completely: row.get::<_, i32>(3)? == 1,
            mode: row.get(4)?,
            ratchet_locked_until_utc: row.get(5)?,
            updated_at_utc: row.get(6)?,
            target_type: row.get(7)?,
            pattern: row.get(8)?,
            weekend_quota_seconds: row.get(9)?,
            schedule_json: row.get(10)?,
        })
    });

    match rows {
        Ok(mapped) => mapped.filter_map(Result::ok).collect(),
        Err(_) => Vec::new(),
    }
}

pub fn get_all_site_rules_status() -> Vec<SiteStatusItem> {
    let now = crate::trusted_time::now_secs();
    let penalty = penalty_active(now);
    let day_start = now - (now % 86400);

    // 1. Carrega todas as regras e métricas em um único lock rápido e libera o banco imediatamente
    let (emergency_tokens, leisure_locked_until, day_of_week, cur_h, cur_m, is_weekend, rules_data) = {
        let conn = db::get_conn().lock();
        let (tokens, leisure): (i64, i64) = conn
            .query_row(
                "SELECT remaining_tokens, leisure_locked_until_utc FROM emergency_tokens WHERE id = 1",
                [],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .unwrap_or((2, 0));

        let dow: i32 = conn
            .query_row("SELECT CAST(strftime('%w', ?1, 'unixepoch', 'localtime') AS INTEGER)", [crate::trusted_time::now_secs()], |r| r.get(0))
            .unwrap_or(1);

        let (h, m): (i32, i32) = conn
            .query_row(
                "SELECT CAST(strftime('%H', ?1, 'unixepoch', 'localtime') AS INTEGER), CAST(strftime('%M', ?1, 'unixepoch', 'localtime') AS INTEGER)",
                [crate::trusted_time::now_secs()],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .unwrap_or((12, 0));

        let mut stmt = match conn.prepare(
            "SELECT r.entity_id, r.display_name, r.daily_quota_seconds, r.is_blocked_completely,
                    COALESCE(r.target_type, 'APP'), COALESCE(r.pattern, ''), r.weekend_quota_seconds, r.schedule_json,
                    COALESCE((SELECT SUM(u.ended_at_utc - u.started_at_utc) FROM usage_intervals u WHERE u.entity_id = r.entity_id AND u.started_at_utc >= ?1), 0)
             FROM rules r ORDER BY r.display_name ASC"
        ) {
            Ok(s) => s,
            Err(_) => return Vec::new(),
        };

        let rows = stmt.query_map([day_start], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, i64>(2)?,
                row.get::<_, i32>(3)? == 1,
                row.get::<_, String>(4)?,
                row.get::<_, String>(5)?,
                row.get::<_, Option<i64>>(6)?,
                row.get::<_, Option<String>>(7)?,
                row.get::<_, i64>(8)?,
            ))
        });

        let items = match rows {
            Ok(mapped) => mapped.filter_map(Result::ok).collect::<Vec<_>>(),
            Err(_) => Vec::new(),
        };

        let weekend = dow == 0 || dow == 6;
        (tokens, leisure, dow, h, m, weekend, items)
    };

    let is_leisure_locked = leisure_locked_until > now;
    let wl_groups = db::get_all_whitelist_groups();

    let mut list = Vec::new();
    for (entity_id, display_name, daily_quota_raw, forced_blocked, target_type, pattern, weekend_quota, schedule_json, consumed) in rules_data {
        // Only a whitelisted rule as a whole is exempt here; whitelisted individual
        // sites/apps are allowed per URL (`proxy::is_whitelisted_target`) and per
        // activity (`tick_entity`), so the rest of the group still blocks.
        let is_whitelisted = db::is_item_in_whitelist_groups(&wl_groups, &entity_id);

        let (is_active_day, is_blocked_by_window) =
            evaluate_schedule_window(schedule_json.as_deref(), cur_h, cur_m, day_of_week);

        let daily_quota = if is_weekend && weekend_quota.unwrap_or(0) > 0 {
            weekend_quota.unwrap()
        } else {
            daily_quota_raw
        };
        let (daily_quota, _) = crate::holidays::apply_holiday_quota(&entity_id, daily_quota);

        let is_blocked = if is_whitelisted || !is_active_day {
            false
        } else {
            forced_blocked || penalty || consumed >= daily_quota || is_leisure_locked || is_blocked_by_window
        };
        let remaining = if is_whitelisted { daily_quota } else { (daily_quota - consumed).max(0) };

        list.push(SiteStatusItem {
            entity_id,
            display_name,
            target_type,
            pattern,
            daily_quota_seconds: daily_quota,
            consumed_seconds: consumed,
            remaining_seconds: remaining,
            is_blocked: is_blocked || (remaining == 0 && !is_whitelisted && is_active_day),
            emergency_tokens_remaining: emergency_tokens,
            is_weekend,
            weekend_quota_seconds: weekend_quota,
        });
    }
    list
}

pub fn save_rule(
    entity_id: &str,
    display_name: &str,
    daily_quota_seconds: i64,
    mode: &str,
    target_type: &str,
    pattern: &str,
    weekend_quota_seconds: Option<i64>,
    schedule_json: Option<&str>,
) -> Result<(), String> {
    if get_anti_cheat_state().is_active {
        // Anti-cheat: an existing rule/group can only be renamed (new rules are allowed).
        let conn = db::get_conn().lock();
        let existing: Option<(i64, String, String, String, Option<i64>, Option<String>)> = conn
            .query_row(
                "SELECT daily_quota_seconds, COALESCE(mode, ''), COALESCE(target_type, ''), COALESCE(pattern, ''), weekend_quota_seconds, schedule_json FROM rules WHERE entity_id = ?1",
                [entity_id],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?)),
            )
            .ok();
        drop(conn);
        if let Some((q, m, t, p, w, sch)) = existing {
            let unchanged = q == daily_quota_seconds
                && m == mode
                && t == target_type
                && same_json_text(&p, pattern)
                && w.unwrap_or(0) == weekend_quota_seconds.unwrap_or(0)
                && same_json_text(sch.as_deref().unwrap_or(""), schedule_json.unwrap_or(""));
            if !unchanged {
                return Err("Modo Anti-Burla ativo! Só é possível renomear grupos até o Anti-Burla ser desativado.".to_string());
            }
        }
    }

    // YouTube stage 3: refuse changes that create a conflict (whitelist x block, ...).
    {
        let before = crate::conflicts::load_current();
        let mut after = before.clone();
        after.rules.retain(|r| r.id != entity_id);
        after.rules.push(crate::conflicts::RuleIn {
            id: entity_id.to_string(),
            name: display_name.to_string(),
            target_type: target_type.to_string(),
            pattern: pattern.to_string(),
            schedule_json: schedule_json.map(str::to_string),
        });
        crate::conflicts::check_new(&before, &after)?;
    }

    let conn = db::get_conn().lock();
    let now = crate::trusted_time::now_secs();

    conn.execute(
        "INSERT INTO rules (entity_id, display_name, daily_quota_seconds, mode, target_type, pattern, weekend_quota_seconds, schedule_json, updated_at_utc)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
         ON CONFLICT(entity_id) DO UPDATE SET
            display_name = excluded.display_name,
            daily_quota_seconds = excluded.daily_quota_seconds,
            mode = excluded.mode,
            target_type = excluded.target_type,
            pattern = excluded.pattern,
            weekend_quota_seconds = excluded.weekend_quota_seconds,
            schedule_json = excluded.schedule_json,
            updated_at_utc = excluded.updated_at_utc",
        rusqlite::params![entity_id, display_name, daily_quota_seconds, mode, target_type, pattern, weekend_quota_seconds, schedule_json, now],
    )
    .map_err(|e| e.to_string())?;
    drop(conn);
    db::bump_state_revision();

    Ok(())
}

/// Equal as JSON when both parse (key order / spacing ignored), else as trimmed text.
pub(crate) fn same_json_text(a: &str, b: &str) -> bool {
    let (a, b) = (a.trim(), b.trim());
    if a == b {
        return true;
    }
    match (serde_json::from_str::<serde_json::Value>(a), serde_json::from_str::<serde_json::Value>(b)) {
        (Ok(x), Ok(y)) => x == y,
        _ => false,
    }
}

pub fn delete_rule(entity_id: &str) -> Result<(), String> {
    if get_anti_cheat_state().is_active {
        return Err("Modo Anti-Burla está ativo! Regras de bloqueio não podem ser removidas.".to_string());
    }

    let conn = db::get_conn().lock();
    conn.execute("DELETE FROM usage_intervals WHERE entity_id = ?1", [entity_id])
        .map_err(|e| e.to_string())?;
    conn.execute("DELETE FROM rules WHERE entity_id = ?1", [entity_id])
        .map_err(|e| e.to_string())?;
    drop(conn);
    db::bump_state_revision();
    Ok(())
}

pub fn toggle_entity_block(entity_id: &str, blocked: bool) -> Result<(), String> {
    if !blocked && get_anti_cheat_state().is_active {
        return Err("Modo Anti-Burla está ativo! O desbloqueio total é estritamente proibido até o Anti-Burla ser destravado.".to_string());
    }

    let conn = db::get_conn().lock();
    let val = if blocked { 1 } else { 0 };
    conn.execute(
        "UPDATE rules SET is_blocked_completely = ?1 WHERE entity_id = ?2",
        (val, entity_id),
    )
    .map_err(|e| e.to_string())?;
    drop(conn);
    db::bump_state_revision();
    Ok(())
}

pub fn get_quarantine_items() -> Vec<QuarantineItem> {
    let conn = db::get_conn().lock();
    let mut stmt = match conn.prepare("SELECT request_id, app_identifier, display_name, platform, status, requested_at_utc FROM install_quarantine ORDER BY CASE status WHEN 'QUARANTINED' THEN 0 ELSE 1 END, requested_at_utc DESC") {
        Ok(s) => s,
        Err(_) => return Vec::new(),
    };

    let rows = stmt.query_map([], |row| {
        Ok(QuarantineItem {
            request_id: row.get(0)?,
            app_identifier: row.get(1)?,
            display_name: row.get(2)?,
            platform: row.get(3)?,
            status: row.get(4)?,
            requested_at_utc: row.get(5)?,
        })
    });

    match rows {
        Ok(mapped) => mapped.filter_map(Result::ok).collect(),
        Err(_) => Vec::new(),
    }
}

pub fn review_quarantine(request_id: &str, approved: bool) -> Result<(), String> {
    let conn = db::get_conn().lock();
    let status = if approved { "APPROVED" } else { "REJECTED" };
    conn.execute(
        "UPDATE install_quarantine SET status = ?1 WHERE request_id = ?2",
        (status, request_id),
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn scan_system_untrusted_processes() -> Vec<QuarantineItem> {
    let mut detector = get_detector().lock();
    let untrusted_processes = detector.find_untrusted_processes();
    drop(detector);

    let conn = db::get_conn().lock();
    let now = crate::trusted_time::now_secs();
    dedupe_quarantine(&conn);
    let known: std::collections::HashSet<String> = quarantine_rows(&conn).into_iter().map(|(_, key, _)| key).collect();

    for (name, key) in untrusted_processes {
        // A program already reviewed (or waiting) is never listed again.
        if known.contains(&key) {
            continue;
        }
        let req_id = format!("quar_{:016x}", fnv1a(&key));
        let _ = conn.execute(
            "INSERT OR IGNORE INTO install_quarantine (request_id, app_identifier, display_name, platform, status, requested_at_utc)
             VALUES (?1, ?2, ?3, 'linux', 'QUARANTINED', ?4)",
            (&req_id, &key, &name, now),
        );
    }

    drop(conn);
    get_quarantine_items()
}

fn fnv1a(s: &str) -> u64 {
    s.bytes().fold(0xcbf29ce484222325u64, |h, b| (h ^ b as u64).wrapping_mul(0x100000001b3))
}

/// (request_id, normalized key, status) of every quarantine row.
fn quarantine_rows(conn: &rusqlite::Connection) -> Vec<(String, String, String)> {
    let Ok(mut stmt) = conn.prepare("SELECT request_id, app_identifier, status FROM install_quarantine") else {
        return Vec::new();
    };
    stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?)))
        .map(|rows| {
            rows.filter_map(Result::ok)
                .map(|(id, path, st)| (id, crate::detector::quarantine_key(&path), st))
                .collect()
        })
        .unwrap_or_default()
}

/// Old scans stored one row per scan: keep one row per program (the reviewed one wins).
fn dedupe_quarantine(conn: &rusqlite::Connection) {
    let mut rows = quarantine_rows(conn);
    // Reviewed rows first, so they are the ones kept.
    rows.sort_by_key(|(_, _, st)| if st == "QUARANTINED" { 1 } else { 0 });
    let mut seen = std::collections::HashSet::new();
    for (id, key, _) in rows {
        if !seen.insert(key) {
            let _ = conn.execute("DELETE FROM install_quarantine WHERE request_id = ?1", [&id]);
        }
    }
}

/// Rejected programs (parental quarantine) are closed whenever they start.
pub fn enforce_rejected_quarantine() {
    let keys: std::collections::HashSet<String> = {
        let conn = db::get_conn().lock();
        quarantine_rows(&conn)
            .into_iter()
            .filter(|(_, _, st)| st == "REJECTED")
            .map(|(_, key, _)| key)
            .collect()
    };
    if keys.is_empty() {
        return;
    }
    for name in get_detector().lock().kill_by_quarantine_keys(&keys) {
        eprintln!("chronos quarantine: closed rejected program {name}");
    }
}

// ------------------ DETECÇÃO AUTOMÁTICA & ANTI-CHEAT ------------------

/// Last second each entity was active but not counted (see [`should_extend_interval`]).
static LAST_NONCOUNTED: std::sync::LazyLock<Mutex<std::collections::HashMap<String, i64>>> =
    std::sync::LazyLock::new(|| Mutex::new(std::collections::HashMap::new()));

/// A counted tick extends the latest usage interval only when it ended at most 3 s ago
/// (tick jitter) and no uncounted (exempt/whitelisted) second happened since then;
/// otherwise a new interval starts, so exempt gaps are never charged.
pub(crate) fn should_extend_interval(last_ended: i64, now: i64, last_noncounted: Option<i64>) -> bool {
    last_ended >= now - 3 && !matches!(last_noncounted, Some(nc) if nc >= last_ended && nc <= now)
}

/// True when the entity's usage was extended within the last 2 seconds (time is running).
pub fn is_entity_counting(entity_id: &str) -> bool {
    let Some(conn) = db::try_get_conn() else { return false };
    let conn = conn.lock();
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    conn.query_row(
        "SELECT COALESCE(MAX(ended_at_utc), 0) FROM usage_intervals WHERE entity_id = ?1",
        [entity_id],
        |r| r.get::<_, i64>(0),
    )
    .map(|last| last >= now - 2)
    .unwrap_or(false)
}

static LAST_ACTIVE_ENTITY: parking_lot::Mutex<Option<String>> = parking_lot::Mutex::new(None);

pub const STAYFOCUSD_CHALLENGE_TEXT: &str =
    "Eu reconheço plenamente que alterar meus limites agora é uma tentativa de ceder à procrastinação. Meus objetivos a longo prazo dependem da minha disciplina e consistência diária. Eu escolho manter o foco e cumprir minhas metas acima de qualquer distração passageira.";

/// Built-in challenge texts (one is drawn each time the challenge mode is activated).
pub const BUILTIN_CHALLENGE_TEXTS: [&str; 4] = [
    STAYFOCUSD_CHALLENGE_TEXT,
    "Eu sei que a vontade de liberar agora vai passar em poucos minutos. Cada vez que eu resisto, fica mais fácil resistir de novo. Eu prefiro o orgulho de ter cumprido o meu plano do que o alívio rápido de uma distração que eu mesmo decidi evitar.",
    "Os limites que eu configurei foram escolhidos com a cabeça fria, pensando no meu futuro. Desfazer esses limites num momento de impulso seria trair a pessoa que eu quero ser. Eu vou respirar fundo, voltar para a minha tarefa e terminar o que comecei.",
    "Tempo é o recurso mais valioso que eu tenho e não volta. Se eu liberar agora, vou trocar horas de progresso por alguns minutos de distração. Eu reconheço esse impulso, aceito que ele existe e mesmo assim escolho manter o meu compromisso com o foco.",
];
pub const MIN_CUSTOM_CHALLENGE_LEN: usize = 120;
const CUSTOM_CHALLENGES_KEY: &str = "anti_cheat_custom_texts";
const CURRENT_CHALLENGE_KEY: &str = "anti_cheat_current_text";

const STRENGTH_CHECK_KEY: &str = "challenge_strength_check";

/// Optional check that refuses custom challenge texts that are too easy to type (on by
/// default).
pub fn challenge_strength_check_enabled() -> bool {
    db::get_config(STRENGTH_CHECK_KEY).map_or(true, |v| v != "0")
}

pub fn set_challenge_strength_check(enabled: bool) -> Result<(), String> {
    if get_anti_cheat_state().is_active {
        return Err("Anti-Burla ativo: os textos do desafio não podem ser alterados agora.".to_string());
    }
    db::set_config(STRENGTH_CHECK_KEY, if enabled { "1" } else { "0" }).map_err(|e| e.to_string())
}

/// Why a challenge text is too easy to type (empty = fine). Messages are Portuguese
/// sources translated by `i18n::tr_msg`.
pub fn challenge_text_issues(text: &str) -> Vec<String> {
    let t = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut issues = Vec::new();
    let chars = t.chars().count();
    if chars < MIN_CUSTOM_CHALLENGE_LEN {
        issues.push(format!("Curto demais: {chars} de {MIN_CUSTOM_CHALLENGE_LEN} caracteres."));
    }
    let lower = t.to_lowercase();
    let words: Vec<&str> = lower
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .collect();
    if words.len() < 20 {
        issues.push("Poucas palavras: escreva frases (pelo menos 20 palavras).".to_string());
    }
    if words.len() >= 10 {
        let unique: std::collections::HashSet<&&str> = words.iter().collect();
        if (unique.len() as f32) < words.len() as f32 * 0.5 {
            issues.push("Muitas palavras repetidas.".to_string());
        }
        let mut counts: std::collections::HashMap<&str, usize> = std::collections::HashMap::new();
        for w in &words {
            *counts.entry(w).or_default() += 1;
        }
        if counts.values().any(|&c| c * 4 > words.len() && c > 3) {
            issues.push("Uma palavra se repete demais.".to_string());
        }
    }
    let letters: std::collections::HashSet<char> = lower.chars().filter(|c| c.is_alphabetic()).collect();
    if letters.len() < 12 {
        issues.push("Poucas letras diferentes.".to_string());
    }
    // "aaaaa", "!!!!!"
    let mut run = 1;
    let mut prev = None;
    let mut long_run = false;
    for c in lower.chars().filter(|c| !c.is_whitespace()) {
        if Some(c) == prev {
            run += 1;
            long_run |= run >= 4;
        } else {
            run = 1;
        }
        prev = Some(c);
    }
    if long_run {
        issues.push("Letras repetidas em sequência.".to_string());
    }
    // A short block copied over and over ("abc abc abc ...").
    let compact: Vec<char> = lower.chars().filter(|c| !c.is_whitespace()).collect();
    if compact.len() >= 12 {
        let n = compact.len();
        let mut pi = vec![0usize; n];
        for i in 1..n {
            let mut k = pi[i - 1];
            while k > 0 && compact[i] != compact[k] {
                k = pi[k - 1];
            }
            if compact[i] == compact[k] {
                k += 1;
            }
            pi[i] = k;
        }
        if pi[n - 1] * 3 >= n * 2 {
            issues.push("O texto é um mesmo trecho repetido.".to_string());
        }
    }
    let squeezed: String = compact.iter().collect();
    if ["qwert", "asdfg", "zxcvb", "12345", "abcdef", "poiuy", "lkjhg"].iter().any(|p| squeezed.contains(p)) {
        issues.push("Sequência de teclado (qwerty, asdf, 12345…).".to_string());
    }
    issues
}

pub fn custom_challenge_texts() -> Vec<String> {
    db::get_config(CUSTOM_CHALLENGES_KEY)
        .and_then(|raw| serde_json::from_str::<Vec<String>>(&raw).ok())
        .unwrap_or_default()
}

/// Saves the user's own challenge texts (each at least [`MIN_CUSTOM_CHALLENGE_LEN`]
/// characters). Refused while anti-cheat is active.
pub fn set_custom_challenge_texts(texts: Vec<String>) -> Result<(), String> {
    if get_anti_cheat_state().is_active {
        return Err("Anti-Burla ativo: os textos do desafio não podem ser alterados agora.".to_string());
    }
    let mut clean: Vec<String> = Vec::new();
    for t in texts {
        let t = t.split_whitespace().collect::<Vec<_>>().join(" ");
        if t.is_empty() {
            continue;
        }
        if t.chars().count() < MIN_CUSTOM_CHALLENGE_LEN {
            return Err(format!(
                "Cada texto precisa ter pelo menos {MIN_CUSTOM_CHALLENGE_LEN} caracteres (\"{}…\" é curto demais).",
                t.chars().take(30).collect::<String>()
            ));
        }
        if challenge_strength_check_enabled() {
            if let Some(first) = challenge_text_issues(&t).into_iter().next() {
                return Err(format!(
                    "Texto fácil demais (\"{}…\"): {first}",
                    t.chars().take(30).collect::<String>()
                ));
            }
        }
        if !clean.contains(&t) {
            clean.push(t);
        }
    }
    db::set_config(CUSTOM_CHALLENGES_KEY, &serde_json::to_string(&clean).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())
}

/// Text the user must type to leave challenge mode (drawn at activation).
pub fn current_challenge_text() -> String {
    db::get_config(CURRENT_CHALLENGE_KEY)
        .filter(|t| !t.trim().is_empty())
        .unwrap_or_else(|| STAYFOCUSD_CHALLENGE_TEXT.to_string())
}

/// The user's own texts replace the built-in ones; without them, the built-ins are used
/// (`custom` = JSON list stored in app_config).
pub fn challenge_pool(custom_json: &str) -> Vec<String> {
    let custom: Vec<String> = serde_json::from_str::<Vec<String>>(custom_json)
        .unwrap_or_default()
        .into_iter()
        .filter(|t| t.chars().count() >= MIN_CUSTOM_CHALLENGE_LEN)
        .collect();
    if custom.is_empty() {
        BUILTIN_CHALLENGE_TEXTS.iter().map(|t| t.to_string()).collect()
    } else {
        custom
    }
}

fn draw_challenge_text_except(current: &str) -> String {
    let pool = challenge_pool(&db::get_config(CUSTOM_CHALLENGES_KEY).unwrap_or_default());
    let candidates: Vec<&String> = pool.iter().filter(|t| t.trim() != current.trim()).collect();
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.subsec_nanos() as usize)
        .unwrap_or(0);
    if candidates.is_empty() {
        return pool[nanos % pool.len()].clone();
    }
    candidates[nanos % candidates.len()].clone()
}

fn draw_challenge_text() -> String {
    draw_challenge_text_except("")
}

/// Draws a different challenge text (called whenever the challenge dialog is closed).
pub fn redraw_challenge_text() -> Result<(), String> {
    let state = get_anti_cheat_state();
    if !state.is_active || state.mode != "CHALLENGE" {
        return Ok(());
    }
    let next = draw_challenge_text_except(&state.challenge_text);
    db::set_config(CURRENT_CHALLENGE_KEY, &next).map_err(|e| e.to_string())?;
    let _ = db::bump_state_revision();
    Ok(())
}

#[derive(Clone, Debug)]
pub struct AntiCheatStateItem {
    pub is_active: bool,
    pub mode: String, // "OFF", "CHALLENGE", "NUKE"
    pub nuke_remaining_seconds: i64,
    pub challenge_text: String,
}

pub fn get_anti_cheat_state() -> AntiCheatStateItem {
    let mode = db::get_config("anti_cheat_mode").unwrap_or_else(|| "OFF".to_string());
    let now = crate::trusted_time::now_secs();
    let nuke_until = db::get_config("anti_cheat_nuke_until_utc").and_then(|s| s.parse::<i64>().ok()).unwrap_or(0);

    let is_active = if mode == "NUKE" {
        now < nuke_until
    } else {
        mode == "CHALLENGE"
    };

    let remaining = if mode == "NUKE" && now < nuke_until {
        nuke_until - now
    } else {
        0
    };

    AntiCheatStateItem {
        is_active,
        mode: if is_active { mode } else { "OFF".to_string() },
        nuke_remaining_seconds: remaining,
        challenge_text: current_challenge_text(),
    }
}

pub fn enable_anti_cheat(mode: &str, nuke_seconds: Option<i64>) -> Result<(), String> {
    let now = crate::trusted_time::now_secs();
    if mode == "NUKE" {
        let duration = nuke_seconds.unwrap_or(3600 * 4); // Default 4h
        let until = now + duration;
        db::set_config("anti_cheat_mode", "NUKE").map_err(|e| e.to_string())?;
        db::set_config("anti_cheat_nuke_until_utc", &until.to_string()).map_err(|e| e.to_string())?;
    } else {
        db::set_config(CURRENT_CHALLENGE_KEY, &draw_challenge_text()).map_err(|e| e.to_string())?;
        db::set_config("anti_cheat_mode", "CHALLENGE").map_err(|e| e.to_string())?;
        db::set_config("anti_cheat_nuke_until_utc", "0").map_err(|e| e.to_string())?;
    }
    enforce_anti_cheat_watchdog();
    let _ = db::bump_state_revision();
    Ok(())
}

pub fn disable_anti_cheat(verification_token: &str) -> Result<(), String> {
    let state = get_anti_cheat_state();
    if !state.is_active {
        return Ok(());
    }

    if state.mode == "NUKE" {
        return Err(format!(
            "Modo Nuke Ativo! O bloqueio permanecerá até o fim do cronômetro. Restam {} segundos.",
            state.nuke_remaining_seconds
        ));
    }

    let expected = current_challenge_text();
    let clean_received = verification_token.trim();
    // The challenge is shown in the app language: any version of the text is accepted.
    if !crate::i18n::variants(&expected).iter().any(|v| v.trim() == clean_received) {
        return Err("Texto do desafio incorreto. O desafio exige digitação com 100% de precisão sem erros.".to_string());
    }

    // With the root vault installed, only the vault can turn anti-cheat off (editing the
    // database alone is reverted), so it verifies the challenge text too.
    if crate::vault::read_published_state().is_some() {
        unlock_through_vault(clean_received)?;
    }
    db::set_config("anti_cheat_mode", "OFF").map_err(|e| e.to_string())?;
    db::set_config("anti_cheat_nuke_until_utc", "0").map_err(|e| e.to_string())?;
    let _ = db::bump_state_revision();
    Ok(())
}

pub const VAULT_BINARY: &str = "/usr/local/lib/chronos/chronos_vault";

fn unlock_through_vault(text: &str) -> Result<(), String> {
    use std::io::Write;
    if !std::path::Path::new(VAULT_BINARY).exists() {
        return Ok(());
    }
    let db_path = db::get_conn().lock().path().map(str::to_string).unwrap_or_default();
    let user = crate::vault::current_user();
    let mut child = std::process::Command::new("pkexec")
        .args([VAULT_BINARY, "unlock", "--user", &user, "--db", &db_path])
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| format!("Falha ao falar com o cofre do Chronos: {e}"))?;
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(text.as_bytes());
    }
    let out = child.wait_with_output().map_err(|e| e.to_string())?;
    if out.status.success() {
        Ok(())
    } else {
        let err = String::from_utf8_lossy(&out.stderr).trim().to_string();
        Err(if err.is_empty() { "O cofre do Chronos recusou o desbloqueio.".to_string() } else { err })
    }
}

pub fn debug_disable_anti_cheat() -> Result<(), String> {
    db::set_config("anti_cheat_mode", "OFF").map_err(|e| e.to_string())?;
    db::set_config("anti_cheat_nuke_until_utc", "0").map_err(|e| e.to_string())?;
    let _ = db::bump_state_revision();
    Ok(())
}

pub fn enforce_anti_cheat_watchdog() {
    let state = get_anti_cheat_state();
    if !state.is_active {
        return;
    }

    if let Ok(home) = std::env::var("HOME") {
        let config_root = std::path::PathBuf::from(&home).join(".config");
        if let Ok(entries) = std::fs::read_dir(config_root) {
            for entry in entries.flatten() {
                let p = entry.path();
                if p.join("Default/Preferences").exists() {
                    let dir_path = p.join("External Extensions");
                    let _ = std::fs::create_dir_all(&dir_path);
                }
            }
        }
    }
}

pub fn tick_auto() -> Option<TickState> {
    enforce_anti_cheat_watchdog();
    let _ = crate::launchers::detect_and_enforce_launcher_filters();

    let (all_rules, day_of_week, cur_h, cur_m) = {
        let conn = db::get_conn().lock();
        let (dow, h, m): (i32, i32, i32) = conn
            .query_row(
                "SELECT CAST(strftime('%w', ?1, 'unixepoch', 'localtime') AS INTEGER), CAST(strftime('%H', ?1, 'unixepoch', 'localtime') AS INTEGER), CAST(strftime('%M', ?1, 'unixepoch', 'localtime') AS INTEGER)",
                [crate::trusted_time::now_secs()],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .unwrap_or((1, 12, 0));

        let mut stmt = match conn.prepare("SELECT entity_id, display_name, COALESCE(target_type, 'APP'), COALESCE(pattern, ''), schedule_json FROM rules ORDER BY display_name ASC") {
            Ok(s) => s,
            Err(_) => {
                return Some(TickState {
                    entity_id: "idle".to_string(),
                    display_name: "Detecção Automática".to_string(),
                    remaining_seconds: 0,
                    daily_quota_seconds: 0,
                    consumed_seconds: 0,
                    is_active_now: false,
                    is_background_playback: false,
                    is_blocked: false,
                    detected_activity_label: "Aguardando cadastro de regras".to_string(),
                    ratchet_locked_until_utc: None,
                    emergency_tokens_remaining: 2,
                    leisure_locked_until_utc: 0,
                    target_type: "NONE".to_string(),
                    is_weekend: false,
                    weekend_quota_seconds: None,
                    active_sessions_json: "[]".to_string(),
                });
            }
        };
        let rows = match stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, Option<String>>(4)?,
            ))
        }) {
            Ok(mapped) => mapped.filter_map(Result::ok).collect::<Vec<_>>(),
            Err(_) => Vec::new(),
        };
        (rows, dow, h, m)
    };

    if all_rules.is_empty() {
        return Some(TickState {
            entity_id: "idle".to_string(),
            display_name: "Detecção Automática".to_string(),
            remaining_seconds: 0,
            daily_quota_seconds: 0,
            consumed_seconds: 0,
            is_active_now: false,
            is_background_playback: false,
            is_blocked: false,
            detected_activity_label: "Nenhuma regra de bloqueio criada".to_string(),
            ratchet_locked_until_utc: None,
            emergency_tokens_remaining: 2,
            leisure_locked_until_utc: 0,
            target_type: "NONE".to_string(),
            is_weekend: false,
            weekend_quota_seconds: None,
            active_sessions_json: "[]".to_string(),
        });
    }

    let active_details = ActivityDetector::get_active_window_details();
    let win_lower = active_details.title.to_lowercase();
    let (browser_url_lower, browser_title_lower) =
        ActivityDetector::get_active_browser_context(&active_details);
    let all_windows_info = ActivityDetector::get_all_windows_info();

    let mut active_entities: Vec<(String, Option<String>)> = Vec::new();

    // 1. Varre todas as regras cadastradas procurando quais sessões/grupos estão ativos agora
    for (entity_id, display_name, target_type, pattern, sched_opt) in &all_rules {
        let (is_active_day, _is_blocked_by_window) =
            evaluate_schedule_window(sched_opt.as_deref(), cur_h, cur_m, day_of_week);
        if !is_active_day {
            continue;
        }

        let mut is_active = false;
        match target_type.as_str() {
            "GROUP" => {
                let (apps, sites) = parse_group_pattern_rich(pattern);
                for app in &apps {
                    if evaluate_app_target_activity(app, &active_details, &win_lower, &all_windows_info).is_some() {
                        is_active = true;
                        break;
                    }
                }
                if !is_active {
                    let app_names: Vec<String> = apps.iter().map(|a| a.name.clone()).collect();
                    let (has_app_media, _) = ActivityDetector::is_media_playing_for_patterns(&app_names);
                    if has_app_media {
                        is_active = true;
                    }
                }
                if !is_active {
                    for d in &sites {
                        if matches_site_or_keyword(d, &win_lower, &browser_url_lower, &browser_title_lower) {
                            is_active = true;
                            break;
                        }
                    }
                }
                if !is_active && !sites.is_empty() {
                    let (has_media, _) = ActivityDetector::is_media_playing_for_patterns(&sites);
                    if has_media {
                        is_active = true;
                    }
                }
            }
            "SITE_GROUP" | "KEYWORD" | "SITE" => {
                let items: Vec<String> = if pattern.is_empty() {
                    vec![entity_id.to_string()]
                } else if pattern.trim().starts_with('{') {
                    parse_group_pattern(&pattern).1
                } else {
                    pattern
                        .split(',')
                        .map(|s| s.trim().to_string())
                        .filter(|s| !s.is_empty())
                        .collect()
                };
                for item in &items {
                    if matches_site_or_keyword(item, &win_lower, &browser_url_lower, &browser_title_lower) {
                        is_active = true;
                        break;
                    }
                }
                if !is_active {
                    let (has_media, _) = ActivityDetector::is_media_playing_for_patterns(&items);
                    if has_media {
                        is_active = true;
                    }
                }
            }
            _ => {
                let target = if pattern.is_empty() { entity_id.as_str() } else { pattern.as_str() };
                let app = AppTarget {
                    name: display_name.clone(),
                    exec: target.to_string(),
                };
                if evaluate_app_target_activity(&app, &active_details, &win_lower, &all_windows_info).is_some()
                    || ActivityDetector::is_media_playing_in_background(&target.to_lowercase()).0
                {
                    is_active = true;
                }
            }
        }

        if is_active {
            active_entities.push((entity_id.clone(), sched_opt.clone()));
        }
    }

    if !active_entities.is_empty() {
        let mut active_ticks: Vec<TickState> = Vec::new();
        let mut session_items: Vec<ActiveSessionItem> = Vec::new();

        for (eid, sched_opt) in &active_entities {
            if let Some(t) = tick_entity(eid) {
                let (notify_mode, notify_interval_mins, notify_remaining_mins) =
                    parse_notification_settings(sched_opt.as_deref());
                session_items.push(ActiveSessionItem {
                    entity_id: t.entity_id.clone(),
                    display_name: t.display_name.clone(),
                    remaining_seconds: t.remaining_seconds,
                    daily_quota_seconds: t.daily_quota_seconds,
                    consumed_seconds: t.consumed_seconds,
                    is_blocked: t.is_blocked,
                    target_type: t.target_type.clone(),
                    detected_activity_label: t.detected_activity_label.clone(),
                    notify_mode,
                    notify_interval_mins,
                    notify_remaining_mins,
                });
                active_ticks.push(t);
            }
        }

        if !active_ticks.is_empty() {
            *LAST_ACTIVE_ENTITY.lock() = Some(active_entities[0].0.clone());
            let mut primary = active_ticks[0].clone();
            primary.active_sessions_json = serde_json::to_string(&session_items).unwrap_or_else(|_| "[]".to_string());
            return Some(primary);
        }
    }

    // Se nenhuma distração ativa agora, exibe a última utilizada ou a primeira regra cadastrada
    let fallback = {
        let last = LAST_ACTIVE_ENTITY.lock();
        last.clone().unwrap_or_else(|| all_rules[0].0.clone())
    };

    if let Some(mut tick) = tick_entity(&fallback) {
        tick.is_active_now = false;
        tick.active_sessions_json = "[]".to_string();
        return Some(tick);
    }

    if let Some(mut tick) = tick_entity(&all_rules[0].0) {
        tick.is_active_now = false;
        tick.active_sessions_json = "[]".to_string();
        return Some(tick);
    }

    Some(TickState {
        entity_id: "idle".to_string(),
        display_name: "Detecção Automática".to_string(),
        remaining_seconds: 0,
        daily_quota_seconds: 0,
        consumed_seconds: 0,
        is_active_now: false,
        is_background_playback: false,
        is_blocked: false,
        detected_activity_label: "Nenhuma distração ativa no momento".to_string(),
        ratchet_locked_until_utc: None,
        emergency_tokens_remaining: 2,
        leisure_locked_until_utc: 0,
        target_type: "NONE".to_string(),
        is_weekend: false,
        weekend_quota_seconds: None,
        active_sessions_json: "[]".to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::detector::{ActiveWindowDetails, WindowInfo};

    #[test]
    fn challenge_text_pool_custom_texts_and_anti_cheat_lock() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db_file = format!("/tmp/chronos_challenge_{}.db", std::process::id());
        let _ = std::fs::remove_file(&db_file);
        db::init_db(&db_file).expect("init temp db");

        assert!(set_custom_challenge_texts(vec!["curto".into()]).is_err(), "too short");
        // Strength check (on by default) refuses easy texts.
        assert!(set_custom_challenge_texts(vec!["x".repeat(MIN_CUSTOM_CHALLENGE_LEN)]).is_err(), "easy text refused");
        assert!(!challenge_text_issues(&"abc def ".repeat(30)).is_empty());
        assert!(!challenge_text_issues(&format!("{} asdfgh", BUILTIN_CHALLENGE_TEXTS[1])).is_empty());
        for t in BUILTIN_CHALLENGE_TEXTS {
            assert!(challenge_text_issues(t).is_empty(), "built-in text passes: {:?}", challenge_text_issues(t));
        }
        set_challenge_strength_check(false).unwrap();
        let mine = "x".repeat(MIN_CUSTOM_CHALLENGE_LEN);
        set_custom_challenge_texts(vec![mine.clone(), "  ".into(), mine.clone()]).unwrap();
        assert_eq!(custom_challenge_texts(), vec![mine.clone()]);

        // Custom texts replace the built-in ones.
        let mine2 = "y".repeat(MIN_CUSTOM_CHALLENGE_LEN);
        set_custom_challenge_texts(vec![mine.clone(), mine2.clone()]).unwrap();
        assert_eq!(challenge_pool(&serde_json::to_string(&[&mine, &mine2]).unwrap()), vec![mine.clone(), mine2.clone()]);
        assert_eq!(challenge_pool("[]").len(), BUILTIN_CHALLENGE_TEXTS.len(), "no custom texts: built-ins");

        enable_anti_cheat("CHALLENGE", None).unwrap();
        let first = current_challenge_text();
        assert!(first == mine || first == mine2, "only custom texts are drawn");
        redraw_challenge_text().unwrap();
        assert_ne!(current_challenge_text(), first, "closing the challenge draws another text");
        let drawn = current_challenge_text();
        assert!(drawn == mine || drawn == mine2);
        assert_eq!(get_anti_cheat_state().challenge_text, drawn);
        assert!(set_custom_challenge_texts(vec![]).is_err(), "locked while active");

        // Anti-cheat: existing rule can only be renamed
        let pat = r#"{"apps":[{"name":"A","exec":"a"}],"sites":[]}"#;
        save_rule("g1", "Grupo", 600, "QUOTA", "GROUP", pat, None, None).unwrap(); // new rule ok
        save_rule("g1", "Novo nome", 600, "QUOTA", "GROUP", r#"{"sites":[],"apps":[{"exec":"a","name":"A"}]}"#, None, None)
            .expect("rename (same pattern, other key order)");
        assert!(save_rule("g1", "Novo nome", 300, "QUOTA", "GROUP", pat, None, None).is_err(), "quota locked");
        assert!(save_rule("g1", "Novo nome", 600, "QUOTA", "GROUP", r#"{"apps":[],"sites":[]}"#, None, None).is_err(), "items locked");
        assert!(save_rule("g1", "Novo nome", 600, "QUOTA", "GROUP", pat, None, Some(r#"{"x":1}"#)).is_err(), "schedule locked");
        assert!(disable_anti_cheat("errado").is_err());
        disable_anti_cheat(&drawn).unwrap();
        assert!(!get_anti_cheat_state().is_active);

        let _ = std::fs::remove_file(db_file);
    }

    #[test]
    fn exempt_gap_is_not_bridged_by_next_counted_tick() {
        // counted until 100, next counted at 101: extend
        assert!(should_extend_interval(100, 101, None));
        // jitter: one skipped second still extends
        assert!(should_extend_interval(100, 102, None));
        // exempt at 101, counted again at 102: new interval (101 not charged)
        assert!(!should_extend_interval(100, 102, Some(101)));
        // old exempt second before the interval end does not matter
        assert!(should_extend_interval(100, 101, Some(90)));
        // stale interval
        assert!(!should_extend_interval(100, 105, None));
    }

    #[test]
    fn normalize_desktop_exec_preserves_steam_game_uri() {
        assert_eq!(
            normalize_desktop_exec("steam steam://rungameid/730"),
            Some("steam://rungameid/730".to_string())
        );
        assert_eq!(
            normalize_desktop_exec("steam -applaunch 1245620 %U"),
            Some("steam://rungameid/1245620".to_string())
        );
        assert_eq!(
            normalize_desktop_exec("/usr/bin/steam %U"),
            Some("steam".to_string())
        );
        assert_eq!(
            normalize_desktop_exec(
                "/home/dwu/.local/share/chronos/bin/chronos-launcher-env /usr/bin/steam %U"
            ),
            Some("steam".to_string())
        );
        assert_eq!(
            normalize_desktop_exec("env LUTRIS_SKIP_INIT=1 lutris lutris:rungameid/42"),
            Some("lutris:rungameid/42".to_string())
        );
    }

    #[test]
    fn launcher_hosted_game_does_not_match_steam_client_window() {
        let game = AppTarget {
            name: "Counter-Strike 2".to_string(),
            exec: "steam".to_string(),
        };
        assert!(game.is_launcher());
        assert!(game.is_launcher_hosted_game());

        let steam_launcher = AppTarget {
            name: "Steam".to_string(),
            exec: "steam".to_string(),
        };
        assert!(steam_launcher.is_launcher());
        assert!(!steam_launcher.is_launcher_hosted_game());

        let active_steam = ActiveWindowDetails {
            class: "steam".to_string(),
            initial_class: "steam".to_string(),
            title: "Steam".to_string(),
            pid: 1000,
            is_browser: false,
        };
        let steam_win = WindowInfo {
            address: "0x1".to_string(),
            class: "steam".to_string(),
            initial_class: "steam".to_string(),
            title: "Steam".to_string(),
            pid: 1000,
        };

        // Abrir apenas a Steam NÃO deve contar tempo nem disparar atividade para jogo Steam!
        assert_eq!(
            evaluate_app_target_activity(&game, &active_steam, "steam", &[steam_win.clone()]),
            None
        );

        // Quando a própria Steam foi adicionada explicitamente ao grupo, ela DEVE ser detectada.
        assert!(
            evaluate_app_target_activity(&steam_launcher, &active_steam, "steam", &[steam_win])
                .is_some()
        );

        // Quando a janela real do jogo abre (`steam_app_730`), o jogo É detectado.
        let cs_game = AppTarget {
            name: "Counter-Strike 2".to_string(),
            exec: "steam://rungameid/730".to_string(),
        };
        let cs_win = WindowInfo {
            address: "0x2".to_string(),
            class: "steam_app_730".to_string(),
            initial_class: "steam_app_730".to_string(),
            title: "Counter-Strike 2".to_string(),
            pid: 2000,
        };
        assert!(
            evaluate_app_target_activity(&cs_game, &active_steam, "steam", &[cs_win]).is_some()
        );
    }
}
