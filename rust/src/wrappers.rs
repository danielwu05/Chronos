//! Recognizes apps started through wrappers, where the process name is not the app's:
//!
//! 1. **Interpreters** (`java -jar minecraft.jar`, `python3 jogo.py`, `electron
//!    /usr/lib/code/...`, `wine Jogo.exe`): the script / jar / app directory in the
//!    command line identifies the app.
//! 2. **systemd scopes**: apps opened from the launcher run in
//!    `app-<launcher>-<name>-<rand>.scope`, Flatpaks in `app-<app.id>-<pid>.scope`. Used
//!    only for interpreters and sandboxed Flatpak processes (anything else an app starts,
//!    like a browser opened from a link, inherits the scope too).
//! 3. **AppImage**: processes carry `APPIMAGE=/path/Obsidian-1.5.AppImage`.
//! 4. **Renamed copies** (anti-bypass): the fingerprint of a blocked app's executable is
//!    learned when it is seen under its real name; a copy with another name in the home
//!    folder or /tmp is still recognized.
//!
//! Everything is cached per (pid, start time) so the 1 s engine tick stays cheap.

use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::sync::OnceLock;

use parking_lot::Mutex;

const INTERPRETERS: &[&str] = &[
    "java", "python", "python2", "python3", "pypy", "pypy3", "node", "nodejs", "electron", "bun", "deno", "wine",
    "wine64", "wine-preloader", "wine64-preloader", "wine64-preloade", "mono", "dotnet", "bash", "sh", "dash", "zsh",
    "ruby", "perl", "lua", "luajit", "love", "godot", "gjs",
];

/// Executable / script extensions dropped when comparing names.
const EXTENSIONS: &[&str] = &[
    ".appimage", ".desktop", ".jar", ".py", ".pyw", ".js", ".mjs", ".cjs", ".exe", ".sh", ".asar", ".love", ".x86_64",
    ".bin", ".rb", ".pl", ".lua",
];

/// Prefixes of the launcher component in `app-<launcher>-<name>-<rand>.scope`.
const SCOPE_LAUNCHERS: &[&str] = &["hyprland-", "niri-", "sway-", "gnome-", "kde-", "plasma-", "flatpak-", "uwsm-"];

fn is_interpreter(name: &str) -> bool {
    let n = name.to_lowercase();
    INTERPRETERS.contains(&n.as_str())
        || n.starts_with("python3.")
        || n.starts_with("electron")
        || n.starts_with("java")
        || n.starts_with("node")
}

/// Lowercase, extension and version suffix removed: `Obsidian-1.5.3.AppImage` -> `obsidian`.
pub fn normalize_identity(raw: &str) -> String {
    let mut s = raw.trim().trim_end_matches('/').to_lowercase();
    if let Some(base) = Path::new(&s).file_name().and_then(|b| b.to_str()) {
        s = base.to_string();
    }
    loop {
        let before = s.len();
        for ext in EXTENSIONS {
            if let Some(stripped) = s.strip_suffix(ext) {
                s = stripped.to_string();
            }
        }
        if s.len() == before {
            break;
        }
    }
    // Version suffix: "obsidian-1.5.3", "game_v2"
    if let Some(idx) = s.find(|c: char| c == '-' || c == '_') {
        let rest = &s[idx + 1..];
        if rest.trim_start_matches('v').starts_with(|c: char| c.is_ascii_digit()) {
            s.truncate(idx);
        }
    }
    s.trim_start_matches('.').to_string()
}

fn compact(s: &str) -> String {
    s.chars().filter(|c| c.is_ascii_alphanumeric()).collect()
}

/// Identity tokens of a systemd scope name (`app-Hyprland-discord-1a2b3c4d.scope`,
/// `app-com.discordapp.Discord-1234.scope`, `app-flatpak-com.spotify.Client-5678.scope`).
pub fn scope_tokens(scope: &str) -> Vec<String> {
    let Some(inner) = scope.strip_prefix("app-").and_then(|s| s.strip_suffix(".scope")) else {
        return Vec::new();
    };
    let inner = inner.replace("\\x2d", "-");
    // Drop the random / pid suffix.
    let core = match inner.rsplit_once('-') {
        Some((head, tail)) if !tail.is_empty() && tail.chars().all(|c| c.is_ascii_hexdigit()) => head.to_string(),
        _ => inner,
    };
    let mut core = core.to_lowercase();
    for p in SCOPE_LAUNCHERS {
        if let Some(rest) = core.strip_prefix(p) {
            core = rest.to_string();
            break;
        }
    }
    let core = core.trim_end_matches(".desktop").to_string();
    if core.is_empty() || matches!(core.as_str(), "gtk-launch" | "xdg-terminal-exec" | "uwsm" | "dex") {
        return Vec::new();
    }
    let mut out = vec![core.clone()];
    if core.contains('.') {
        if let Some(last) = core.rsplit('.').next() {
            out.push(last.to_string());
        }
    }
    out
}

fn read_scope(pid: u32) -> Option<String> {
    let text = std::fs::read_to_string(format!("/proc/{pid}/cgroup")).ok()?;
    let path = text.lines().find_map(|l| l.strip_prefix("0::"))?;
    path.rsplit('/').find(|seg| seg.starts_with("app-") && seg.ends_with(".scope")).map(str::to_string)
}

fn read_cmdline(pid: u32) -> Vec<String> {
    std::fs::read(format!("/proc/{pid}/cmdline"))
        .map(|b| {
            b.split(|&c| c == 0)
                .filter(|a| !a.is_empty())
                .map(|a| String::from_utf8_lossy(a).to_string())
                .collect()
        })
        .unwrap_or_default()
}

/// Tokens from an interpreter's command line: script/jar/exe names, the app folder of
/// `/usr/lib/<app>/...` or `/opt/<app>/...`, and Java main-class segments.
pub fn cmdline_tokens(args: &[String]) -> Vec<String> {
    let mut out = Vec::new();
    let is_java = args.first().is_some_and(|a| normalize_identity(a).starts_with("java"));
    let mut skip_next = false;
    for arg in args.iter().skip(1).take(12) {
        if skip_next {
            skip_next = false;
            continue;
        }
        if arg.starts_with('-') {
            // Flags whose value is not the program (classpaths, options).
            skip_next = matches!(arg.as_str(), "-cp" | "-classpath" | "--class-path" | "-m" | "-c" | "-e");
            if let Some(v) = arg.strip_prefix("-Dminecraft.launcher.brand=") {
                out.push(normalize_identity(v));
            }
            continue;
        }
        let lower = arg.to_lowercase();
        let path = lower.replace('\\', "/");
        for root in ["/usr/lib/", "/usr/lib64/", "/usr/share/", "/opt/"] {
            if let Some(rest) = path.split(root).nth(1) {
                if let Some(app) = rest.split('/').next() {
                    out.push(normalize_identity(app));
                }
            }
        }
        out.push(normalize_identity(&path));
        if is_java && !path.contains('/') && path.contains('.') {
            out.extend(path.split('.').filter(|s| s.len() > 2).map(str::to_string));
        }
    }
    out.retain(|t| t.len() >= 2);
    out
}

#[derive(Default)]
struct Cache {
    /// pid -> (start time, tokens)
    tokens: HashMap<u32, (u64, Vec<String>)>,
    /// (path, size, mtime) -> fingerprint
    fingerprints: HashMap<(String, u64, i64), u64>,
}

fn cache() -> &'static Mutex<Cache> {
    static C: OnceLock<Mutex<Cache>> = OnceLock::new();
    C.get_or_init(Default::default)
}

/// All wrapper identity tokens of a process (cached while the pid lives).
pub fn process_tokens(pid: u32, start_time: u64, proc_name: &str, exe: &str) -> Vec<String> {
    if let Some((st, t)) = cache().lock().tokens.get(&pid) {
        if *st == start_time {
            return t.clone();
        }
    }
    let mut tokens = Vec::new();
    let exe_base = Path::new(exe).file_name().and_then(|b| b.to_str()).unwrap_or("");
    let interpreter = is_interpreter(proc_name) || is_interpreter(exe_base);
    // The scope is inherited by anything an app starts (a browser opened from a link
    // lands in the app's scope), so it only identifies interpreters (the usual wrapper)
    // and processes inside a Flatpak sandbox.
    let sandboxed = Path::new(&format!("/proc/{pid}/root/.flatpak-info")).exists();
    if interpreter || sandboxed {
        if let Some(scope) = read_scope(pid) {
            tokens.extend(scope_tokens(&scope));
        }
    }
    if interpreter {
        tokens.extend(cmdline_tokens(&read_cmdline(pid)));
    }
    if let Some(appimage) = crate::detector::read_process_environ_map(pid).get("APPIMAGE") {
        tokens.push(normalize_identity(appimage));
    }
    tokens.sort();
    tokens.dedup();
    let mut c = cache().lock();
    if c.tokens.len() > 4096 {
        c.tokens.clear();
    }
    c.tokens.insert(pid, (start_time, tokens.clone()));
    tokens
}

/// Whether wrapper tokens identify `target` (an app exec / name, e.g. `minecraft`,
/// `Obsidian.AppImage`, `flatpak run com.spotify.Client`).
pub fn tokens_match(target: &str, tokens: &[String]) -> bool {
    let mut wanted: HashSet<String> = HashSet::new();
    let t = target.trim();
    let parts: Vec<&str> = t.split_whitespace().collect();
    if parts.len() >= 3 && parts[0] == "flatpak" && parts[1] == "run" {
        wanted.insert(parts[2].to_lowercase());
    } else if let Some(first) = parts.first() {
        wanted.insert(normalize_identity(first));
    }
    wanted.insert(normalize_identity(t));
    wanted.retain(|w| w.len() >= 2 && !crate::detector::is_generic_launcher_token(w));
    if wanted.is_empty() {
        return false;
    }
    let wanted_compact: HashSet<String> = wanted.iter().map(|w| compact(w)).filter(|w| w.len() >= 2).collect();
    tokens.iter().any(|tok| wanted.contains(tok) || wanted_compact.contains(&compact(tok)))
}

// ------------------------------------------------------------ renamed copies (layer 4)

const FINGERPRINT_KEY: &str = "blocked_exe_fingerprints";

/// Size + sampled content hash (first and last 256 KiB): fast and stable for copies.
fn fingerprint(path: &str) -> Option<u64> {
    use std::io::{Read, Seek, SeekFrom};
    let meta = std::fs::metadata(path).ok()?;
    let size = meta.len();
    if size < 4096 {
        return None;
    }
    let mtime = meta.modified().ok()?.duration_since(std::time::UNIX_EPOCH).ok()?.as_secs() as i64;
    let key = (path.to_string(), size, mtime);
    if let Some(fp) = cache().lock().fingerprints.get(&key) {
        return Some(*fp);
    }
    let mut f = std::fs::File::open(path).ok()?;
    let mut buf = vec![0u8; 256 * 1024];
    let mut h: u64 = 0xcbf29ce484222325 ^ size;
    let mut feed = |bytes: &[u8]| {
        for &b in bytes {
            h = (h ^ b as u64).wrapping_mul(0x100000001b3);
        }
    };
    let n = f.read(&mut buf).ok()?;
    feed(&buf[..n]);
    if size > buf.len() as u64 * 2 {
        f.seek(SeekFrom::End(-(buf.len() as i64))).ok()?;
        let n = f.read(&mut buf).ok()?;
        feed(&buf[..n]);
    }
    let mut c = cache().lock();
    if c.fingerprints.len() > 4096 {
        c.fingerprints.clear();
    }
    c.fingerprints.insert(key, h);
    Some(h)
}

fn learned() -> HashMap<String, Vec<u64>> {
    crate::db::try_get_conn()
        .and_then(|_| crate::db::get_config(FINGERPRINT_KEY))
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default()
}

/// Remembers the executable of a blocked app seen under its real name.
pub fn learn_blocked_executable(target: &str, exe: &str) {
    if exe.is_empty() || crate::db::try_get_conn().is_none() {
        return;
    }
    let Some(fp) = fingerprint(exe) else { return };
    let key = normalize_identity(target);
    let mut map = learned();
    let list = map.entry(key).or_default();
    if list.contains(&fp) {
        return;
    }
    list.push(fp);
    if list.len() > 8 {
        list.remove(0);
    }
    if let Ok(raw) = serde_json::to_string(&map) {
        let _ = crate::db::set_config(FINGERPRINT_KEY, &raw);
    }
}

/// A copy of a blocked executable under another name (only checked for programs in the
/// home folder or temporary folders, where a renamed copy would live).
pub fn is_renamed_copy(target: &str, exe: &str) -> bool {
    let home = std::env::var("HOME").unwrap_or_default();
    let in_user_area = (!home.is_empty() && exe.starts_with(&home)) || exe.starts_with("/tmp") || exe.starts_with("/dev/shm");
    if !in_user_area {
        return false;
    }
    let map = learned();
    let Some(known) = map.get(&normalize_identity(target)) else { return false };
    fingerprint(exe).is_some_and(|fp| known.contains(&fp))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(v: &[&str]) -> Vec<String> {
        v.iter().map(|x| x.to_string()).collect()
    }

    #[test]
    fn identities_from_wrappers() {
        assert_eq!(normalize_identity("/home/u/Apps/Obsidian-1.5.3.AppImage"), "obsidian");
        assert_eq!(normalize_identity("minecraft.jar"), "minecraft");

        assert_eq!(scope_tokens("app-Hyprland-discord-1a2b3c4d.scope"), s(&["discord"]));
        assert_eq!(scope_tokens("app-com.discordapp.Discord-1629.scope"), s(&["com.discordapp.discord", "discord"]));
        assert_eq!(scope_tokens("app-flatpak-com.spotify.Client-5678.scope"), s(&["com.spotify.client", "client"]));
        assert_eq!(scope_tokens("app-Hyprland-omarchy\\x2dhyprland\\x2dmonitor\\x2dwatch-bc86a77a.scope"), s(&["omarchy-hyprland-monitor-watch"]));
        assert!(scope_tokens("app-Hyprland-gtk\\x2dlaunch-4f1ae4d5.scope").is_empty());
        assert!(scope_tokens("tmux-spawn-84a2.scope").is_empty());

        let mc = cmdline_tokens(&s(&["java", "-Xmx2G", "-cp", "/x/libs.jar", "net.minecraft.client.main.Main"]));
        assert!(tokens_match("minecraft", &mc));
        assert!(tokens_match("jogo", &cmdline_tokens(&s(&["python3", "-u", "/home/u/jogos/jogo.py"]))));
        assert!(tokens_match("code", &cmdline_tokens(&s(&["electron", "/usr/lib/code/out/cli.js"]))));
        assert!(tokens_match("Game.exe", &cmdline_tokens(&s(&["wine64-preloader", "Z:\\games\\Game.exe"]))));
        assert!(tokens_match("flatpak run com.spotify.Client", &scope_tokens("app-flatpak-com.spotify.Client-5678.scope")));
        assert!(tokens_match("Obsidian.AppImage", &[normalize_identity("/tmp/Obsidian-1.5.3.AppImage")]));
        assert!(!tokens_match("steam", &s(&["steam"])), "launchers keep their own handling");
        assert!(!tokens_match("discord", &cmdline_tokens(&s(&["python3", "bot.py"]))));
    }

    #[test]
    fn renamed_copy_is_recognized() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db_file = std::env::temp_dir().join(format!("chronos_wrap_{}.db", std::process::id()));
        crate::db::init_db(db_file.to_str().unwrap()).unwrap();
        let dir = std::env::temp_dir().join(format!("chronos_wrap_bin_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let real = dir.join("discord");
        let copy = dir.join("notdiscord");
        let other = dir.join("other");
        let bytes: Vec<u8> = (0..20000u32).map(|i| (i * 7 % 251) as u8).collect();
        std::fs::write(&real, &bytes).unwrap();
        std::fs::write(&copy, &bytes).unwrap();
        std::fs::write(&other, vec![1u8; 20000]).unwrap();
        learn_blocked_executable("discord", real.to_str().unwrap());
        assert!(is_renamed_copy("discord", copy.to_str().unwrap()));
        assert!(!is_renamed_copy("discord", other.to_str().unwrap()));
        assert!(!is_renamed_copy("slack", copy.to_str().unwrap()));
        let _ = std::fs::remove_dir_all(dir);
        let _ = std::fs::remove_file(db_file);
    }
}

#[cfg(test)]
mod live {
    /// `cargo test --lib -- --ignored live_wrapper_tokens --nocapture`
    #[test]
    #[ignore]
    fn live_wrapper_tokens() {
        let mut sys = sysinfo::System::new();
        sys.refresh_processes(sysinfo::ProcessesToUpdate::All, true);
        let mut seen = std::collections::BTreeSet::new();
        for p in sys.processes().values() {
            let name = p.name().to_string_lossy().to_lowercase();
            let exe = p.exe().map(|e| e.to_string_lossy().to_string()).unwrap_or_default();
            let t = super::process_tokens(p.pid().as_u32(), p.start_time(), &name, &exe);
            if !t.is_empty() {
                seen.insert(format!("{name}: {t:?}"));
            }
        }
        for s in seen {
            eprintln!("{s}");
        }
    }
}
