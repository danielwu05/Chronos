use std::collections::HashMap;
use std::process::Command;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::OnceLock;
use std::time::{SystemTime, UNIX_EPOCH};
use sysinfo::{ProcessesToUpdate, System};

static LAST_YOUTUBE_SEEN_UTC: AtomicI64 = AtomicI64::new(0);
static IS_HYPRLAND: OnceLock<bool> = OnceLock::new();
static WINDOW_INFO_CACHE: parking_lot::Mutex<Option<(i64, Vec<WindowInfo>)>> = parking_lot::Mutex::new(None);
static BROWSER_HISTORY_CACHE: parking_lot::Mutex<Option<(i64, Vec<(String, String)>)>> = parking_lot::Mutex::new(None);
static PLAYERCTL_CACHE: parking_lot::Mutex<Option<(i64, Vec<Vec<String>>)>> = parking_lot::Mutex::new(None);

pub fn extract_binary_basename(exec_or_name: &str) -> String {
    let s = exec_or_name.trim();
    if s.is_empty() {
        return String::new();
    }
    let lower = s.to_lowercase();
    if lower.starts_with("steam://")
        || lower.starts_with("heroic://")
        || lower.starts_with("lutris:")
    {
        return String::new();
    }
    let parts: Vec<&str> = s.split_whitespace().collect();
    let bin_part = if parts.len() >= 3 && parts[0] == "flatpak" && parts[1] == "run" {
        parts[2].rsplit('.').next().unwrap_or(parts[2])
    } else if !parts.is_empty() {
        parts[0]
    } else {
        s
    };
    let path = std::path::Path::new(bin_part);
    let base = path.file_name().and_then(|n| n.to_str()).unwrap_or(bin_part);
    base.to_lowercase()
}

/// A process is the app only when its name or executable basename IS the target binary
/// (text in arguments never matches: `grep youtube`, `nvim youtube.rs`, test runners…).
/// `comm` names are truncated to 15 chars by the kernel.
pub fn process_identity_matches(clean_target: &str, proc_name: &str, proc_exe: &str) -> bool {
    if clean_target.is_empty() {
        return false;
    }
    let truncated: String = clean_target.chars().take(15).collect();
    let name_ok = proc_name == clean_target || (clean_target.chars().count() > 15 && proc_name == truncated);
    let exe_base = std::path::Path::new(proc_exe)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("");
    name_ok || (!exe_base.is_empty() && exe_base == clean_target)
}

/// Whether a process is the target app: `Some(true)` by its own name / executable,
/// `Some(false)` through a wrapper (interpreter command line, systemd scope, AppImage,
/// renamed copy; see [`crate::wrappers`]), `None` otherwise.
fn process_matches_target(process: &sysinfo::Process, clean_target: &str, raw_target: &str) -> Option<bool> {
    let proc_name = process.name().to_string_lossy().to_lowercase();
    let proc_exe_raw = process.exe().map(|p| p.to_string_lossy().to_string()).unwrap_or_default();
    if process_identity_matches(clean_target, &proc_name, &proc_exe_raw.to_lowercase()) {
        return Some(true);
    }
    let pid = process.pid().as_u32();
    if pid == std::process::id() || proc_name.starts_with("chronos") || clean_target.is_empty() {
        return None;
    }
    let tokens = crate::wrappers::process_tokens(pid, process.start_time(), &proc_name, &proc_exe_raw);
    if crate::wrappers::tokens_match(raw_target, &tokens) || crate::wrappers::is_renamed_copy(raw_target, &proc_exe_raw) {
        return Some(false);
    }
    None
}

pub fn is_generic_launcher_token(token: &str) -> bool {
    matches!(
        token.trim().to_lowercase().as_str(),
        "steam"
            | "steam.exe"
            | "steam (runtime)"
            | "com.valvesoftware.steam"
            | "steamwebhelper"
            | "heroic"
            | "heroic games launcher"
            | "heroicgameslauncher"
            | "com.heroicgameslauncher.hgl"
            | "lutris"
            | "net.lutris.lutris"
            | "wine"
            | "wine64"
            | "proton"
            | "bottles"
    )
}

pub fn is_lutris_client_process(proc_name_lower: &str, cmd_joined_lower: &str) -> bool {
    matches!(proc_name_lower, "lutris" | "net.lutris.lutris")
        || ((proc_name_lower.starts_with("python") || proc_name_lower == "py")
            && (cmd_joined_lower.contains("/lutris")
                || cmd_joined_lower.contains(" -m lutris")
                || cmd_joined_lower.contains("net.lutris.lutris")))
}

pub fn read_process_environ_from_bytes(bytes: &[u8]) -> HashMap<String, String> {
    let mut map = HashMap::new();
    for chunk in bytes.split(|&b| b == 0) {
        if chunk.is_empty() {
            continue;
        }
        let s = String::from_utf8_lossy(chunk);
        if let Some((k, v)) = s.split_once('=') {
            if !k.is_empty() {
                map.insert(k.to_string(), v.to_string());
            }
        }
    }
    map
}

pub fn read_process_environ_map(pid: u32) -> HashMap<String, String> {
    #[cfg(target_os = "linux")]
    {
        if pid == 0 {
            return HashMap::new();
        }
        let path = format!("/proc/{pid}/environ");
        match std::fs::read(&path) {
            Ok(bytes) => read_process_environ_from_bytes(&bytes),
            Err(_) => HashMap::new(),
        }
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = pid;
        HashMap::new()
    }
}

fn parse_numeric_appid_token(raw: &str) -> Option<i64> {
    let lower = raw.trim().trim_matches(['"', '\'']).to_ascii_lowercase();
    let trimmed = lower
        .strip_prefix("umu-")
        .or_else(|| lower.strip_prefix("steam-"))
        .unwrap_or(&lower);
    if trimmed.is_empty() || !trimmed.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let id = trimmed.parse::<i64>().ok()?;
    // Steam Store App IDs fit comfortably below 2^31; higher values are Steam shortcut CRCs.
    (id > 0 && id < 2_000_000_000).then_some(id)
}

pub fn extract_steam_appid_from_env(env: &HashMap<String, String>) -> Option<i64> {
    for key in ["SteamAppId", "STEAM_APPID", "SteamGameId", "UMU_ID", "GAMEID"] {
        if let Some(val) = env.get(key) {
            if let Some(id) = parse_numeric_appid_token(val) {
                return Some(id);
            }
        }
    }
    None
}

fn is_ignored_wrapper_exec_token(base: &str) -> bool {
    is_generic_launcher_token(base)
        || matches!(
            base,
            "wine64-preloader"
                | "wine-preloader"
                | "wineserver"
                | "umu-run"
                | "reaper"
                | "pressure-vessel"
                | "bash"
                | "sh"
                | "env"
                | "python"
                | "python3"
                | "explorer.exe"
                | "services.exe"
                | "winedevice.exe"
                | "plugplay.exe"
                | "svchost.exe"
                | "rpcss.exe"
        )
}

/// Extracts `(basename, stem)` pairs from a game `exec_hint` (supports Unix and Windows paths).
pub fn extract_game_exec_candidates(exec_hint: &str) -> Vec<(String, String)> {
    let trimmed = exec_hint.trim();
    if trimmed.is_empty() {
        return Vec::new();
    }
    let lower = trimmed.to_lowercase();
    if lower.starts_with("steam://") || lower.starts_with("heroic://") || lower.starts_with("lutris:") {
        return Vec::new();
    }

    let mut raw_paths: Vec<String> = Vec::new();
    let trimmed_unquoted = trimmed.trim_matches(['"', '\'']);
    if trimmed_unquoted.contains('\\') || trimmed_unquoted.contains('/') || !trimmed_unquoted.contains(' ') {
        raw_paths.push(trimmed_unquoted.to_string());
    }
    for tok in trimmed.split_whitespace() {
        let clean = tok.trim_matches(['"', '\'']);
        if clean.starts_with('-') || clean.contains('=') {
            continue;
        }
        raw_paths.push(clean.to_string());
    }

    let mut out = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for raw in raw_paths {
        let base = raw
            .rsplit(['/', '\\'])
            .next()
            .unwrap_or(&raw)
            .trim_matches(['"', '\''])
            .to_lowercase();
        if base.len() < 4 || is_ignored_wrapper_exec_token(&base) {
            continue;
        }
        let stem = base
            .strip_suffix(".exe")
            .or_else(|| base.strip_suffix(".x86_64"))
            .or_else(|| base.strip_suffix(".x86"))
            .or_else(|| base.strip_suffix(".bin"))
            .or_else(|| base.strip_suffix(".sh"))
            .or_else(|| base.strip_suffix(".appimage"))
            .unwrap_or(&base)
            .to_string();
        if seen.insert((base.clone(), stem.clone())) {
            out.push((base, stem));
        }
    }
    out
}

pub fn exec_matches_process(exec_hint: &str, proc_name: &str, proc_exe: &str, proc_cmd: &str) -> bool {
    let candidates = extract_game_exec_candidates(exec_hint);
    if candidates.is_empty() {
        return false;
    }
    let pname_l = proc_name.trim().to_lowercase();
    let proc_exe_norm = proc_exe.to_lowercase().replace('\\', "/");
    let proc_cmd_norm = proc_cmd.to_lowercase().replace('\\', "/");

    for (base, stem) in candidates {
        if pname_l == base || (!stem.is_empty() && stem.len() >= 4 && pname_l == stem) {
            return true;
        }
        // Linux `/proc/<pid>/comm` truncates process names to 15 bytes.
        if pname_l.len() >= 12 && (base.starts_with(&pname_l) || stem.starts_with(&pname_l)) {
            return true;
        }
        if proc_exe_norm.ends_with(&format!("/{base}"))
            || (!stem.is_empty() && stem.len() >= 4 && proc_exe_norm.ends_with(&format!("/{stem}")))
        {
            return true;
        }
        if proc_cmd_norm.split_whitespace().any(|tok| {
            let clean = tok.trim_matches(['"', '\'']);
            clean.rsplit('/').next() == Some(base.as_str())
        }) {
            return true;
        }
        if base.ends_with(".exe") && proc_cmd_norm.contains(&base) {
            return true;
        }
    }
    false
}

fn contains_id_token(haystack: &str, prefix: &str, app_id: i64) -> bool {
    if app_id <= 0 {
        return false;
    }
    let needle = format!("{prefix}{app_id}");
    let mut search_from = 0usize;
    while let Some(rel) = haystack[search_from..].find(&needle) {
        let end = search_from + rel + needle.len();
        let next_is_digit = haystack[end..]
            .chars()
            .next()
            .map(|c| c.is_ascii_digit())
            .unwrap_or(false);
        if !next_is_digit {
            return true;
        }
        search_from = search_from + rel + 1;
    }
    false
}

fn process_matches_steam_appid(
    proc_name: &str,
    proc_exe: &str,
    proc_cmd: &str,
    app_id: i64,
) -> bool {
    if app_id <= 0 {
        return false;
    }
    if is_lutris_client_process(proc_name, proc_cmd)
        || matches!(
            proc_name,
            "steam"
                | "steamwebhelper"
                | "steam-runtime"
                | "heroic"
                | "lutris"
                | "net.lutris.lutris"
                | "chronos_app"
                | "chronos_proxy"
                | "firefox"
                | "chrome"
                | "chromium"
                | "brave"
        )
    {
        return false;
    }
    contains_id_token(proc_cmd, "appid=", app_id)
        || contains_id_token(proc_cmd, "steam_app_", app_id)
        || contains_id_token(proc_name, "steam_app_", app_id)
        || contains_id_token(proc_exe, "steam_app_", app_id)
}

fn process_matches_steam_appid_with_env(
    proc_name: &str,
    proc_exe: &str,
    proc_cmd: &str,
    env: &HashMap<String, String>,
    app_id: i64,
) -> bool {
    if process_matches_steam_appid(proc_name, proc_exe, proc_cmd, app_id) {
        return true;
    }
    if app_id <= 0 || is_lutris_client_process(proc_name, proc_cmd) {
        return false;
    }
    extract_steam_appid_from_env(env) == Some(app_id)
}

fn normalize_game_match_text(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut prev_space = true;
    for ch in input.trim().to_lowercase().chars() {
        if ch.is_alphanumeric() {
            out.push(ch);
            prev_space = false;
        } else if !prev_space {
            out.push(' ');
            prev_space = true;
        }
    }
    out.trim().to_string()
}

fn is_untrusted_location(path: &str) -> bool {
    let lower = path.to_lowercase();
    lower.starts_with("/tmp")
        || lower.starts_with("/dev/shm")
        || lower.contains("/downloads/")
        || lower.contains("/.cache/")
}

/// Stable identity of a program path: folder names that look random (AppImage mounts
/// `.mount_AbC123`, temp dirs, hashes) become `*`; the file name is kept.
pub fn quarantine_key(path: &str) -> String {
    let parts: Vec<&str> = path.split('/').collect();
    let last = parts.len().saturating_sub(1);
    parts
        .iter()
        .enumerate()
        .map(|(i, seg)| {
            if i == last || seg.is_empty() {
                return seg.to_string();
            }
            let core = seg.trim_start_matches('.');
            let prefix_random = ["mount_", "tmp", "_MEI", "org.chromium."]
                .iter()
                .find_map(|p| core.strip_prefix(p))
                .is_some_and(|rest| rest.len() >= 4);
            let has_digit = core.chars().any(|c| c.is_ascii_digit());
            let has_alpha = core.chars().any(|c| c.is_ascii_alphabetic());
            let hexish = core.len() >= 8 && core.chars().all(|c| c.is_ascii_hexdigit() || c == '-');
            let mixed = core.len() >= 6 && has_digit && has_alpha && !core.contains(['.', ' ']);
            if prefix_random || hexish || mixed {
                "*".to_string()
            } else {
                seg.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join("/")
}

#[derive(Clone, Debug, Default)]
pub struct WindowInfo {
    pub address: String,
    pub class: String,
    pub initial_class: String,
    pub title: String,
    pub pid: u32,
}

impl WindowInfo {
    pub fn matches_app(&self, app_name: &str, app_exec: &str) -> bool {
        let n = app_name.trim().to_lowercase();
        let e = app_exec.trim().to_lowercase();
        let base_n = extract_binary_basename(&n);
        let base_e = extract_binary_basename(&e);
        let c = self.class.to_lowercase();
        let ic = self.initial_class.to_lowercase();
        let t = self.title.to_lowercase();

        if !c.is_empty() {
            if c == n || c == e || (!base_n.is_empty() && c == base_n) || (!base_e.is_empty() && c == base_e) {
                return true;
            }
            if (!base_e.is_empty() && c.contains(&base_e)) || (!base_n.is_empty() && c.contains(&base_n)) {
                return true;
            }
        }

        if !ic.is_empty() {
            if ic == n || ic == e || (!base_n.is_empty() && ic == base_n) || (!base_e.is_empty() && ic == base_e) {
                return true;
            }
            if (!base_e.is_empty() && ic.contains(&base_e)) || (!base_n.is_empty() && ic.contains(&base_n)) {
                return true;
            }
        }

        // Browser windows: the title is the page title ("youtube - Pesquisa Google"), so it
        // never identifies an app; browser tabs are matched by their domain instead
        // (engine::evaluate_app_target_activity).
        if !t.is_empty() && !self.is_browser() {
            if t == n || (!base_n.is_empty() && t.contains(&base_n)) || (!base_e.is_empty() && t.contains(&base_e)) {
                return true;
            }
            if !n.is_empty() && (t.starts_with(&format!("{} - ", n)) || t.ends_with(&format!(" - {}", n))) {
                return true;
            }
            if !base_n.is_empty() && (t.starts_with(&format!("{} - ", base_n)) || t.ends_with(&format!(" - {}", base_n))) {
                return true;
            }
        }
        false
    }

    /// Host of the focused browser tab reported by the extension (fresh only).
    pub fn active_browser_tab_host() -> Option<String> {
        let text = std::fs::read_to_string("/tmp/chronos_active_tab.json").ok()?;
        let v: serde_json::Value = serde_json::from_str(&text).ok()?;
        let ts = v.get("timestamp_ms").and_then(|t| t.as_i64()).unwrap_or(0);
        let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_millis() as i64;
        if (now - ts).abs() > crate::youtube::ACTIVE_TAB_FRESH_MS {
            return None;
        }
        let url = v.get("url").and_then(|u| u.as_str())?.to_lowercase();
        let rest = url.split_once("://").map_or(url.as_str(), |(_, r)| r);
        let host = rest.split(['/', '?', '#', ':']).next().unwrap_or("").trim_start_matches("www.").to_string();
        (!host.is_empty()).then_some(host)
    }

    pub fn is_browser(&self) -> bool {
        let c = self.class.to_lowercase();
        let ic = self.initial_class.to_lowercase();
        let t = self.title.to_lowercase();
        c.contains("chrom")
            || c.contains("firefox")
            || c.contains("brave")
            || c.contains("edge")
            || c.contains("opera")
            || c.contains("vivaldi")
            || c.contains("zen")
            || c.contains("waterfox")
            || c.contains("librewolf")
            || ic.contains("chrom")
            || ic.contains("firefox")
            || ic.contains("brave")
            || t.contains("google chrome")
            || t.contains("chromium")
            || t.contains("mozilla firefox")
    }

    pub fn is_launcher_chrome(&self) -> bool {
        let c = self.class.trim().to_lowercase();
        let ic = self.initial_class.trim().to_lowercase();
        let t = self.title.trim().to_lowercase();
        let is_launcher_cls = matches!(
            c.as_str(),
            "steam" | "steamwebhelper" | "heroic" | "lutris" | "net.lutris.lutris" | "com.heroicgameslauncher.hgl"
        ) || matches!(
            ic.as_str(),
            "steam" | "steamwebhelper" | "heroic" | "lutris" | "net.lutris.lutris" | "com.heroicgameslauncher.hgl"
        );
        if !is_launcher_cls {
            return false;
        }
        t.is_empty()
            || matches!(
                t.as_str(),
                "steam"
                    | "sign in to steam"
                    | "iniciar sessão no steam"
                    | "friends list"
                    | "lista de amigos"
                    | "special offers"
                    | "ofertas especiais"
                    | "steam settings"
                    | "configurações"
                    | "screenshots"
                    | "capturas de tela"
                    | "players"
                    | "servers"
                    | "servidores"
                    | "heroic games launcher"
                    | "lutris"
                    | "bottles"
            )
            || t.starts_with("steam - ")
            || t.starts_with("friends")
            || t.starts_with("special offers")
    }

    /// Correspondência específica de janela para um JOGO hospedado por launcher.
    /// Rejeita explicitamente janelas do próprio cliente launcher (ex: Steam principal) e navegadores.
    pub fn matches_game_window(&self, game_name: &str, steam_app_id: Option<i64>) -> bool {
        if self.is_browser() || self.is_launcher_chrome() {
            return false;
        }
        let c = self.class.trim().to_lowercase();
        let ic = self.initial_class.trim().to_lowercase();

        if let Some(appid) = steam_app_id.filter(|id| *id > 0) {
            let expected = format!("steam_app_{appid}");
            if c == expected || ic == expected {
                return true;
            }
        }

        let norm_game = normalize_game_match_text(game_name);
        if norm_game.is_empty() || is_generic_launcher_token(&norm_game) {
            return false;
        }

        let compact_game: String = norm_game.chars().filter(|ch| !ch.is_whitespace()).collect();
        if !c.is_empty() && !is_generic_launcher_token(&c) {
            let norm_c = normalize_game_match_text(&c);
            let compact_c: String = norm_c.chars().filter(|ch| !ch.is_whitespace()).collect();
            if norm_c == norm_game || (!compact_game.is_empty() && compact_game.len() >= 4 && compact_c == compact_game) {
                return true;
            }
        }
        if !ic.is_empty() && !is_generic_launcher_token(&ic) {
            let norm_ic = normalize_game_match_text(&ic);
            let compact_ic: String = norm_ic.chars().filter(|ch| !ch.is_whitespace()).collect();
            if norm_ic == norm_game || (!compact_game.is_empty() && compact_game.len() >= 4 && compact_ic == compact_game) {
                return true;
            }
        }

        // Nunca casa apenas pelo título se a janela pertence diretamente ao launcher
        // (ex.: aba do Steam Client exibindo página de loja com título do jogo); para
        // janelas `steam_app_*` ou classes nativas/Wine/Proton/Gamescope, verifica o título.
        let is_launcher_cls = is_generic_launcher_token(&c) || is_generic_launcher_token(&ic);
        if is_launcher_cls {
            return false;
        }

        let norm_title = normalize_game_match_text(&self.title);
        if norm_title.is_empty() {
            return false;
        }
        if norm_title == norm_game
            || norm_title.starts_with(&format!("{norm_game} "))
            || norm_title.ends_with(&format!(" {norm_game}"))
            || (norm_game.len() >= 5 && norm_title.contains(&norm_game))
        {
            return true;
        }
        false
    }
}

#[derive(Clone, Debug, Default)]
pub struct ActiveWindowDetails {
    pub class: String,
    pub initial_class: String,
    pub title: String,
    pub pid: u32,
    pub is_browser: bool,
}

impl ActiveWindowDetails {
    pub fn as_window_info(&self) -> WindowInfo {
        WindowInfo {
            address: String::new(),
            class: self.class.clone(),
            initial_class: self.initial_class.clone(),
            title: self.title.clone(),
            pid: self.pid,
        }
    }
}

pub struct ActivityDetector {
    system: System,
}

impl ActivityDetector {
    pub fn new() -> Self {
        let mut system = System::new();
        system.refresh_processes(ProcessesToUpdate::All, true);
        Self { system }
    }

    pub fn is_steam_appid_running(&mut self, app_id: i64) -> bool {
        if app_id <= 0 {
            return false;
        }
        self.system.refresh_processes(ProcessesToUpdate::All, true);
        self.system.processes().values().any(|process| {
            let proc_cmd = process
                .cmd()
                .iter()
                .map(|s| s.to_string_lossy().to_lowercase())
                .collect::<Vec<_>>()
                .join(" ");
            let proc_name = process.name().to_string_lossy().to_lowercase();
            let proc_exe = process
                .exe()
                .map(|p| p.to_string_lossy().to_lowercase())
                .unwrap_or_default();
            let env = read_process_environ_map(process.pid().as_u32());
            process_matches_steam_appid_with_env(&proc_name, &proc_exe, &proc_cmd, &env, app_id)
        })
    }

    pub fn kill_steam_appid_processes(&mut self, app_id: i64, game_name: &str) -> usize {
        self.system.refresh_processes(ProcessesToUpdate::All, true);
        let norm_game = normalize_game_match_text(game_name);
        let compact_game: String = norm_game.chars().filter(|ch| !ch.is_whitespace()).collect();
        let mut killed = 0;

        for process in self.system.processes().values() {
            let proc_name = process.name().to_string_lossy().to_lowercase();
            let proc_cmd = process
                .cmd()
                .iter()
                .map(|s| s.to_string_lossy().to_lowercase())
                .collect::<Vec<_>>()
                .join(" ");
            if is_lutris_client_process(&proc_name, &proc_cmd)
                || matches!(
                    proc_name.as_str(),
                    "steam"
                        | "steamwebhelper"
                        | "steam-runtime"
                        | "heroic"
                        | "lutris"
                        | "net.lutris.lutris"
                        | "chronos_app"
                        | "chronos_proxy"
                )
            {
                continue;
            }
            let proc_exe = process
                .exe()
                .map(|p| p.to_string_lossy().to_lowercase())
                .unwrap_or_default();
            let env = read_process_environ_map(process.pid().as_u32());

            let matches_id =
                process_matches_steam_appid_with_env(&proc_name, &proc_exe, &proc_cmd, &env, app_id);

            let matches_game = !compact_game.is_empty()
                && compact_game.len() >= 5
                && !is_generic_launcher_token(&proc_name)
                && (normalize_game_match_text(&proc_name).replace(' ', "") == compact_game
                    || proc_exe.contains(&compact_game));

            if matches_id || matches_game {
                if process.kill() {
                    killed += 1;
                }
            }
        }
        killed
    }

    pub fn is_process_running(&mut self, target_name: &str) -> bool {
        self.system.refresh_processes(ProcessesToUpdate::All, true);
        let clean_target = extract_binary_basename(target_name);

        self.system
            .processes()
            .values()
            .any(|process| process_matches_target(process, &clean_target, target_name).is_some())
    }

    /// Kills a process and all its descendants (used for the window of a blocked app,
    /// whatever wrapper started it).
    pub fn kill_pid_tree(&mut self, root: u32) -> usize {
        if root <= 1 || root == std::process::id() {
            return 0;
        }
        self.system.refresh_processes(ProcessesToUpdate::All, true);
        let procs = self.system.processes();
        let mut tree = vec![root];
        let mut i = 0;
        while i < tree.len() {
            let parent = tree[i];
            for (pid, p) in procs {
                if p.parent().map(|pp| pp.as_u32()) == Some(parent) && !tree.contains(&pid.as_u32()) {
                    tree.push(pid.as_u32());
                }
            }
            i += 1;
        }
        tree.iter()
            .rev()
            .filter(|pid| **pid != std::process::id())
            .filter_map(|pid| procs.get(&sysinfo::Pid::from_u32(*pid)))
            .filter(|p| p.kill())
            .count()
    }

    pub fn kill_processes(&mut self, target_name: &str) -> usize {
        self.system.refresh_processes(ProcessesToUpdate::All, true);
        let clean_target = extract_binary_basename(target_name);
        let mut killed = 0;

        for process in self.system.processes().values() {
            let Some(by_name) = process_matches_target(process, &clean_target, target_name) else {
                continue;
            };
            if by_name {
                // Remember the real executable: renamed copies are recognized later.
                if let Some(exe) = process.exe() {
                    crate::wrappers::learn_blocked_executable(target_name, &exe.to_string_lossy());
                }
            }
            if process.kill() {
                killed += 1;
            }
        }

        // Fallback pkill para garantir encerramento de binários teimosos e subprocessos
        if !clean_target.is_empty() && clean_target != "chronos" && clean_target != "chronos_app" {
            let _ = Command::new("pkill").args(["-15", "-f", &clean_target]).output();
        }

        killed
    }

    /// (name, stable key) of running programs from temporary / download folders.
    /// The key is [`quarantine_key`]: random folder names are replaced by `*`, so an
    /// AppImage re-mounted at a new /tmp/.mount_XXXX keeps the same identity.
    pub fn find_untrusted_processes(&mut self) -> Vec<(String, String)> {
        self.system.refresh_processes(ProcessesToUpdate::All, true);
        let own_dir = std::env::current_exe().ok().and_then(|p| p.parent().map(|d| d.to_path_buf()));
        let mut list: Vec<(String, String)> = Vec::new();

        for process in self.system.processes().values() {
            let Some(exe_path) = process.exe() else { continue };
            if own_dir.as_ref().is_some_and(|d| exe_path.starts_with(d)) {
                continue; // Chronos itself (dev builds live under ~/Downloads)
            }
            let path_str = exe_path.to_string_lossy().to_string();
            if !is_untrusted_location(&path_str) {
                continue;
            }
            let name = process.name().to_string_lossy().to_string();
            if name.to_lowercase().starts_with("chronos") {
                continue;
            }
            let key = quarantine_key(&path_str);
            if !list.iter().any(|(_, k)| k == &key) {
                list.push((name, key));
            }
        }
        list
    }

    /// Kills every process whose [`quarantine_key`] is in `keys`; returns their names.
    pub fn kill_by_quarantine_keys(&mut self, keys: &std::collections::HashSet<String>) -> Vec<String> {
        if keys.is_empty() {
            return Vec::new();
        }
        self.system.refresh_processes(ProcessesToUpdate::All, true);
        let mut killed = Vec::new();
        for process in self.system.processes().values() {
            let Some(exe) = process.exe() else { continue };
            let path = exe.to_string_lossy();
            if !is_untrusted_location(&path) || !keys.contains(&quarantine_key(&path)) {
                continue;
            }
            if process.kill() {
                killed.push(process.name().to_string_lossy().to_string());
            }
        }
        killed
    }

    pub fn get_active_window_details() -> ActiveWindowDetails {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;

        let has_hyprland = *IS_HYPRLAND.get_or_init(|| {
            std::env::var("HYPRLAND_INSTANCE_SIGNATURE").is_ok()
                || Command::new("which").arg("hyprctl").output().map(|o| o.status.success()).unwrap_or(false)
        });

        if has_hyprland {
            if let Ok(output) = Command::new("hyprctl").args(["activewindow", "-j"]).output() {
                if output.status.success() {
                    if let Ok(json) = serde_json::from_slice::<serde_json::Value>(&output.stdout) {
                        let class = json.get("class").and_then(|v| v.as_str()).unwrap_or("").trim().to_lowercase();
                        let initial_class = json.get("initialClass").and_then(|v| v.as_str()).unwrap_or("").trim().to_lowercase();
                        let title = json.get("title").and_then(|t| t.as_str()).unwrap_or("").trim().to_string();
                        let pid = json.get("pid").and_then(|v| v.as_u64()).unwrap_or(0) as u32;

                        if !title.is_empty() && title.to_lowercase().contains("youtube") {
                            LAST_YOUTUBE_SEEN_UTC.store(now, Ordering::Relaxed);
                        }

                        let is_browser = class.contains("chrom")
                            || class.contains("firefox")
                            || class.contains("brave")
                            || class.contains("edge")
                            || class.contains("opera")
                            || class.contains("vivaldi")
                            || class.contains("zen")
                            || class.contains("waterfox")
                            || class.contains("librewolf")
                            || initial_class.contains("chrom")
                            || initial_class.contains("firefox")
                            || title.to_lowercase().contains("google chrome")
                            || title.to_lowercase().contains("chromium");

                        return ActiveWindowDetails {
                            class,
                            initial_class,
                            title,
                            pid,
                            is_browser,
                        };
                    }
                }
            }
        }

        // Fallback X11
        let title = Self::get_active_window_title().unwrap_or_default();
        let t_lower = title.to_lowercase();
        let is_browser = t_lower.contains("chrom")
            || t_lower.contains("firefox")
            || t_lower.contains("brave")
            || t_lower.contains("edge")
            || t_lower.contains("opera");

        ActiveWindowDetails {
            class: String::new(),
            initial_class: String::new(),
            title,
            pid: 0,
            is_browser,
        }
    }

    pub fn get_active_window_title() -> Option<String> {
        let details = Self::get_active_window_details();
        if !details.title.is_empty() {
            Some(details.title)
        } else {
            None
        }
    }

    pub fn get_all_windows_info() -> Vec<WindowInfo> {
        let now_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as i64;

        {
            let cache = WINDOW_INFO_CACHE.lock();
            if let Some((ts, ref list)) = *cache {
                if (now_ms - ts).abs() <= 750 {
                    return list.clone();
                }
            }
        }

        let now = now_ms / 1000;
        let mut list = Vec::new();
        let has_hyprland = *IS_HYPRLAND.get_or_init(|| {
            std::env::var("HYPRLAND_INSTANCE_SIGNATURE").is_ok()
                || Command::new("which").arg("hyprctl").output().map(|o| o.status.success()).unwrap_or(false)
        });

        if has_hyprland {
            if let Ok(output) = Command::new("hyprctl").args(["clients", "-j"]).output() {
                if output.status.success() {
                    if let Ok(arr) = serde_json::from_slice::<Vec<serde_json::Value>>(&output.stdout) {
                        for item in arr {
                            let address = item.get("address").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();
                            let class = item.get("class").and_then(|v| v.as_str()).unwrap_or("").trim().to_lowercase();
                            let initial_class = item.get("initialClass").and_then(|v| v.as_str()).unwrap_or("").trim().to_lowercase();
                            let title = item.get("title").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();
                            let pid = item.get("pid").and_then(|v| v.as_u64()).unwrap_or(0) as u32;

                            if !title.is_empty() && title.to_lowercase().contains("youtube") {
                                LAST_YOUTUBE_SEEN_UTC.store(now, Ordering::Relaxed);
                            }

                            if !class.is_empty() || !title.is_empty() || !address.is_empty() {
                                list.push(WindowInfo { address, class, initial_class, title, pid });
                            }
                        }
                    }
                }
            }
        }

        if list.is_empty() {
            if let Ok(output) = Command::new("wmctrl").arg("-l").output() {
                if output.status.success() {
                    for line in String::from_utf8_lossy(&output.stdout).lines() {
                        let t = line.trim();
                        if !t.is_empty() {
                            list.push(WindowInfo {
                                address: String::new(),
                                class: String::new(),
                                initial_class: String::new(),
                                title: t.to_string(),
                                pid: 0,
                            });
                        }
                    }
                }
            }
        }

        *WINDOW_INFO_CACHE.lock() = Some((now_ms, list.clone()));
        list
    }

    /// Obtém os títulos de todas as janelas abertas no gerenciador de janelas (com cache de 750ms para evitar spawning redundante de processos)
    pub fn get_all_window_titles_lower() -> Vec<String> {
        Self::get_all_windows_info()
            .into_iter()
            .map(|w| w.title.to_lowercase())
            .filter(|t| !t.is_empty())
            .collect()
    }

    /// Consulta de forma ultra-rápida (~2ms) e sem lock (immutable=1) com cache de 2000ms as últimas URLs e títulos do histórico
    pub fn query_recent_browser_history() -> Vec<(String, String)> {
        let now_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as i64;

        {
            let cache = BROWSER_HISTORY_CACHE.lock();
            if let Some((ts, ref items)) = *cache {
                if (now_ms - ts).abs() <= 2000 {
                    return items.clone();
                }
            }
        }

        let home = match std::env::var("HOME") {
            Ok(h) => h,
            Err(_) => return Vec::new(),
        };
        let config_root = std::path::PathBuf::from(home).join(".config");
        let mut history_files = Vec::new();

        if let Ok(entries) = std::fs::read_dir(&config_root) {
            for entry in entries.flatten() {
                let p = entry.path();
                if !p.is_dir() {
                    continue;
                }
                for sub in &["Default/History", "Profile 1/History", "Profile 2/History"] {
                    let h_file = p.join(sub);
                    if h_file.is_file() {
                        if let Ok(meta) = h_file.metadata() {
                            if let Ok(modified) = meta.modified() {
                                history_files.push((modified, h_file));
                            }
                        }
                    }
                }
            }
        }

        history_files.sort_by(|a, b| b.0.cmp(&a.0));
        let mut results = Vec::new();

        for (_, h_path) in history_files.into_iter().take(2) {
            let uri = format!("file:{}?immutable=1", h_path.to_string_lossy());
            let flags = rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY
                | rusqlite::OpenFlags::SQLITE_OPEN_URI
                | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX;
            if let Ok(conn) = rusqlite::Connection::open_with_flags(&uri, flags) {
                if let Ok(mut stmt) = conn.prepare(
                    "SELECT LOWER(url), LOWER(title) FROM urls ORDER BY last_visit_time DESC LIMIT 50",
                ) {
                    if let Ok(rows) = stmt.query_map([], |r| {
                        Ok((
                            r.get::<_, String>(0).unwrap_or_default(),
                            r.get::<_, String>(1).unwrap_or_default(),
                        ))
                    }) {
                        for item in rows.flatten() {
                            if !item.0.is_empty() {
                                results.push(item);
                            }
                        }
                    }
                }
            }
            if !results.is_empty() {
                break;
            }
        }

        *BROWSER_HISTORY_CACHE.lock() = Some((now_ms, results.clone()));
        results
    }

    /// Obtém a URL e título da aba ativa do navegador via extensão (/tmp/chronos_active_tab.json),
    /// via banco History (immutable=1) ou via leitura rápida da sessão ativa do navegador.
    pub fn get_active_browser_context(active_details: &ActiveWindowDetails) -> (String, String) {
        let now_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as i64;

        // Se a janela em foco NÃO for um navegador, não reporta aba ativa em primeiro plano!
        if !active_details.is_browser {
            return (String::new(), String::new());
        }

        // 1. Verifica arquivo em tempo real reportado pela extensão via WebBlockServer
        if let Ok(content) = std::fs::read_to_string("/tmp/chronos_active_tab.json") {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                let ts = json.get("timestamp_ms").and_then(|v| v.as_i64()).unwrap_or(0);
                if (now_ms - ts).abs() <= crate::youtube::ACTIVE_TAB_FRESH_MS {
                    let url = json
                        .get("url")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_lowercase();
                    let title = json
                        .get("title")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_lowercase();
                    if !url.is_empty() {
                        return (url, title);
                    }
                }
            }
        }

        let active_window_lower = active_details.title.to_lowercase();
        if active_window_lower.is_empty() {
            return (String::new(), String::new());
        }

        // 2. Fallback: consulta as URLs recentes no SQLite History do navegador (suporta Chrome 157 Sessions_Encrypted)
        let ignored_hosts = [
            "gstatic.com",
            "googleapis.com",
            "accounts.google.com",
            "doubleclick.net",
            "googlesyndication.com",
            "google-analytics.com",
            "127.0.0.1",
            "localhost",
            "clients2.google.com",
            "ogs.google.com",
        ];
        for (h_url, h_title) in Self::query_recent_browser_history().into_iter().take(25) {
            let without_proto = h_url
                .trim_start_matches("https://")
                .trim_start_matches("http://")
                .trim_start_matches("www.");
            let host = without_proto.split('/').next().unwrap_or("");
            if host.is_empty() || ignored_hosts.iter().any(|ig| host.contains(ig)) {
                continue;
            }
            let domain_root = host.split('.').next().unwrap_or("");
            let title_matches = !h_title.is_empty() && active_window_lower.contains(&h_title);
            let domain_matches = domain_root.len() >= 3 && active_window_lower.contains(domain_root);
            if title_matches || domain_matches {
                return (h_url, h_title);
            }
        }

        // 3. Fallback: lê os últimos bytes do arquivo Session_* mais recente do navegador
        if let Some(url) = Self::read_latest_matching_browser_session_url(&active_window_lower) {
            return (url, active_window_lower.to_string());
        }

        (String::new(), String::new())
    }

    pub fn get_active_browser_context_str(active_window_lower: &str) -> (String, String) {
        let is_browser = active_window_lower.contains("chrom")
            || active_window_lower.contains("firefox")
            || active_window_lower.contains("brave")
            || active_window_lower.contains("edge")
            || active_window_lower.contains("opera");
        let details = ActiveWindowDetails {
            title: active_window_lower.to_string(),
            is_browser,
            ..Default::default()
        };
        Self::get_active_browser_context(&details)
    }

    pub fn has_active_audio_sink_for_browser_or(app_name: &str) -> bool {
        let app_lower = app_name.to_lowercase();
        if let Ok(output) = Command::new("pactl").args(["list", "sink-inputs"]).output() {
            if output.status.success() {
                let text = String::from_utf8_lossy(&output.stdout).to_lowercase();
                for block in text.split("sink input #") {
                    if block.contains("state: running") {
                        if block.contains("chrome")
                            || block.contains("firefox")
                            || block.contains("brave")
                            || block.contains("chromium")
                            || block.contains("spotify")
                            || (!app_lower.is_empty() && block.contains(&app_lower))
                        {
                            return true;
                        }
                    }
                }
            }
        }
        false
    }

    fn read_latest_matching_browser_session_url(active_window_lower: &str) -> Option<String> {
        use std::io::{Read, Seek, SeekFrom};

        let home = std::env::var("HOME").ok()?;
        let config_root = std::path::PathBuf::from(home).join(".config");
        let mut session_files = Vec::new();

        // Procura dinamicamente diretórios Sessions dentro de ~/.config/*/Default/Sessions e Profile */Sessions
        if let Ok(entries) = std::fs::read_dir(&config_root) {
            for entry in entries.flatten() {
                let p = entry.path();
                if !p.is_dir() {
                    continue;
                }
                for sub in &["Default/Sessions", "Profile 1/Sessions", "Profile 2/Sessions"] {
                    let sess_dir = p.join(sub);
                    if sess_dir.is_dir() {
                        if let Ok(s_entries) = std::fs::read_dir(&sess_dir) {
                            for s_entry in s_entries.flatten() {
                                let sp = s_entry.path();
                                if let Some(fname) = sp.file_name().and_then(|f| f.to_str()) {
                                    if fname.starts_with("Session_") {
                                        if let Ok(meta) = sp.metadata() {
                                            if let Ok(modified) = meta.modified() {
                                                session_files.push((modified, sp));
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        session_files.sort_by(|a, b| b.0.cmp(&a.0));
        let (_, newest_session) = session_files.first()?;

        let mut file = std::fs::File::open(newest_session).ok()?;
        let len = file.metadata().ok()?.len();
        let read_size = len.min(32768);
        let _ = file.seek(SeekFrom::End(-(read_size as i64)));
        let mut buf = Vec::with_capacity(read_size as usize);
        file.read_to_end(&mut buf).ok()?;

        // Extrai sequências ASCII que começam com http:// ou https://
        let mut urls = Vec::new();
        let mut i = 0;
        while i + 8 < buf.len() {
            if &buf[i..i + 7] == b"http://" || &buf[i..i + 8] == b"https://" {
                let start = i;
                while i < buf.len() {
                    let b = buf[i];
                    if b.is_ascii_graphic()
                        && b != b'"'
                        && b != b'\''
                        && b != b'<'
                        && b != b'>'
                        && b != b'\\'
                        && b != b')'
                    {
                        i += 1;
                    } else {
                        break;
                    }
                }
                if let Ok(s) = std::str::from_utf8(&buf[start..i]) {
                    urls.push(s.to_lowercase());
                }
            } else {
                i += 1;
            }
        }

        let ignored_hosts = [
            "gstatic.com",
            "googleapis.com",
            "accounts.google.com",
            "doubleclick.net",
            "googlesyndication.com",
            "google-analytics.com",
            "127.0.0.1",
            "localhost",
            "clients2.google.com",
            "ogs.google.com",
        ];

        // Percorre de trás para frente (URL mais recente primeiro)
        for u in urls.into_iter().rev() {
            let without_proto = u
                .trim_start_matches("https://")
                .trim_start_matches("http://")
                .trim_start_matches("www.");
            let host = without_proto.split('/').next().unwrap_or("");
            if host.is_empty() || ignored_hosts.iter().any(|ig| host.contains(ig)) {
                continue;
            }
            let domain_root = host.split('.').next().unwrap_or("");
            // Confirma que a janela em foco corresponde ao site aberto na sessão
            if !domain_root.is_empty() && active_window_lower.contains(domain_root) {
                return Some(u);
            }
        }

        None
    }

    fn fetch_playerctl_playing_lines() -> Vec<Vec<String>> {
        let output = match Command::new("playerctl")
            .args([
                "-a",
                "metadata",
                "--format",
                "{{status}}|||{{playerName}}|||{{title}}|||{{xesam:url}}|||{{mpris:artUrl}}",
            ])
            .output()
        {
            Ok(o) if o.status.success() => o,
            _ => return Vec::new(),
        };

        let stdout = String::from_utf8_lossy(&output.stdout);
        let mut lines = Vec::new();
        for line in stdout.lines() {
            let parts: Vec<String> = line.split("|||").map(|s| s.to_string()).collect();
            if parts.is_empty() {
                continue;
            }
            if parts[0].trim().eq_ignore_ascii_case("playing") {
                lines.push(parts);
            }
        }
        lines
    }

    pub fn is_media_playing_for_patterns(patterns: &[String]) -> (bool, Option<String>) {
        if patterns.is_empty() {
            return (false, None);
        }

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;
        let now_ms = now * 1000;

        // 1. Verifica se a extensão web detectou uma aba emitindo áudio em segundo plano ou primeiro plano
        if let Ok(content) = std::fs::read_to_string("/tmp/chronos_active_tab.json") {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                let ts = json.get("audible_timestamp_ms").or_else(|| json.get("timestamp_ms")).and_then(|v| v.as_i64()).unwrap_or(0);
                if (now_ms - ts).abs() <= crate::youtube::AUDIBLE_TAB_FRESH_MS {
                    let a_url = json.get("audible_url").and_then(|v| v.as_str()).unwrap_or("").to_lowercase();
                    let a_title = json.get("audible_title").and_then(|v| v.as_str()).unwrap_or("").to_lowercase();
                    if !a_url.is_empty() || !a_title.is_empty() {
                        for pat in patterns {
                            let p_clean = pat
                                .trim()
                                .trim_start_matches("https://")
                                .trim_start_matches("http://")
                                .trim_start_matches("www.")
                                .trim_end_matches('/')
                                .to_lowercase();
                            if p_clean.is_empty() {
                                continue;
                            }
                            let domain_root = if p_clean.contains('.') && !p_clean.contains('/') {
                                p_clean.split('.').next().unwrap_or("")
                            } else {
                                ""
                            };
                            let matches_url = !a_url.is_empty() && (a_url.contains(&p_clean) || (!domain_root.is_empty() && a_url.contains(domain_root)));
                            let matches_title = !a_title.is_empty() && (a_title.contains(&p_clean) || (!domain_root.is_empty() && a_title.contains(domain_root)));
                            if matches_url || matches_title {
                                if p_clean.contains("youtube") || domain_root == "youtube" {
                                    LAST_YOUTUBE_SEEN_UTC.store(now, Ordering::Relaxed);
                                }
                                let label = if !a_title.is_empty() { a_title } else { a_url };
                                return (true, Some(label));
                            }
                        }
                    }
                }
            }
        }

        // 2. Consulta instâncias do playerctl (MPRIS2)
        let playing_lines: Vec<Vec<String>> = {
            let mut cache = PLAYERCTL_CACHE.lock();
            if let Some((ts, ref cached)) = *cache {
                if (now_ms - ts).abs() <= 750 {
                    cached.clone()
                } else {
                    let fresh = Self::fetch_playerctl_playing_lines();
                    *cache = Some((now_ms, fresh.clone()));
                    fresh
                }
            } else {
                let fresh = Self::fetch_playerctl_playing_lines();
                *cache = Some((now_ms, fresh.clone()));
                fresh
            }
        };

        if !playing_lines.is_empty() {
            // Coleta contextos adicionais apenas quando há mídia ativamente em reprodução ("Playing")
            let all_window_titles = Self::get_all_window_titles_lower();
            let history_entries = Self::query_recent_browser_history();

            let mut ext_audible_contexts = Vec::new();
            if let Ok(content) = std::fs::read_to_string("/tmp/chronos_active_tab.json") {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                    let ts = json.get("audible_timestamp_ms").and_then(|v| v.as_i64()).unwrap_or(0).max(json.get("timestamp_ms").and_then(|v| v.as_i64()).unwrap_or(0));
                    if (now_ms - ts).abs() <= crate::youtube::AUDIBLE_TAB_FRESH_MS {
                        for key in &["audible_url", "audible_title", "url", "title"] {
                            if let Some(val) = json.get(*key).and_then(|v| v.as_str()) {
                                let lower = val.trim().to_lowercase();
                                if !lower.is_empty() {
                                    ext_audible_contexts.push(lower);
                                }
                            }
                        }
                    }
                }
            }

            for parts in playing_lines {
                let player_name = if parts.len() > 1 { parts[1].trim() } else { "" };
                let title = if parts.len() > 2 && !parts[2].trim().is_empty() {
                    parts[2].trim()
                } else {
                    "Mídia em Execução"
                };
                let url = if parts.len() > 3 { parts[3].trim().to_lowercase() } else { String::new() };
                let art_url = if parts.len() > 4 { parts[4].trim().to_lowercase() } else { String::new() };

                let title_lower = title.to_lowercase();
                let p_lower = player_name.to_lowercase();
                let is_browser = p_lower.contains("chrom")
                    || p_lower.contains("brave")
                    || p_lower.contains("firefox")
                    || p_lower.contains("edge")
                    || p_lower.contains("opera")
                    || p_lower.contains("vivaldi")
                    || p_lower.contains("zen")
                    || p_lower.contains("waterfox")
                    || p_lower.contains("librewolf");

                let mut candidate_texts = vec![
                    title_lower.clone(),
                    url.clone(),
                    art_url.clone(),
                    p_lower.clone(),
                ];

                if title_lower.len() >= 3 && title_lower != "mídia em execução" {
                    let title_prefix: String = title_lower.chars().take(24).collect();
                    for win_t in &all_window_titles {
                        if win_t.contains(&title_lower)
                            || (title_prefix.len() >= 6 && win_t.contains(&title_prefix))
                        {
                            candidate_texts.push(win_t.clone());
                        }
                    }
                    for (h_url, h_title) in &history_entries {
                        if !h_title.is_empty()
                            && (h_title.contains(&title_lower)
                                || (h_title.len() >= 4 && title_lower.contains(h_title))
                                || (title_prefix.len() >= 6 && h_title.contains(&title_prefix)))
                        {
                            candidate_texts.push(h_url.clone());
                            candidate_texts.push(h_title.clone());
                        }
                    }
                }

                if is_browser {
                    for ext_ctx in &ext_audible_contexts {
                        candidate_texts.push(ext_ctx.clone());
                    }
                }

                for pat in patterns {
                    let p_clean = pat
                        .trim()
                        .trim_start_matches("https://")
                        .trim_start_matches("http://")
                        .trim_start_matches("www.")
                        .trim_end_matches('/')
                        .to_lowercase();
                    if p_clean.is_empty() {
                        continue;
                    }

                    let domain_root = if p_clean.contains('.') && !p_clean.contains('/') {
                        p_clean.split('.').next().unwrap_or("")
                    } else {
                        ""
                    };

                    // A. Verifica nos contextos enriquecidos da faixa em reprodução
                    let matched_enriched = candidate_texts.iter().any(|ctx| {
                        if ctx.is_empty() {
                            return false;
                        }
                        if ctx.contains(&p_clean) {
                            return true;
                        }
                        if domain_root.len() >= 3 && ctx.contains(domain_root) {
                            return true;
                        }
                        false
                    });

                    if matched_enriched {
                        if p_clean.contains("youtube") || domain_root == "youtube" {
                            LAST_YOUTUBE_SEEN_UTC.store(now, Ordering::Relaxed);
                        }
                        return (true, Some(title.to_string()));
                    }

                    // B. Se for um navegador tocando áudio e houver uma janela aberta com o site bloqueado
                    if is_browser {
                        let window_has_site = all_window_titles.iter().any(|win_t| {
                            win_t.contains(&p_clean)
                                || (domain_root.len() >= 3 && win_t.contains(domain_root))
                        });
                        if window_has_site {
                            return (true, Some(title.to_string()));
                        }

                        // C. Verificação de thumbnail/metadados reais do YouTube na faixa atual
                        if (p_clean.contains("youtube") || domain_root == "youtube")
                            && (art_url.contains("ytimg") || art_url.contains("googlevideo"))
                        {
                            LAST_YOUTUBE_SEEN_UTC.store(now, Ordering::Relaxed);
                            return (true, Some(title.to_string()));
                        }
                    }
                }
            }
        }

        // 3. Fallback PulseAudio / PipeWire: verifica se há áudio saindo ativamente de navegador ou app
        for pat in patterns {
            let p_clean = pat.trim().to_lowercase();
            if Self::has_active_audio_sink_for_browser_or(&p_clean) {
                let all_windows = Self::get_all_window_titles_lower();
                let matches_open_window = all_windows.iter().any(|w| w.contains(&p_clean));
                if matches_open_window {
                    return (true, Some(format!("Áudio em reprodução: {}", pat)));
                }
            }
        }

        (false, None)
    }

    /// Fecha uma janela pelo título, classe ou endereço de forma limpa (Hyprland ou X11/wmctrl)
    pub fn close_window_by_title(title: &str) {
        let t_clean = title.trim();
        if t_clean.is_empty() {
            return;
        }

        let clean_base = extract_binary_basename(t_clean);

        let has_hyprland = *IS_HYPRLAND.get_or_init(|| {
            std::env::var("HYPRLAND_INSTANCE_SIGNATURE").is_ok()
                || Command::new("which").arg("hyprctl").output().map(|o| o.status.success()).unwrap_or(false)
        });

        if has_hyprland {
            // 1. Fecha por classe no Hyprland (ex: discord, alacritty, code, etc.)
            if !clean_base.is_empty() {
                let _ = Command::new("hyprctl")
                    .args(["dispatch", "closewindow", &format!("class:(?i).*{}.*", clean_base)])
                    .output();
            }

            // 2. Fecha por título
            let _ = Command::new("hyprctl")
                .args(["dispatch", "closewindow", &format!("title:{}", t_clean)])
                .output();

            // 3. Fecha cada janela correspondente por endereço exato de janela ou PID
            for win in Self::get_all_windows_info() {
                if win.matches_app(t_clean, &clean_base) {
                    if !win.address.is_empty() {
                        let _ = Command::new("hyprctl")
                            .args(["dispatch", "closewindow", &format!("address:{}", win.address)])
                            .output();
                    } else if win.pid > 0 {
                        let _ = Command::new("hyprctl")
                            .args(["dispatch", "closewindow", &format!("pid:{}", win.pid)])
                            .output();
                    }
                }
            }
        }

        let _ = Command::new("wmctrl")
            .args(["-c", t_clean])
            .output();
        if !clean_base.is_empty() {
            let _ = Command::new("wmctrl")
                .args(["-c", &clean_base])
                .output();
        }
    }

    /// Otimizado para execução única: delega ao detector enriquecido por padrões
    pub fn is_media_playing_in_background(target: &str) -> (bool, Option<String>) {
        Self::is_media_playing_for_patterns(&[target.to_string()])
    }

    pub fn close_game_window_only(game_name: &str, steam_app_id: Option<i64>) {
        let has_hyprland = *IS_HYPRLAND.get_or_init(|| {
            std::env::var("HYPRLAND_INSTANCE_SIGNATURE").is_ok()
                || Command::new("which")
                    .arg("hyprctl")
                    .output()
                    .map(|o| o.status.success())
                    .unwrap_or(false)
        });

        for win in Self::get_all_windows_info() {
            if !win.matches_game_window(game_name, steam_app_id) {
                continue;
            }
            if has_hyprland {
                if !win.address.is_empty() {
                    let _ = Command::new("hyprctl")
                        .args(["dispatch", "closewindow", &format!("address:{}", win.address)])
                        .output();
                } else if win.pid > 0 {
                    let _ = Command::new("hyprctl")
                        .args(["dispatch", "closewindow", &format!("pid:{}", win.pid)])
                        .output();
                }
            } else if !win.title.trim().is_empty() {
                let _ = Command::new("wmctrl").args(["-c", win.title.trim()]).output();
            }
        }
    }

    pub fn pause_background_media(_target: &str) {
        let _ = Command::new("playerctl")
            .args(["-a", "pause"])
            .output();

        for p in &["chromium", "brave", "firefox", "chrome"] {
            let _ = Command::new("playerctl")
                .args(["-p", p, "pause"])
                .output();
        }
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn quarantine_key_is_stable_across_random_dirs() {
        use super::quarantine_key;
        assert_eq!(
            quarantine_key("/tmp/.mount_Obsid4xK9q/obsidian"),
            quarantine_key("/tmp/.mount_ObsidZZ7a1b/obsidian")
        );
        assert_eq!(quarantine_key("/tmp/tmpa8f3k2x9/run.bin"), quarantine_key("/tmp/tmpq0q0q0q0/run.bin"));
        assert_eq!(
            quarantine_key("/home/u/Downloads/game-v1.2/Game.x86_64"),
            "/home/u/Downloads/game-v1.2/Game.x86_64"
        );
        assert_ne!(quarantine_key("/tmp/a/one"), quarantine_key("/tmp/a/two"));
    }

    #[test]
    fn browser_titles_do_not_match_apps() {
        use super::WindowInfo;
        let w = |class: &str, title: &str| WindowInfo {
            class: class.into(),
            initial_class: class.into(),
            title: title.into(),
            ..Default::default()
        };
        assert!(!w("google-chrome", "youtube - Pesquisa Google").matches_app("Youtube", "youtube"));
        assert!(!w("firefox", "YouTube - Mozilla Firefox").matches_app("Youtube", "youtube"));
        assert!(w("chrome-youtube.com__-Default", "YouTube").matches_app("Youtube", "youtube"), "web-app by class");
        assert!(w("youtube-music", "Youtube Music").matches_app("Youtube Music", "youtube-music"));
        assert!(w("org.gnome.Nautilus", "youtube - Files").matches_app("Youtube", "youtube"), "non-browser titles still count");
    }

    #[test]
    fn process_identity_ignores_arguments() {
        use super::process_identity_matches as m;
        assert!(m("youtube", "youtube", "/usr/bin/youtube"));
        assert!(!m("youtube", "nvim", "/usr/bin/nvim"), "editing youtube.rs is not YouTube");
        assert!(!m("youtube", "node", "/usr/bin/node"));
        assert!(!m("steam", "steamwebhelper", "/home/u/.steam/steamwebhelper"));
        assert!(m("discord", "discord", "/opt/discord/discord"));
        assert!(m("heroicgameslauncher", "heroicgameslaun", "/opt/Heroic/heroic"));
        assert!(m("code", "electron", "/usr/bin/code"), "exe basename counts");
        assert!(!m("", "anything", "/x"));
    }

    use super::*;

    #[test]
    fn steam_client_window_does_not_match_steam_game() {
        let steam_client = WindowInfo {
            address: "0x1".to_string(),
            class: "steam".to_string(),
            initial_class: "steam".to_string(),
            title: "Steam".to_string(),
            pid: 1001,
        };
        assert!(!steam_client.matches_game_window("Counter-Strike 2", Some(730)));
        assert!(!steam_client.matches_game_window("Elden Ring", None));

        // Mesmo quando a aba da loja do cliente Steam exibe o título do jogo, class == "steam"
        // não deve contar tempo como se o jogo estivesse sendo jogado.
        let steam_store_page = WindowInfo {
            address: "0x2".to_string(),
            class: "steam".to_string(),
            initial_class: "steam".to_string(),
            title: "Counter-Strike 2 on Steam".to_string(),
            pid: 1001,
        };
        assert!(!steam_store_page.matches_game_window("Counter-Strike 2", Some(730)));

        // Já a janela real do jogo (`steam_app_730` ou binário próprio) DEVE dar match.
        let game_win = WindowInfo {
            address: "0x3".to_string(),
            class: "steam_app_730".to_string(),
            initial_class: "steam_app_730".to_string(),
            title: "Counter-Strike 2".to_string(),
            pid: 2002,
        };
        assert!(game_win.matches_game_window("Counter-Strike 2", Some(730)));

        let proton_win = WindowInfo {
            address: "0x4".to_string(),
            class: "eldenring.exe".to_string(),
            initial_class: "steam_app_1245620".to_string(),
            title: "ELDEN RING".to_string(),
            pid: 2003,
        };
        assert!(proton_win.matches_game_window("Elden Ring", Some(1245620)));
        assert!(proton_win.matches_game_window("Elden Ring", None));

        // Vídeo no navegador com o nome do jogo NÃO conta como jogo desktop aberto
        let browser_win = WindowInfo {
            address: "0x5".to_string(),
            class: "google-chrome".to_string(),
            initial_class: "google-chrome".to_string(),
            title: "Counter-Strike 2 - YouTube".to_string(),
            pid: 3001,
        };
        assert!(!browser_win.matches_game_window("Counter-Strike 2", Some(730)));
    }

    #[test]
    fn extract_basename_ignores_launcher_uris() {
        assert_eq!(extract_binary_basename("steam://rungameid/730"), "");
        assert_eq!(extract_binary_basename("heroic://launch/123"), "");
        assert_eq!(extract_binary_basename("/usr/bin/steam"), "steam");
    }

    #[test]
    fn appid_token_matching_respects_boundaries_and_ignores_webhelper() {
        assert!(is_generic_launcher_token("com.valvesoftware.Steam"));
        assert!(is_generic_launcher_token("steam.exe"));

        // Prefix collision protection: AppId=730 must NOT match 73
        assert!(!process_matches_steam_appid(
            "reaper",
            "/usr/bin/reaper",
            "reaper steamlaunch appid=730 -- game",
            73
        ));
        assert!(process_matches_steam_appid(
            "reaper",
            "/usr/bin/reaper",
            "reaper steamlaunch appid=730 -- game",
            730
        ));

        // steamwebhelper/browser carrying an AppId URL must NOT trigger running game detection
        assert!(!process_matches_steam_appid(
            "steamwebhelper",
            "/home/u/.local/share/Steam/ubuntu12_64/steamwebhelper",
            "steamwebhelper --url=https://store.steampowered.com/app/730 appid=730",
            730
        ));
        assert!(!process_matches_steam_appid(
            "steam",
            "/usr/bin/steam",
            "steam steam_app_730",
            730
        ));
    }

    #[test]
    fn lutris_env_and_windows_exec_matching() {
        let env = read_process_environ_from_bytes(
            b"WINEPREFIX=/home/u/Games/isaac-pfx\0UMU_ID=umu-250900\0LUTRIS_GAME_UUID=isaac-1\0",
        );
        assert_eq!(extract_steam_appid_from_env(&env), Some(250900));
        assert!(process_matches_steam_appid_with_env(
            "wine64-preloader",
            "/usr/bin/wine64-preloader",
            r"Z:\home\u\Games\Isaac\isaac-ng.exe",
            &env,
            250900
        ));
        assert!(!process_matches_steam_appid_with_env(
            "python3",
            "/usr/bin/python3",
            "/usr/bin/python3 /usr/bin/lutris",
            &env,
            250900
        ));

        let shortcut_env = read_process_environ_from_bytes(b"UMU_ID=umu-3000000123\0SteamAppId=0\0");
        assert_eq!(extract_steam_appid_from_env(&shortcut_env), None);

        assert!(is_lutris_client_process("lutris", "lutris"));
        assert!(is_lutris_client_process("net.lutris.lutris", "net.lutris.lutris"));
        assert!(is_lutris_client_process("python3", "/usr/bin/python3 /usr/bin/lutris"));
        assert!(!is_lutris_client_process("python3", "/usr/bin/python3 /usr/bin/umu-run"));

        assert!(exec_matches_process(
            r"C:\Games\Isaac\isaac-ng.exe",
            "isaac-ng.exe",
            "/usr/bin/wine64-preloader",
            r"C:\Games\Isaac\isaac-ng.exe --windowed"
        ));
        // 15-byte `/proc/<pid>/comm` truncation
        assert!(exec_matches_process(
            "/opt/games/TheBindingOfIsaacRebirth.x86_64",
            "thebindingofisa",
            "",
            ""
        ));
        assert!(!exec_matches_process("/usr/bin/wine64", "wine64", "/usr/bin/wine64", ""));
    }
}
