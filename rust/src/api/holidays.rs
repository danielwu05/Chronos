//! Flutter bridge for holiday quotas (holiday > weekend > weekday).

use crate::api::simple::ActionFeedback;

#[derive(Debug, Clone)]
pub struct HolidayDto {
    /// `YYYY-MM-DD`
    pub date: String,
    pub name: String,
}

#[derive(Debug, Clone)]
pub struct HolidayQuotaDto {
    pub entity_id: String,
    pub seconds: i64,
}

fn feedback(res: Result<(), String>, ok: &str) -> ActionFeedback {
    match res {
        Ok(()) => ActionFeedback { success: true, message: ok.to_string() },
        Err(message) => ActionFeedback { success: false, message },
    }
}

/// Name of today's holiday (national, optional or custom), if any.
#[flutter_rust_bridge::frb(sync)]
pub fn get_today_holiday() -> Option<String> {
    crate::holidays::holiday_name(crate::holidays::today_local())
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_upcoming_holidays(limit: u32) -> Vec<HolidayDto> {
    crate::holidays::upcoming(crate::holidays::today_local(), limit as usize)
        .into_iter()
        .map(|(date, name)| HolidayDto { date, name: crate::i18n::tr_msg(&name) })
        .collect()
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_custom_holidays() -> Vec<HolidayDto> {
    crate::holidays::custom_holidays()
        .into_iter()
        .map(|(date, name)| HolidayDto { date, name })
        .collect()
}

pub fn save_custom_holidays(holidays: Vec<HolidayDto>) -> ActionFeedback {
    let anti_cheat = crate::engine::get_anti_cheat_state().is_active;
    let map = holidays.into_iter().map(|h| (h.date, h.name)).collect();
    feedback(crate::holidays::save_custom_holidays(map, anti_cheat), "Feriados salvos.")
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_holiday_quotas() -> Vec<HolidayQuotaDto> {
    crate::holidays::holiday_quotas()
        .into_iter()
        .map(|(entity_id, seconds)| HolidayQuotaDto { entity_id, seconds })
        .collect()
}

/// Sets a rule's holiday quota in seconds (`None` or `<= 0` removes it).
pub fn set_holiday_quota(entity_id: String, seconds: Option<i64>) -> ActionFeedback {
    let anti_cheat = crate::engine::get_anti_cheat_state().is_active;
    feedback(
        crate::holidays::set_holiday_quota(&entity_id, seconds, anti_cheat),
        "Cota de feriado salva.",
    )
}
