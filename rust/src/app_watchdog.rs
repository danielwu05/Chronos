//! Relaunches the Chronos desktop app when its process is killed.
//!
//! The app records `{pid, exe}` in `~/.local/share/chronos/app.json` at startup. The
//! `chronos_proxy` daemon (a `Restart=always` systemd user service) checks it every few
//! seconds and relaunches `exe --background` when that pid is gone, unless the
//! `.uninstalling` marker exists. The app, in turn, keeps the daemon running.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicI64, Ordering};

const RESPAWN_MIN_INTERVAL_SECS: i64 = 20;

fn data_dir() -> PathBuf {
    crate::profile::data_dir()
}

fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

/// True when `pid` is alive and still runs `exe` (guards against pid reuse).
pub fn app_is_alive(pid: u32, exe: &Path) -> bool {
    let Ok(target) = std::fs::read_link(format!("/proc/{pid}/exe")) else {
        return false;
    };
    let canon_exe = std::fs::canonicalize(exe).unwrap_or_else(|_| exe.to_path_buf());
    let target_str = target.to_string_lossy();
    // A replaced binary (rebuild/update) shows up as "<path> (deleted)".
    target == canon_exe || target_str.trim_end_matches(" (deleted)") == canon_exe.to_string_lossy()
}

fn graphical_session_available() -> bool {
    if std::env::var("WAYLAND_DISPLAY").is_ok() || std::env::var("DISPLAY").is_ok() {
        return true;
    }
    let runtime = std::env::var("XDG_RUNTIME_DIR").unwrap_or_default();
    std::fs::read_dir(&runtime)
        .map(|it| it.flatten().any(|e| e.file_name().to_string_lossy().starts_with("wayland-")))
        .unwrap_or(false)
}

static LAST_SPAWN: AtomicI64 = AtomicI64::new(0);

/// Checks the app and relaunches it in the background if needed. Returns true if a
/// relaunch was attempted.
pub fn ensure_app_running() -> bool {
    // Dev builds can be closed normally and are never relaunched.
    if crate::profile::is_dev() {
        return false;
    }
    let dir = data_dir();
    if dir.join(".uninstalling").exists() {
        return false;
    }
    let Ok(raw) = std::fs::read_to_string(dir.join("app.json")) else {
        return false;
    };
    let Ok(v) = serde_json::from_str::<serde_json::Value>(&raw) else {
        return false;
    };
    let pid = v.get("pid").and_then(|p| p.as_u64()).unwrap_or(0) as u32;
    let Some(exe) = v.get("exe").and_then(|e| e.as_str()).map(PathBuf::from) else {
        return false;
    };
    if (pid > 0 && app_is_alive(pid, &exe)) || !exe.is_file() || !graphical_session_available() {
        return false;
    }
    let t = now();
    if t - LAST_SPAWN.load(Ordering::SeqCst) < RESPAWN_MIN_INTERVAL_SECS {
        return false;
    }
    LAST_SPAWN.store(t, Ordering::SeqCst);
    // A transient unit gets the session environment from the user manager and is not
    // killed when this daemon restarts (it is outside our cgroup).
    let spawned = std::process::Command::new("systemd-run")
        .args(["--user", "--collect", "--quiet", "--unit"])
        .arg(format!("chronos-app-{t}"))
        .arg(&exe)
        .arg("--background")
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if !spawned {
        let _ = std::process::Command::new(&exe).arg("--background").spawn();
    }
    eprintln!("chronos watchdog: relaunched app {}", exe.display());
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_app_is_alive_checks_pid_and_exe() {
        let me = std::process::id();
        let my_exe = std::env::current_exe().unwrap();
        assert!(app_is_alive(me, &my_exe));
        assert!(!app_is_alive(me, Path::new("/usr/bin/definitely-not-chronos")), "pid reuse guard");
        assert!(!app_is_alive(u32::MAX - 7, &my_exe), "dead pid");
    }
}
