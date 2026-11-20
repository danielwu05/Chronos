//! Release vs dev profile, so a development build can run side by side with the
//! installed release without sharing ports, data, services or system integrations.
//!
//! | | release | dev |
//! |---|---|---|
//! | API / proxy ports | 4545 / 4546 | 5545 / 5546 |
//! | data dir | `~/.local/share/chronos` | `~/.local/share/chronos-dev` |
//! | system integrations (guard, DNS, launcher wrappers, Lutris DB) | yes | no |
//!
//! The daemon learns its profile from `CHRONOS_PROFILE=dev` (set in its unit / dev script);
//! the app sets it through [`set_dev`] right after startup.

use std::path::PathBuf;
use std::sync::atomic::{AtomicU8, Ordering};

// 0 = unknown (read env), 1 = release, 2 = dev
static PROFILE: AtomicU8 = AtomicU8::new(0);

pub fn set_dev(dev: bool) {
    PROFILE.store(if dev { 2 } else { 1 }, Ordering::SeqCst);
}

pub fn is_dev() -> bool {
    match PROFILE.load(Ordering::SeqCst) {
        2 => true,
        1 => false,
        _ => {
            let dev = std::env::var("CHRONOS_PROFILE").is_ok_and(|v| v.eq_ignore_ascii_case("dev"));
            set_dev(dev);
            dev
        }
    }
}

pub fn api_port_for(dev: bool) -> u16 {
    if dev { 5545 } else { 4545 }
}

pub fn proxy_port_for(dev: bool) -> u16 {
    if dev { 5546 } else { 4546 }
}

pub fn data_dir_name_for(dev: bool) -> &'static str {
    if dev { "chronos-dev" } else { "chronos" }
}

pub fn api_port() -> u16 {
    api_port_for(is_dev())
}

pub fn proxy_port() -> u16 {
    proxy_port_for(is_dev())
}

/// `http://127.0.0.1:<api port>`
pub fn api_base() -> String {
    format!("http://127.0.0.1:{}", api_port())
}

/// `127.0.0.1:<api port>` (for "is this our own page?" checks).
pub fn api_host() -> String {
    format!("127.0.0.1:{}", api_port())
}

fn home() -> String {
    std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string())
}

/// `~/.local/share/chronos` (release) or `~/.local/share/chronos-dev` (dev).
pub fn data_dir() -> PathBuf {
    PathBuf::from(format!("{}/.local/share/{}", home(), data_dir_name_for(is_dev())))
}

/// System-wide side effects (launcher `.desktop` wrappers, Lutris DB edits, guard)
/// only belong to the release install.
pub fn allows_system_integrations() -> bool {
    !is_dev()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_profile_ports_and_dirs() {
        assert_eq!((api_port_for(true), proxy_port_for(true)), (5545, 5546));
        assert_eq!((api_port_for(false), proxy_port_for(false)), (4545, 4546));
        assert_eq!(data_dir_name_for(true), "chronos-dev");
        assert_eq!(data_dir_name_for(false), "chronos");
    }
}
