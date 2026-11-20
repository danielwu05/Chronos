//! Trusted wall clock. The root vault (`chronos_vault sync`) tracks system time against
//! the boot clock (and the network `Date` header) and stores a correction offset when
//! the clock is changed; the engine uses `now_secs()` = system time + that offset, so
//! moving the clock neither ends a Nuke early nor resets the daily quota.

use parking_lot::Mutex;
use serde::{Deserialize, Serialize};

/// A jump bigger than this (seconds) between wall clock and boot clock is a clock change.
pub const CLOCK_JUMP_TOLERANCE_S: i64 = 120;
/// Network time disagreement that triggers a correction.
pub const NETWORK_TOLERANCE_S: i64 = 300;

pub fn system_now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

static OFFSET_CACHE: Mutex<(i64, i64)> = Mutex::new((i64::MIN, 0)); // (read at, offset)

/// Correction offset published by the root vault (0 without a vault).
pub fn offset_secs() -> i64 {
    let now = system_now_secs();
    {
        let c = OFFSET_CACHE.lock();
        if c.0 != i64::MIN && (now - c.0).abs() < 5 {
            return c.1;
        }
    }
    let offset = crate::vault::read_published_state()
        .map(|s| s.clock.offset)
        .unwrap_or(0);
    *OFFSET_CACHE.lock() = (now, offset);
    offset
}

/// Trusted "now" (unix seconds).
pub fn now_secs() -> i64 {
    system_now_secs() + offset_secs()
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct ClockState {
    #[serde(default)]
    pub boot_id: String,
    /// Raw system time at the last check.
    #[serde(default)]
    pub last_wall: i64,
    /// Boot clock (/proc/uptime, includes suspend) at the last check.
    #[serde(default)]
    pub last_uptime: f64,
    /// trusted = wall + offset
    #[serde(default)]
    pub offset: i64,
    /// Highest trusted time seen (time never goes back across reboots).
    #[serde(default)]
    pub last_trusted: i64,
    #[serde(default)]
    pub last_network_check: i64,
}

/// Advances the clock state with a new reading; returns a description when the system
/// clock was moved (the offset then compensates it).
pub fn advance(prev: &ClockState, boot_id: &str, wall: i64, uptime: f64) -> (ClockState, Option<String>) {
    let mut s = prev.clone();
    let mut event = None;
    if prev.boot_id.is_empty() {
        s = ClockState { boot_id: boot_id.to_string(), last_wall: wall, last_uptime: uptime, offset: 0, last_trusted: wall, last_network_check: 0 };
        return (s, None);
    }
    if prev.boot_id == boot_id {
        let expected = prev.last_wall + (uptime - prev.last_uptime).round() as i64;
        let delta = wall - expected;
        if delta.abs() > CLOCK_JUMP_TOLERANCE_S {
            s.offset -= delta;
            event = Some(format!(
                "Relógio do sistema {} em {}",
                if delta > 0 { "adiantado" } else { "atrasado" },
                human_duration(delta.abs())
            ));
        }
    } else {
        // New boot: time can't be earlier than what was already seen.
        let trusted = wall + s.offset;
        if trusted < prev.last_trusted - CLOCK_JUMP_TOLERANCE_S {
            let back = prev.last_trusted - trusted;
            s.offset += back;
            event = Some(format!("Relógio voltou {} desde a última sessão", human_duration(back)));
        }
        s.boot_id = boot_id.to_string();
    }
    s.last_wall = wall;
    s.last_uptime = uptime;
    s.last_trusted = s.last_trusted.max(wall + s.offset);
    (s, event)
}

/// Applies a network time reading (ground truth).
pub fn apply_network(prev: &ClockState, wall: i64, network: i64) -> (ClockState, Option<String>) {
    let mut s = prev.clone();
    s.last_network_check = wall;
    let trusted = wall + s.offset;
    if (trusted - network).abs() > NETWORK_TOLERANCE_S {
        let old = s.offset;
        s.offset = network - wall;
        s.last_trusted = network;
        let drift = network - (wall + old);
        // A wrong system clock without an earlier correction is a manual change.
        if (network - wall).abs() > NETWORK_TOLERANCE_S {
            return (
                s,
                Some(format!(
                    "Relógio do sistema difere da hora da internet em {}",
                    human_duration(drift.abs())
                )),
            );
        }
    }
    (s, None)
}

fn human_duration(secs: i64) -> String {
    if secs >= 86400 {
        format!("{} dia(s)", secs / 86400)
    } else if secs >= 3600 {
        format!("{} h", secs / 3600)
    } else if secs >= 60 {
        format!("{} min", secs / 60)
    } else {
        format!("{secs} s")
    }
}

pub fn read_boot_id() -> String {
    std::fs::read_to_string("/proc/sys/kernel/random/boot_id")
        .map(|s| s.trim().to_string())
        .unwrap_or_default()
}

pub fn read_uptime() -> f64 {
    std::fs::read_to_string("/proc/uptime")
        .ok()
        .and_then(|s| s.split_whitespace().next().and_then(|v| v.parse().ok()))
        .unwrap_or(0.0)
}

/// Parses an HTTP `Date` header (RFC 7231: "Wed, 19 Nov 2026 15:04:05 GMT").
pub fn parse_http_date(s: &str) -> Option<i64> {
    let parts: Vec<&str> = s.split_whitespace().collect();
    if parts.len() < 5 {
        return None;
    }
    let day: i64 = parts[1].parse().ok()?;
    let month = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        .iter()
        .position(|m| m.eq_ignore_ascii_case(parts[2]))? as i64
        + 1;
    let year: i64 = parts[3].parse().ok()?;
    let hms: Vec<i64> = parts[4].split(':').filter_map(|v| v.parse().ok()).collect();
    if hms.len() != 3 {
        return None;
    }
    // days from civil (Howard Hinnant)
    let y = if month <= 2 { year - 1 } else { year };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    Some(days * 86400 + hms[0] * 3600 + hms[1] * 60 + hms[2])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clock_jumps_are_compensated() {
        let (s0, e) = advance(&ClockState::default(), "b1", 1_000_000, 100.0);
        assert!(e.is_none());
        // normal flow: 60 s later
        let (s1, e) = advance(&s0, "b1", 1_000_060, 160.0);
        assert!(e.is_none());
        assert_eq!(s1.offset, 0);
        // clock moved forward 1 day
        let (s2, e) = advance(&s1, "b1", 1_000_060 + 86_400 + 5, 165.0);
        assert!(e.unwrap().contains("adiantado"));
        assert_eq!(1_000_060 + 86_400 + 5 + s2.offset, 1_000_065, "trusted keeps real time");
        // clock moved back 2 h
        let (s3, e) = advance(&s2, "b1", 1_000_070 - 7_200, 175.0);
        assert!(e.unwrap().contains("atrasado"));
        assert_eq!(1_000_070 - 7_200 + s3.offset, 1_000_075);
        // reboot with clock set to the past
        let (s4, e) = advance(&s3, "b2", 900_000, 10.0);
        assert!(e.unwrap().contains("voltou"));
        assert!(900_000 + s4.offset >= s3.last_trusted - CLOCK_JUMP_TOLERANCE_S);
        // network corrects
        let (s5, e) = apply_network(&s4, 2_000_000, 2_000_000);
        assert_eq!(s5.offset, 0);
        assert!(e.is_none(), "system clock right: correction only");
    }

    #[test]
    fn http_date_parses() {
        assert_eq!(parse_http_date("Thu, 01 Jan 1970 00:00:00 GMT"), Some(0));
        assert_eq!(parse_http_date("Wed, 19 Nov 2026 15:04:05 GMT"), Some(1795100645));
        assert!(parse_http_date("garbage").is_none());
    }
}
