//! Holiday quotas: priority is holiday > weekend > weekday.
//!
//! Holidays are Brazilian national holidays (fixed + Easter-based, including the
//! optional Carnaval / Corpus Christi days) plus user-defined dates. Each rule may
//! have its own holiday quota (stored in `app_config` as `holiday_quotas`).

use std::collections::BTreeMap;

use crate::db;

const CUSTOM_KEY: &str = "custom_holidays";
const QUOTAS_KEY: &str = "holiday_quotas";

/// Civil date (year, month 1-12, day 1-31).
pub type Ymd = (i32, u32, u32);

fn is_leap(y: i32) -> bool {
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

fn days_in_month(y: i32, m: u32) -> u32 {
    match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        _ if is_leap(y) => 29,
        _ => 28,
    }
}

/// Days since 1970-01-01 for a civil date (proleptic Gregorian).
fn to_days(y: i32, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y } as i64;
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m as i64 + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

fn from_days(z: i64) -> Ymd {
    let z = z + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let y = (yoe + era * 400 + if m <= 2 { 1 } else { 0 }) as i32;
    (y, m, d)
}

/// Easter Sunday (anonymous Gregorian algorithm).
pub fn easter(y: i32) -> Ymd {
    let a = y % 19;
    let b = y / 100;
    let c = y % 100;
    let d = b / 4;
    let e = b % 4;
    let f = (b + 8) / 25;
    let g = (b - f + 1) / 3;
    let h = (19 * a + b - d - g + 15) % 30;
    let i = c / 4;
    let k = c % 4;
    let l = (32 + 2 * e + 2 * i - h - k) % 7;
    let m = (a + 11 * h + 22 * l) / 451;
    let month = (h + l - 7 * m + 114) / 31;
    let day = (h + l - 7 * m + 114) % 31 + 1;
    (y, month as u32, day as u32)
}

/// Brazilian national holidays (and optional days) for a year: date -> name.
pub fn national_holidays(y: i32) -> BTreeMap<Ymd, &'static str> {
    let mut out = BTreeMap::new();
    for (m, d, name) in [
        (1, 1, "Confraternização Universal"),
        (4, 21, "Tiradentes"),
        (5, 1, "Dia do Trabalho"),
        (9, 7, "Independência do Brasil"),
        (10, 12, "Nossa Senhora Aparecida"),
        (11, 2, "Finados"),
        (11, 15, "Proclamação da República"),
        (11, 20, "Dia da Consciência Negra"),
        (12, 25, "Natal"),
    ] {
        out.insert((y, m, d), name);
    }
    let (ey, em, ed) = easter(y);
    let e = to_days(ey, em, ed);
    for (offset, name) in [
        (-48, "Carnaval (segunda)"),
        (-47, "Carnaval (terça)"),
        (-2, "Sexta-feira Santa"),
        (60, "Corpus Christi"),
    ] {
        out.insert(from_days(e + offset), name);
    }
    out
}

pub fn parse_ymd(s: &str) -> Option<Ymd> {
    let mut it = s.trim().splitn(3, '-');
    let y = it.next()?.parse::<i32>().ok()?;
    let m = it.next()?.parse::<u32>().ok()?;
    let d = it.next()?.parse::<u32>().ok()?;
    ((1..=12).contains(&m) && d >= 1 && d <= days_in_month(y, m)).then_some((y, m, d))
}

pub fn format_ymd((y, m, d): Ymd) -> String {
    format!("{y:04}-{m:02}-{d:02}")
}

/// User-defined holidays (`YYYY-MM-DD` -> name).
pub fn custom_holidays() -> BTreeMap<String, String> {
    db::try_get_conn()
        .and_then(|_| db::get_config(CUSTOM_KEY))
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default()
}

/// Saves custom holidays. Under anti-cheat, adding dates (more lenient days) is refused.
pub fn save_custom_holidays(next: BTreeMap<String, String>, anti_cheat_active: bool) -> Result<(), String> {
    let mut clean = BTreeMap::new();
    for (date, name) in next {
        let ymd = parse_ymd(&date).ok_or_else(|| format!("Data inválida: {date}"))?;
        let label = if name.trim().is_empty() { "Feriado personalizado".to_string() } else { name.trim().to_string() };
        clean.insert(format_ymd(ymd), label);
    }
    if anti_cheat_active {
        let current = custom_holidays();
        if let Some(added) = clean.keys().find(|k| !current.contains_key(*k)) {
            return Err(format!(
                "Modo Anti-Burla está ativo! Adicionar o feriado {added} exige desativar o Anti-Burla."
            ));
        }
    }
    db::set_config(CUSTOM_KEY, &serde_json::to_string(&clean).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())?;
    let _ = db::bump_state_revision();
    Ok(())
}

/// Holiday name for a date, if any (national, optional or custom).
pub fn holiday_name(date: Ymd) -> Option<String> {
    if let Some(n) = national_holidays(date.0).get(&date) {
        return Some(n.to_string());
    }
    custom_holidays().get(&format_ymd(date)).cloned()
}

/// Today's local date (via SQLite `localtime`, consistent with the engine's weekday logic).
pub fn today_local() -> Ymd {
    let s: Option<String> = db::try_get_conn().and_then(|c| {
        c.lock()
            .query_row("SELECT date(?1, 'unixepoch', 'localtime')", [crate::trusted_time::now_secs()], |r| r.get(0))
            .ok()
    });
    s.as_deref().and_then(parse_ymd).unwrap_or_else(|| {
        let now = crate::trusted_time::now_secs();
        from_days(now / 86400)
    })
}

/// Upcoming holidays from `from` (inclusive), at most `limit`.
pub fn upcoming(from: Ymd, limit: usize) -> Vec<(String, String)> {
    let start = to_days(from.0, from.1, from.2);
    let mut all: BTreeMap<i64, String> = BTreeMap::new();
    for y in [from.0, from.0 + 1] {
        for (date, name) in national_holidays(y) {
            all.insert(to_days(date.0, date.1, date.2), name.to_string());
        }
    }
    for (date, name) in custom_holidays() {
        if let Some(d) = parse_ymd(&date) {
            all.insert(to_days(d.0, d.1, d.2), name);
        }
    }
    all.range(start..)
        .take(limit)
        .map(|(d, n)| (format_ymd(from_days(*d)), n.clone()))
        .collect()
}

// ---------------------------------------------------------------------------
// Per-rule holiday quotas

pub fn holiday_quotas() -> BTreeMap<String, i64> {
    db::try_get_conn()
        .and_then(|_| db::get_config(QUOTAS_KEY))
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default()
}

fn rule_daily_quota(entity_id: &str) -> Option<i64> {
    db::try_get_conn()?
        .lock()
        .query_row("SELECT daily_quota_seconds FROM rules WHERE entity_id = ?1", [entity_id], |r| r.get(0))
        .ok()
}

/// Sets (or clears with `None`) a rule's holiday quota. Under anti-cheat, raising
/// it, or creating/removing one above the normal quota, is refused.
pub fn set_holiday_quota(entity_id: &str, seconds: Option<i64>, anti_cheat_active: bool) -> Result<(), String> {
    let mut all = holiday_quotas();
    let current = all.get(entity_id).copied();
    let next = seconds.filter(|s| *s > 0);
    if anti_cheat_active {
        // Baseline = what applies on holidays today: the holiday quota if set, else the
        // rule's normal daily quota. Only going above it is loosening.
        let baseline = current.or_else(|| rule_daily_quota(entity_id));
        let more_lenient = match (baseline, next) {
            (Some(b), Some(n)) => n > b,
            (None, Some(_)) => true,
            // Removing a holiday quota falls back to the normal quota: lenient if that is higher.
            (Some(b), None) => current.is_some() && rule_daily_quota(entity_id).is_some_and(|d| d > b),
            (None, None) => false,
        };
        if more_lenient {
            return Err("Modo Anti-Burla está ativo! Aumentar a cota de feriado exige desativar o Anti-Burla.".to_string());
        }
    }
    match next {
        Some(s) => {
            all.insert(entity_id.to_string(), s);
        }
        None => {
            all.remove(entity_id);
        }
    }
    db::set_config(QUOTAS_KEY, &serde_json::to_string(&all).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())?;
    let _ = db::bump_state_revision();
    Ok(())
}

/// Effective quota: today's holiday quota for the rule when set, otherwise `base`
/// (which already applies the weekend override). Must be called outside DB locks.
pub fn apply_holiday_quota(entity_id: &str, base: i64) -> (i64, Option<String>) {
    let quotas = holiday_quotas();
    let Some(q) = quotas.get(entity_id).copied() else {
        return (base, None);
    };
    match holiday_name(today_local()) {
        Some(name) => (q, Some(name)),
        None => (base, None),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_easter_and_national_holidays() {
        assert_eq!(easter(2024), (2024, 3, 31));
        assert_eq!(easter(2025), (2025, 4, 20));
        assert_eq!(easter(2026), (2026, 4, 5));
        let h = national_holidays(2026);
        assert_eq!(h.get(&(2026, 2, 16)), Some(&"Carnaval (segunda)"));
        assert_eq!(h.get(&(2026, 2, 17)), Some(&"Carnaval (terça)"));
        assert_eq!(h.get(&(2026, 4, 3)), Some(&"Sexta-feira Santa"));
        assert_eq!(h.get(&(2026, 6, 4)), Some(&"Corpus Christi"));
        assert_eq!(h.get(&(2026, 11, 20)), Some(&"Dia da Consciência Negra"));
        assert!(h.get(&(2026, 3, 10)).is_none());
        assert_eq!(from_days(to_days(2028, 2, 29)), (2028, 2, 29));
        assert!(parse_ymd("2026-02-30").is_none());
        assert_eq!(parse_ymd("2026-12-24"), Some((2026, 12, 24)));
    }

    #[test]
    fn test_custom_holidays_and_quotas_with_anti_cheat() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db_file = format!("/tmp/chronos_holidays_{}.db", std::process::id());
        let _ = std::fs::remove_file(&db_file);
        db::init_db(&db_file).expect("init temp db");

        let mut next = BTreeMap::new();
        next.insert("2026-12-24".to_string(), "Véspera".to_string());
        save_custom_holidays(next.clone(), false).unwrap();
        assert_eq!(holiday_name((2026, 12, 24)).as_deref(), Some("Véspera"));
        assert_eq!(holiday_name((2026, 12, 25)).as_deref(), Some("Natal"));

        let mut more = next.clone();
        more.insert("2026-12-31".to_string(), String::new());
        assert!(save_custom_holidays(more, true).is_err(), "adding under anti-cheat refused");
        assert!(save_custom_holidays(BTreeMap::new(), true).is_ok(), "removing is fine");
        assert!(save_custom_holidays(
            [("2026-13-01".to_string(), String::new())].into_iter().collect(),
            false
        )
        .is_err());

        set_holiday_quota("yt", Some(7200), false).unwrap();
        assert_eq!(holiday_quotas().get("yt"), Some(&7200));
        assert!(set_holiday_quota("yt", Some(9000), true).is_err(), "raise refused");
        assert!(set_holiday_quota("yt", Some(3600), true).is_ok(), "lower allowed");
        assert!(set_holiday_quota("other", Some(60), true).is_err(), "unknown rule: refused");
        db::get_conn()
            .lock()
            .execute(
                "INSERT INTO rules (entity_id, display_name, daily_quota_seconds, mode, updated_at_utc) VALUES ('sess', 'Sessão', 3600, 'SELF_CONTROL', 0)",
                [],
            )
            .unwrap();
        assert!(set_holiday_quota("sess", Some(7200), true).is_err(), "new holiday quota above normal refused");
        assert!(set_holiday_quota("sess", Some(1800), true).is_ok(), "new holiday quota below normal allowed");
        assert!(set_holiday_quota("sess", None, true).is_err(), "removing would fall back to the higher normal quota");
        set_holiday_quota("sess", None, false).unwrap();
        set_holiday_quota("yt", None, true).unwrap();
        assert!(holiday_quotas().is_empty());

        // Today becomes a holiday -> quota applies only to rules that have one
        let today = format_ymd(today_local());
        save_custom_holidays([(today, "Hoje".to_string())].into_iter().collect(), false).unwrap();
        set_holiday_quota("yt", Some(10800), false).unwrap();
        // Name: "Hoje", or the national holiday when the test runs on one (e.g. 20/11).
        let (quota, name) = apply_holiday_quota("yt", 3600);
        assert_eq!(quota, 10800);
        assert!(name.is_some());
        assert_eq!(apply_holiday_quota("other", 3600), (3600, None));

        let up = upcoming((2026, 12, 20), 2);
        assert_eq!(up[0].0, "2026-12-25");

        let _ = std::fs::remove_file(db_file);
    }
}
