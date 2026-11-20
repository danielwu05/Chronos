//! Conflicts between block groups, whitelists and YouTube "show only" (YouTube stage 3).
//!
//! - the same app/site in a whitelist and in a block group;
//! - the same app/site/YouTube type in two whitelists;
//! - the same app/site in two block groups whose active days overlap;
//! - a whitelisted YouTube type hidden by "Mostrar apenas".
//!
//! The YouTube exemption (the YouTube app blocked + educational types whitelisted) is
//! not a conflict. Saves are refused only when they CREATE a conflict, so existing ones
//! never lock the user out (e.g. renaming under anti-cheat).

use std::collections::{BTreeSet, HashMap};

#[derive(Debug, Clone)]
pub struct RuleIn {
    pub id: String,
    pub name: String,
    pub target_type: String,
    pub pattern: String,
    pub schedule_json: Option<String>,
}

#[derive(Debug, Clone)]
pub struct WhitelistIn {
    pub id: String,
    pub name: String,
    pub items: String,
}

#[derive(Debug, Clone, Default)]
pub struct Inputs {
    pub rules: Vec<RuleIn>,
    pub whitelist: Vec<WhitelistIn>,
    /// "Mostrar apenas" types when enabled.
    pub show_only: Option<Vec<String>>,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct Conflict {
    pub kind: &'static str,
    /// Human label of the item ("app firefox", "site reddit.com", "tipo Música").
    pub item: String,
    /// Display names of the groups involved (sorted).
    pub groups: Vec<String>,
    /// Stable key: kind + item + group ids.
    pub key: String,
}

impl Conflict {
    pub fn message(&self) -> String {
        match self.kind {
            "whitelist_block" => format!(
                "{} está na lista branca e num grupo de bloqueio ({}).",
                self.item,
                self.groups.join(", ")
            ),
            "two_whitelists" => format!("{} está em duas listas brancas ({}).", self.item, self.groups.join(", ")),
            "two_blocks" => format!(
                "{} está em dois grupos de bloqueio com dias em comum ({}).",
                self.item,
                self.groups.join(", ")
            ),
            "show_only" => format!(
                "{} está na lista branca ({}), mas o \"Mostrar apenas\" do YouTube o esconde.",
                self.item,
                self.groups.join(", ")
            ),
            _ => self.item.clone(),
        }
    }
}

fn norm_app(name: &str, exec: &str) -> Option<String> {
    let e = crate::detector::extract_binary_basename(exec);
    let key = if !e.is_empty() { e } else { name.trim().to_lowercase() };
    (!key.is_empty()).then_some(key)
}

fn norm_site(raw: &str) -> Option<String> {
    let r = raw.trim().to_lowercase();
    let r = r.strip_prefix("https://").or_else(|| r.strip_prefix("http://")).unwrap_or(&r);
    let host = r.split(['/', '?', '#']).next().unwrap_or("").trim_start_matches("www.").trim_end_matches('.');
    (host.contains('.')).then(|| host.to_string())
}

/// ("app"|"site"|"yt", key) items of a JSON pattern / whitelist items.
fn items_of_json(raw: &str) -> BTreeSet<(&'static str, String)> {
    let mut out = BTreeSet::new();
    let Ok(v) = serde_json::from_str::<serde_json::Value>(raw.trim()) else {
        return out;
    };
    if let Some(apps) = v.get("apps").and_then(|a| a.as_array()) {
        for a in apps {
            let (name, exec) = match a {
                serde_json::Value::String(s) => (s.as_str(), ""),
                serde_json::Value::Object(o) => (
                    o.get("name").and_then(|x| x.as_str()).unwrap_or(""),
                    o.get("exec").and_then(|x| x.as_str()).unwrap_or(""),
                ),
                _ => continue,
            };
            if let Some(k) = norm_app(name, exec) {
                out.insert(("app", k));
            }
        }
    }
    if let Some(sites) = v.get("sites").and_then(|a| a.as_array()) {
        for s in sites.iter().filter_map(|s| s.as_str()) {
            if let Some(k) = norm_site(s) {
                out.insert(("site", k));
            }
        }
    }
    if let Some(types) = v.get("yt_types").and_then(|a| a.as_array()) {
        for t in types {
            let id = t.get("type").and_then(|x| x.as_str()).or_else(|| t.as_str()).unwrap_or("");
            if !id.trim().is_empty() {
                out.insert(("yt", id.trim().to_lowercase()));
            }
        }
    }
    out
}

fn rule_items(r: &RuleIn) -> BTreeSet<(&'static str, String)> {
    match r.target_type.as_str() {
        "GROUP" | "SITE_GROUP" => items_of_json(&r.pattern),
        "APP" => {
            let exec = if r.pattern.trim().is_empty() { r.id.as_str() } else { r.pattern.as_str() };
            norm_app(&r.name, exec).map(|k| ("app", k)).into_iter().collect()
        }
        "SITE" => norm_site(if r.pattern.trim().is_empty() { &r.id } else { &r.pattern })
            .map(|k| ("site", k))
            .into_iter()
            .collect(),
        _ => BTreeSet::new(),
    }
}

/// ISO days (1 = Mon .. 7 = Sun) the rule is active; empty/missing = every day.
fn rule_days(r: &RuleIn) -> BTreeSet<i64> {
    let days: BTreeSet<i64> = r
        .schedule_json
        .as_deref()
        .and_then(|s| serde_json::from_str::<serde_json::Value>(s).ok())
        .and_then(|v| v.get("days").and_then(|d| d.as_array()).cloned())
        .map(|arr| arr.iter().filter_map(|d| d.as_i64()).collect())
        .unwrap_or_default();
    if days.is_empty() {
        (1..=7).collect()
    } else {
        days
    }
}

fn label(kind: &str, key: &str) -> String {
    match kind {
        "app" => format!("O app '{key}'"),
        "site" => format!("O site '{key}'"),
        _ => format!("O tipo do YouTube '{}'", crate::youtube::type_label(key)),
    }
}

pub fn find_conflicts(inp: &Inputs) -> Vec<Conflict> {
    let mut out: Vec<Conflict> = Vec::new();
    let mut push = |kind: &'static str, item_kind: &str, item: &str, groups: Vec<(&str, &str)>| {
        let mut ids: Vec<&str> = groups.iter().map(|g| g.0).collect();
        ids.sort();
        let mut names: Vec<String> = groups.iter().map(|g| g.1.to_string()).collect();
        names.sort();
        out.push(Conflict {
            kind,
            item: label(item_kind, item),
            groups: names,
            key: format!("{kind}|{item_kind}:{item}|{}", ids.join(",")),
        });
    };

    let rule_sets: Vec<(&RuleIn, BTreeSet<(&'static str, String)>, BTreeSet<i64>)> =
        inp.rules.iter().map(|r| (r, rule_items(r), rule_days(r))).collect();
    let wl_sets: Vec<(&WhitelistIn, BTreeSet<(&'static str, String)>)> =
        inp.whitelist.iter().map(|w| (w, items_of_json(&w.items))).collect();

    // whitelist x block (apps/sites only: YouTube types exempt by design)
    for (w, wi) in &wl_sets {
        for (r, ri, _) in &rule_sets {
            for it in wi.iter().filter(|i| i.0 != "yt") {
                if ri.contains(it) {
                    push("whitelist_block", it.0, &it.1, vec![(&w.id, &w.name), (&r.id, &r.name)]);
                }
            }
        }
    }
    // two whitelists
    let mut by_item: HashMap<&(&'static str, String), Vec<&WhitelistIn>> = HashMap::new();
    for (w, wi) in &wl_sets {
        for it in wi {
            by_item.entry(it).or_default().push(w);
        }
    }
    for (it, ws) in by_item {
        for i in 0..ws.len() {
            for j in i + 1..ws.len() {
                push("two_whitelists", it.0, &it.1, vec![(&ws[i].id, &ws[i].name), (&ws[j].id, &ws[j].name)]);
            }
        }
    }
    // two block groups with overlapping days
    for i in 0..rule_sets.len() {
        for j in i + 1..rule_sets.len() {
            let (a, ai, ad) = &rule_sets[i];
            let (b, bi, bd) = &rule_sets[j];
            if ad.is_disjoint(bd) {
                continue;
            }
            for it in ai.intersection(bi) {
                push("two_blocks", it.0, &it.1, vec![(&a.id, &a.name), (&b.id, &b.name)]);
            }
        }
    }
    // whitelisted YouTube type hidden by "Mostrar apenas"
    if let Some(show) = &inp.show_only {
        let show: BTreeSet<String> = show.iter().map(|s| s.trim().to_lowercase()).collect();
        for (w, wi) in &wl_sets {
            for it in wi.iter().filter(|i| i.0 == "yt") {
                if !show.contains(&it.1) {
                    push("show_only", it.0, &it.1, vec![(&w.id, &w.name)]);
                }
            }
        }
    }
    out.sort();
    out.dedup_by(|a, b| a.key == b.key);
    out
}

/// Refuses a change that introduces conflicts not present before.
pub fn check_new(before: &Inputs, after: &Inputs) -> Result<(), String> {
    let old: BTreeSet<String> = find_conflicts(before).into_iter().map(|c| c.key).collect();
    let new: Vec<Conflict> = find_conflicts(after).into_iter().filter(|c| !old.contains(&c.key)).collect();
    if new.is_empty() {
        return Ok(());
    }
    let msgs: Vec<String> = new.iter().take(3).map(|c| c.message()).collect();
    Err(format!("Conflito: {}", msgs.join(" ")))
}

/// Current rules/whitelists/show-only from the database.
pub fn load_current() -> Inputs {
    let rules = {
        let conn = crate::db::get_conn().lock();
        let mut out = Vec::new();
        if let Ok(mut st) = conn.prepare(
            "SELECT entity_id, display_name, COALESCE(target_type, 'APP'), COALESCE(pattern, ''), schedule_json FROM rules",
        ) {
            if let Ok(rows) = st.query_map([], |r| {
                Ok(RuleIn { id: r.get(0)?, name: r.get(1)?, target_type: r.get(2)?, pattern: r.get(3)?, schedule_json: r.get(4)? })
            }) {
                out.extend(rows.flatten());
            }
        }
        out
    };
    let whitelist = crate::db::get_all_whitelist_groups()
        .into_iter()
        .map(|g| WhitelistIn { id: g.group_id, name: g.display_name, items: g.items })
        .collect();
    let f = crate::db::get_focus_filters();
    Inputs { rules, whitelist, show_only: f.yt_show_only_enabled.then_some(f.yt_show_only_types) }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rule(id: &str, pattern: &str, days: &str) -> RuleIn {
        RuleIn {
            id: id.into(),
            name: id.into(),
            target_type: "GROUP".into(),
            pattern: pattern.into(),
            schedule_json: Some(format!(r#"{{"days":{days}}}"#)),
        }
    }
    fn wl(id: &str, items: &str) -> WhitelistIn {
        WhitelistIn { id: id.into(), name: id.into(), items: items.into() }
    }

    #[test]
    fn each_conflict_kind_and_the_youtube_exemption() {
        let yt_rule = rule("r1", r#"{"apps":[{"name":"Youtube","exec":"youtube"}],"sites":[]}"#, "[]");
        let exempt = wl("w1", r#"{"apps":[],"sites":[],"yt_types":[{"type":"educacional"}]}"#);
        let base = Inputs { rules: vec![yt_rule.clone()], whitelist: vec![exempt.clone()], show_only: None };
        assert!(find_conflicts(&base).is_empty(), "YouTube exemption is not a conflict");

        let mut i = base.clone();
        i.whitelist.push(wl("w2", r#"{"apps":[{"name":"Youtube","exec":"youtube"}],"sites":[]}"#));
        assert!(find_conflicts(&i).iter().any(|c| c.kind == "whitelist_block"));

        let mut i = base.clone();
        i.whitelist.push(wl("w2", r#"{"apps":[],"sites":[],"yt_types":[{"type":"educacional"}]}"#));
        assert!(find_conflicts(&i).iter().any(|c| c.kind == "two_whitelists"));

        let mut i = base.clone();
        i.rules.push(rule("r2", r#"{"apps":[{"name":"YouTube","exec":"/usr/bin/youtube"}],"sites":[]}"#, "[1,2]"));
        assert!(find_conflicts(&i).iter().any(|c| c.kind == "two_blocks"), "all days x mon/tue overlap");

        let mut i = Inputs::default();
        i.rules.push(rule("a", r#"{"apps":[],"sites":["https://www.reddit.com/"]}"#, "[1,2,3]"));
        i.rules.push(rule("b", r#"{"apps":[],"sites":["reddit.com"]}"#, "[6,7]"));
        assert!(find_conflicts(&i).is_empty(), "weekdays x weekend do not overlap");

        let mut i = base.clone();
        i.show_only = Some(vec!["musica".into()]);
        assert!(find_conflicts(&i).iter().any(|c| c.kind == "show_only"));
        i.show_only = Some(vec!["educacional".into(), "musica".into()]);
        assert!(find_conflicts(&i).is_empty());
    }

    #[test]
    fn only_new_conflicts_are_refused() {
        let r = rule("r1", r#"{"apps":[{"name":"Aether","exec":"aether"}],"sites":[]}"#, "[]");
        let w = wl("w1", r#"{"apps":[{"name":"Aether","exec":"aether"}],"sites":[]}"#);
        let before = Inputs { rules: vec![r.clone()], whitelist: vec![], show_only: None };
        let after = Inputs { rules: vec![r.clone()], whitelist: vec![w.clone()], show_only: None };
        let err = check_new(&before, &after).unwrap_err();
        assert!(err.contains("aether"), "{err}");
        // Existing conflict + a rename elsewhere: allowed.
        let mut renamed = after.clone();
        renamed.rules[0].name = "Novo nome".into();
        assert!(check_new(&after, &renamed).is_ok());
    }
}
