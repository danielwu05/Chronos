//! Flutter bridge for YouTube content types (whitelist exemptions + analytics).

#[derive(Debug, Clone)]
pub struct YtContentTypeDto {
    pub id: String,
    pub label: String,
}

#[derive(Debug, Clone)]
pub struct YtExemptTotalDto {
    pub type_id: String,
    pub label: String,
    pub seconds: i64,
}

#[derive(Debug, Clone)]
pub struct YtCustomRuleDto {
    /// Built-in id (e.g. `podcasts`) or a new custom id (e.g. `custom_minecraft`).
    pub type_id: String,
    pub name: String,
    pub channels: Vec<String>,
    pub keywords: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct ExtensionUpdateStatusDto {
    pub auto_update: bool,
    /// Newest packaged extension version (served to browsers).
    pub latest_version: String,
    /// Newest Mozilla-signed version the app can deliver to Firefox ("" = none).
    pub firefox_latest_version: String,
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_extension_update_status() -> ExtensionUpdateStatusDto {
    ExtensionUpdateStatusDto {
        auto_update: crate::local_api::extension_auto_update_enabled(),
        latest_version: crate::local_api::latest_extension_version_cached().unwrap_or_default(),
        firefox_latest_version: crate::firefox_updates::latest_firefox_version().unwrap_or_default(),
    }
}

/// When on, browser extensions check for and install the newest Chronos extension
/// as soon as the app packages a new version.
pub fn set_extension_auto_update(enabled: bool) {
    crate::local_api::set_extension_auto_update(enabled);
}

/// Asks every connected browser extension to check for an update right now.
pub fn request_extension_update_now() {
    crate::local_api::request_extension_update_now();
}

/// Built-in YouTube content types plus custom types created by the user.
#[flutter_rust_bridge::frb(sync)]
pub fn get_youtube_content_types() -> Vec<YtContentTypeDto> {
    let mut out: Vec<YtContentTypeDto> = crate::youtube::BUILTIN_TYPES
        .iter()
        .map(|(id, label)| YtContentTypeDto {
            id: id.to_string(),
            label: crate::i18n::tr_msg(label),
        })
        .collect();
    for rule in crate::youtube::custom_rules() {
        if !out.iter().any(|t| t.id == rule.type_id) {
            out.push(YtContentTypeDto {
                id: rule.type_id,
                label: rule.name,
            });
        }
    }
    out
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_youtube_custom_rules() -> Vec<YtCustomRuleDto> {
    crate::youtube::custom_rules()
        .into_iter()
        .map(|r| YtCustomRuleDto {
            type_id: r.type_id,
            name: r.name,
            channels: r.channels,
            keywords: r.keywords,
        })
        .collect()
}

pub fn save_youtube_custom_rules(rules: Vec<YtCustomRuleDto>) -> crate::api::simple::ActionFeedback {
    let anti_cheat = crate::engine::get_anti_cheat_state().is_active;
    let native = rules
        .into_iter()
        .map(|r| crate::youtube::YtCustomRule {
            type_id: r.type_id,
            name: r.name,
            channels: r.channels,
            keywords: r.keywords,
        })
        .collect();
    match crate::youtube::save_custom_rules(native, anti_cheat) {
        Ok(()) => crate::api::simple::ActionFeedback {
            success: true,
            message: crate::i18n::tr_msg(&("Tipos personalizados do YouTube salvos.".to_string())),
        },
        Err(message) => crate::api::simple::ActionFeedback { success: false, message },
    }
}

/// Exempt (not quota-consuming) YouTube time per type over the last `days` days (1 = today).
pub fn get_youtube_exempt_totals(days: i64) -> Vec<YtExemptTotalDto> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;
    let day_start = now - (now % 86400);
    let since = day_start - (days.max(1) - 1) * 86400;
    crate::youtube::exempt_totals_since(since)
        .into_iter()
        .map(|(type_id, seconds)| YtExemptTotalDto {
            label: crate::youtube::type_label(&type_id),
            type_id,
            seconds,
        })
        .collect()
}
