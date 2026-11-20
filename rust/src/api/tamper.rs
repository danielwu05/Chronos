//! Flutter bridge for the layered anti-cheat (root vault): tamper log and reaction.

use crate::api::simple::ActionFeedback;

#[derive(Debug, Clone)]
pub struct TamperEventDto {
    pub at_utc: i64,
    pub kind: String,
    pub detail: String,
}

#[derive(Debug, Clone)]
pub struct VaultStatusDto {
    /// Root vault present (guard installed with layered anti-cheat).
    pub installed: bool,
    /// Clock correction currently applied (seconds).
    pub clock_offset_seconds: i64,
    /// Tamper penalty: sessions blocked until this time (0 = none).
    pub penalty_until_utc: i64,
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_tamper_events(limit: u32) -> Vec<TamperEventDto> {
    crate::vault::read_tamper_events(&crate::vault::current_user(), limit as usize)
        .into_iter()
        .map(|e| TamperEventDto { at_utc: e.at, kind: e.kind, detail: crate::i18n::tr_msg(&e.detail) })
        .collect()
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_vault_status() -> VaultStatusDto {
    let state = crate::vault::read_published_state();
    let now = crate::trusted_time::now_secs();
    let penalty = crate::db::get_config("penalty_until")
        .and_then(|v| v.parse::<i64>().ok())
        .filter(|u| *u > now)
        .unwrap_or(0);
    VaultStatusDto {
        installed: state.is_some(),
        clock_offset_seconds: state.map(|s| s.clock.offset).unwrap_or(0),
        penalty_until_utc: penalty,
    }
}

/// "restore" or "restore_penalty".
#[flutter_rust_bridge::frb(sync)]
pub fn get_tamper_reaction() -> String {
    crate::engine::tamper_reaction()
}

pub fn set_tamper_reaction(reaction: String) -> ActionFeedback {
    match crate::engine::set_tamper_reaction(&reaction) {
        Ok(()) => ActionFeedback { success: true, message: "Reação a burlas salva.".to_string() },
        Err(message) => ActionFeedback { success: false, message },
    }
}
