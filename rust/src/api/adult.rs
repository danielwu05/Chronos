//! Flutter bridge for the adult content filter (domain list, SafeSearch, family DNS).

use crate::api::simple::ActionFeedback;

#[derive(Debug, Clone)]
pub struct AdultFilterDto {
    pub enabled: bool,
    pub use_domain_list: bool,
    pub safe_search: bool,
    pub log_attempts: bool,
    pub allowlist: Vec<String>,
    pub dns_protection: bool,
    pub dns_provider: String,
    /// Local image AI (blurs +18 images in the browser extension).
    pub image_ai: bool,
    /// Whole-screen image AI (any app; Hyprland only).
    pub screen_ai: bool,
    /// Parental mode keeps the filter always on (UI hides the off switch).
    pub parental_forced: bool,
    /// Number of adult domains currently loaded from the public list.
    pub domain_list_size: i64,
}

#[derive(Debug, Clone)]
pub struct AdultAttemptDto {
    pub at_utc: i64,
    pub site: String,
    pub method: String,
}

#[derive(Debug, Clone)]
pub struct DnsProviderDto {
    pub id: String,
    pub label: String,
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_adult_filter() -> AdultFilterDto {
    let s = crate::adult::settings();
    if s.enabled && s.use_domain_list {
        crate::adult::ensure_domain_list_loaded_async();
    }
    AdultFilterDto {
        enabled: s.enabled,
        use_domain_list: s.use_domain_list,
        safe_search: s.safe_search,
        log_attempts: s.log_attempts,
        allowlist: s.allowlist,
        dns_protection: s.dns_protection,
        dns_provider: s.dns_provider,
        image_ai: s.image_ai,
        screen_ai: s.screen_ai,
        parental_forced: crate::adult::is_parental_mode(),
        domain_list_size: crate::adult::domain_list_size() as i64,
    }
}

/// Saves the filter. Loosening is refused under anti-cheat; parental mode cannot disable.
/// The caller then applies `dns_protection`/`safe_search` system-wide through the guard.
pub fn save_adult_filter(filter: AdultFilterDto) -> ActionFeedback {
    let anti_cheat = crate::engine::get_anti_cheat_state().is_active;
    let next = crate::adult::AdultFilterSettings {
        enabled: filter.enabled,
        use_domain_list: filter.use_domain_list,
        safe_search: filter.safe_search,
        log_attempts: filter.log_attempts,
        allowlist: filter.allowlist,
        dns_protection: filter.dns_protection,
        dns_provider: filter.dns_provider,
        image_ai: filter.image_ai,
        screen_ai: filter.screen_ai,
    };
    match crate::adult::save_settings(next, anti_cheat) {
        Ok(()) => ActionFeedback { success: true, message: "Filtro de conteúdo adulto salvo.".to_string() },
        Err(message) => ActionFeedback { success: false, message },
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_adult_attempts(limit: u32) -> Vec<AdultAttemptDto> {
    crate::adult::recent_attempts(limit as usize)
        .into_iter()
        .map(|(at_utc, site, method)| AdultAttemptDto { at_utc, site, method })
        .collect()
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_dns_providers() -> Vec<DnsProviderDto> {
    crate::adult::DNS_PROVIDERS
        .iter()
        .map(|(id, label)| DnsProviderDto { id: id.to_string(), label: label.to_string() })
        .collect()
}

/// Incognito/private + guest browsing block (default on).
#[flutter_rust_bridge::frb(sync)]
pub fn get_private_browsing_block() -> bool {
    crate::adult::private_browsing_blocked()
}

/// Saves the choice; turning it off is refused under anti-cheat. The caller then
/// applies it system-wide through the guard (`set-incognito`).
pub fn set_private_browsing_block(blocked: bool) -> ActionFeedback {
    let anti_cheat = crate::engine::get_anti_cheat_state().is_active;
    match crate::adult::set_private_browsing_blocked(blocked, anti_cheat) {
        Ok(true) => ActionFeedback { success: true, message: crate::adult::INCOGNITO_ACCESS_HELP.to_string() },
        Ok(false) => ActionFeedback { success: true, message: String::new() },
        Err(message) => ActionFeedback { success: false, message },
    }
}

/// Whether the current network's DNS (router/provider) already blocks adult sites.
pub fn network_dns_filters_adult() -> bool {
    crate::adult::network_dns_filters_adult()
}

#[derive(Debug, Clone)]
pub struct IncognitoAccessDto {
    /// Browsers with Chronos running (reported in the last 2 minutes).
    pub browsers: i64,
    /// Of those, how many lack "Allow in incognito".
    pub denied: i64,
    /// Browsers (chrome, chromium, brave, ...) whose extension lacks incognito access.
    pub denied_browsers: Vec<String>,
    /// Browsers that reported recently (open, extension running).
    pub reported_browsers: Vec<String>,
}

/// Whether the Chronos extension may run in incognito windows in each open browser.
#[flutter_rust_bridge::frb(sync)]
pub fn get_incognito_access() -> IncognitoAccessDto {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0);
    let (known, denied) = crate::adult::incognito_access_summary(now);
    let by_browser = crate::adult::incognito_access_by_browser(now);
    let mut denied_browsers: Vec<String> =
        by_browser.iter().filter(|(_, ok)| !ok).map(|(b, _)| b.clone()).filter(|b| !b.is_empty()).collect();
    denied_browsers.dedup();
    let mut reported_browsers: Vec<String> = by_browser.iter().map(|(b, _)| b.clone()).filter(|b| !b.is_empty()).collect();
    reported_browsers.sort();
    reported_browsers.dedup();
    IncognitoAccessDto { browsers: known as i64, denied: denied as i64, denied_browsers, reported_browsers }
}

/// Whether the whole-screen detector can run here (Hyprland + grim).
#[flutter_rust_bridge::frb(sync)]
pub fn screen_ai_supported() -> bool {
    crate::screen_guard::supported()
}

#[derive(Debug, Clone)]
pub struct ScreenAlertDto {
    /// Grows by one per event (0 = none yet).
    pub seq: i64,
    pub at_ms: i64,
    /// `adult` (+18 on screen) or `app` (blocked app closed)
    pub kind: String,
    /// Window class (adult) or app name (app)
    pub name: String,
    /// For `app`: quota | window | forced | penalty | leisure
    pub reason: String,
}

/// Last screen alert (the app shows a full-screen cover when `seq` changes).
#[flutter_rust_bridge::frb(sync)]
pub fn get_screen_alert() -> ScreenAlertDto {
    let v: serde_json::Value = std::fs::read_to_string(crate::screen_guard::alert_path())
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_default();
    let s = |k: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or("").to_string();
    ScreenAlertDto {
        seq: v.get("seq").and_then(|x| x.as_i64()).unwrap_or(0),
        at_ms: v.get("at_ms").and_then(|x| x.as_i64()).unwrap_or(0),
        kind: s("kind"),
        name: s("name"),
        reason: s("reason"),
    }
}
