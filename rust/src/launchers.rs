//! Generic desktop launcher catalog & enforcement (`rust/src/launchers.rs`).
//!
//! Discovers installed games across Steam, Heroic (Epic/GOG/Amazon), Lutris,
//! Bottles, and XDG `.desktop` entries, enriches them via Steam API metadata,
//! blocks prohibited games/windows on screen, and optionally wraps native CEF/Electron
//! launcher `.desktop` entries + NSS DB so internal Store/Guides/Discussions/Artworks
//! route through `chronos_proxy` fail-open.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use parking_lot::Mutex;
use sysinfo::{ProcessesToUpdate, System};

use crate::{db, detector, engine, steam_api};

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct LauncherGameEntry {
    pub id: String,
    pub launcher: String,
    pub app_id: Option<i64>,
    pub title: String,
    pub exec_hint: String,
    pub install_dir: String,
    #[serde(default)]
    pub wine_prefix: String,
    pub tags: Vec<String>,
    pub genres: Vec<String>,
    pub categories: Vec<String>,
}

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct LauncherBlockEvent {
    pub title: String,
    pub launcher: String,
    pub reason: String,
    pub timestamp_utc: i64,
}

static GAME_CATALOG_CACHE: Mutex<Option<(i64, Vec<LauncherGameEntry>)>> = Mutex::new(None);
static LAST_ENFORCE_MS: Mutex<i64> = Mutex::new(0);
static LAST_BLOCK_EVENT: Mutex<Option<LauncherBlockEvent>> = Mutex::new(None);
static PENDING_LOOKUPS: Mutex<Option<HashSet<String>>> = Mutex::new(None);

fn now_utc() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

fn parse_vdf_kv_line(line: &str) -> Option<(String, String)> {
    let mut parts = Vec::new();
    let mut chars = line.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '"' {
            let mut val = String::new();
            while let Some(inner) = chars.next() {
                if inner == '\\' {
                    if let Some(esc) = chars.next() {
                        val.push(esc);
                    }
                } else if inner == '"' {
                    break;
                } else {
                    val.push(inner);
                }
            }
            parts.push(val);
            if parts.len() == 2 {
                return Some((parts[0].clone(), parts[1].clone()));
            }
        }
    }
    None
}

pub fn parse_steam_library_folders_vdf(content: &str) -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    for line in content.lines() {
        if let Some((k, v)) = parse_vdf_kv_line(line) {
            if k.eq_ignore_ascii_case("path") && !v.trim().is_empty() {
                dirs.push(PathBuf::from(v.trim()).join("steamapps"));
            }
        }
    }
    dirs
}

pub fn parse_steam_appmanifest_acf(content: &str) -> Option<LauncherGameEntry> {
    let mut app_id: Option<i64> = None;
    let mut name: Option<String> = None;
    let mut installdir: Option<String> = None;

    for line in content.lines() {
        if let Some((k, v)) = parse_vdf_kv_line(line) {
            match k.to_ascii_lowercase().as_str() {
                "appid" => app_id = v.trim().parse::<i64>().ok(),
                "name" => name = Some(v.trim().to_string()),
                "installdir" => installdir = Some(v.trim().to_string()),
                _ => {}
            }
        }
    }

    let id = app_id?;
    let title = name.filter(|s| !s.is_empty())?;
    let lower = title.to_lowercase();
    if lower.starts_with("proton ")
        || lower == "proton"
        || lower.starts_with("steam linux runtime")
        || lower.contains("steamworks common redistributables")
    {
        return None;
    }

    let inst = installdir.unwrap_or_default();
    Some(LauncherGameEntry {
        id: format!("steam:{id}"),
        launcher: "Steam".to_string(),
        app_id: Some(id),
        title,
        exec_hint: String::new(),
        install_dir: inst,
        wine_prefix: String::new(),
        tags: Vec::new(),
        genres: Vec::new(),
        categories: Vec::new(),
    })
}

fn scan_steam_roots(home: &Path, out: &mut Vec<LauncherGameEntry>) {
    let steam_roots = [
        home.join(".local/share/Steam/steamapps"),
        home.join(".steam/steam/steamapps"),
        home.join(".var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps"),
    ];

    let mut steamapps_dirs: Vec<PathBuf> = Vec::new();
    let mut seen_dirs = HashSet::new();

    for root in steam_roots {
        if root.exists() && seen_dirs.insert(root.clone()) {
            steamapps_dirs.push(root.clone());
        }
        let vdf_path = root.join("libraryfolders.vdf");
        if let Ok(text) = std::fs::read_to_string(&vdf_path) {
            for lib in parse_steam_library_folders_vdf(&text) {
                if lib.exists() && seen_dirs.insert(lib.clone()) {
                    steamapps_dirs.push(lib);
                }
            }
        }
    }

    for dir in steamapps_dirs {
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let p = entry.path();
            let fname = p.file_name().and_then(|s| s.to_str()).unwrap_or("");
            if fname.starts_with("appmanifest_") && fname.ends_with(".acf") {
                if let Ok(content) = std::fs::read_to_string(&p) {
                    if let Some(mut game) = parse_steam_appmanifest_acf(&content) {
                        if !game.install_dir.is_empty() {
                            game.install_dir = dir
                                .join("common")
                                .join(&game.install_dir)
                                .to_string_lossy()
                                .to_string();
                        }
                        out.push(game);
                    }
                }
            }
        }
    }
}

pub fn parse_heroic_installed_json(content: &str, store_label: &str) -> Vec<LauncherGameEntry> {
    let Ok(val) = serde_json::from_str::<serde_json::Value>(content) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    let push_obj = |obj: &serde_json::Map<String, serde_json::Value>, out: &mut Vec<LauncherGameEntry>| {
        let title = obj
            .get("title")
            .or_else(|| obj.get("app_title"))
            .or_else(|| obj.get("app_name"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        if title.is_empty() {
            return;
        }
        let app_key = obj
            .get("app_name")
            .or_else(|| obj.get("appName"))
            .or_else(|| obj.get("id"))
            .and_then(|v| v.as_str())
            .unwrap_or(&title)
            .to_string();
        let install_dir = obj
            .get("install_path")
            .or_else(|| obj.get("installPath"))
            .or_else(|| obj.get("folder_name"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        let exec_hint = obj
            .get("executable")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        let wine_prefix = obj
            .get("wine_prefix")
            .or_else(|| obj.get("winePrefix"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        out.push(LauncherGameEntry {
            id: format!("heroic:{store_label}:{app_key}"),
            launcher: format!("Heroic ({store_label})"),
            app_id: None,
            title,
            exec_hint,
            install_dir,
            wine_prefix,
            tags: Vec::new(),
            genres: Vec::new(),
            categories: Vec::new(),
        });
    };

    if let Some(arr) = val
        .get("installed")
        .or_else(|| val.get("games"))
        .and_then(|v| v.as_array())
        .or_else(|| val.as_array())
    {
        for item in arr {
            if let Some(obj) = item.as_object() {
                push_obj(obj, &mut out);
            }
        }
    } else if let Some(map) = val.as_object() {
        for (_, item) in map {
            if let Some(obj) = item.as_object() {
                push_obj(obj, &mut out);
            }
        }
    }
    out
}

fn scan_heroic_roots(home: &Path, out: &mut Vec<LauncherGameEntry>) {
    let heroic_roots = [
        home.join(".config/heroic"),
        home.join(".var/app/com.heroicgameslauncher.hgl/config/heroic"),
    ];
    for root in heroic_roots {
        let sources = [
            (root.join("legendaryConfig/legendary/installed.json"), "Epic"),
            (root.join("gog_store/installed.json"), "GOG"),
            (root.join("nile_config/nile/installed.json"), "Amazon"),
            (root.join("sideload_apps/library.json"), "Sideload"),
        ];
        for (path, label) in sources {
            if let Ok(txt) = std::fs::read_to_string(path) {
                out.extend(parse_heroic_installed_json(&txt, label));
            }
        }
    }
}

fn slug_to_fallback_title(slug_or_stem: &str) -> String {
    let mut base = slug_or_stem.trim();
    if let Some((head, tail)) = base.rsplit_once('-') {
        if tail.len() >= 5 && tail.chars().all(|c| c.is_ascii_digit()) {
            base = head;
        }
    }
    base.replace(['-', '_'], " ")
        .split_whitespace()
        .map(|w| {
            let mut chars = w.chars();
            match chars.next() {
                Some(first) => first.to_uppercase().to_string() + chars.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// Parses a Lutris (`games/*.yml`) or Bottles (`bottle.yml`) YAML config, preserving section nesting.
pub fn parse_simple_yaml_game(content: &str, launcher: &str, prefix_id: &str) -> Option<LauncherGameEntry> {
    let mut name: Option<String> = None;
    let mut game_slug: Option<String> = None;
    let mut runner: Option<String> = None;
    let mut exe: Option<String> = None;
    let mut dir: Option<String> = None;
    let mut wine_prefix: Option<String> = None;
    let mut app_id: Option<i64> = None;
    let mut section = String::new();
    let mut has_game_or_wine_section = false;

    for raw in content.lines() {
        let indent = raw.len() - raw.trim_start().len();
        let trimmed = raw.trim();
        if trimmed.starts_with('#') || trimmed.is_empty() {
            continue;
        }
        let Some((k, v)) = trimmed.split_once(':') else {
            continue;
        };
        let key = k.trim().to_ascii_lowercase();
        let val = v.trim().trim_matches('"').trim_matches('\'').to_string();

        if indent == 0 && (val.is_empty() || val == "{}") {
            section = key;
            if matches!(section.as_str(), "game" | "wine" | "system") {
                has_game_or_wine_section = true;
            }
            continue;
        }
        if indent == 0 {
            section.clear();
        }
        if val.is_empty() || val == "{}" || val == "[]" {
            continue;
        }

        if indent == 0 {
            if (key == "name" || key == "title") && name.is_none() {
                name = Some(val);
            } else if key == "game_slug" && game_slug.is_none() {
                game_slug = Some(val);
            } else if key == "slug" && game_slug.is_none() {
                game_slug = Some(val);
            } else if key == "runner" && runner.is_none() {
                runner = Some(val);
            }
        } else if section.is_empty() || section == "game" || section == "wine" || section == "bottle" {
            if (key == "exe" || key == "executable" || key == "main_file" || key == "path")
                && section != "wine"
                && exe.is_none()
            {
                exe = Some(val);
            } else if (key == "working_dir" || key == "directory") && dir.is_none() {
                dir = Some(val);
            } else if (key == "prefix" || key == "wine_prefix") && wine_prefix.is_none() {
                wine_prefix = Some(val);
            } else if (key == "appid" || key == "steamid") && app_id.is_none() {
                if let Ok(id) = val.parse::<i64>() {
                    if id > 0 && id < 2_000_000_000 {
                        app_id = Some(id);
                    }
                }
            }
        }
    }

    let title = if let Some(n) = name {
        n
    } else if launcher == "Lutris"
        && (exe.is_some() || runner.is_some() || has_game_or_wine_section)
        && !prefix_id.trim().is_empty()
        && !matches!(prefix_id.trim().to_ascii_lowercase().as_str(), "lutris" | "system")
    {
        let fallback = slug_to_fallback_title(game_slug.as_deref().unwrap_or(prefix_id));
        if fallback.is_empty() {
            return None;
        }
        fallback
    } else {
        return None;
    };

    let entry_id_slug = game_slug
        .as_deref()
        .filter(|s| !s.is_empty())
        .unwrap_or(prefix_id);
    let formatted_launcher = if launcher == "Lutris" {
        match runner.as_deref().filter(|r| !r.is_empty()) {
            Some(r) => format!("Lutris ({r})"),
            None => "Lutris".to_string(),
        }
    } else {
        launcher.to_string()
    };

    Some(LauncherGameEntry {
        id: format!("{launcher}:{entry_id_slug}"),
        launcher: formatted_launcher,
        app_id,
        title,
        exec_hint: exe.unwrap_or_default(),
        install_dir: dir.unwrap_or_default(),
        wine_prefix: wine_prefix.unwrap_or_default(),
        tags: Vec::new(),
        genres: Vec::new(),
        categories: Vec::new(),
    })
}

fn scan_lutris_pga_db(
    db_path: &Path,
    yml_by_stem: &HashMap<String, LauncherGameEntry>,
    consumed_stems: &mut HashSet<String>,
    out: &mut Vec<LauncherGameEntry>,
) {
    if !db_path.exists() {
        return;
    }
    let Ok(conn) = rusqlite::Connection::open_with_flags(
        db_path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    ) else {
        return;
    };

    let mut cols = HashSet::new();
    if let Ok(mut info_stmt) = conn.prepare("PRAGMA table_info(games)") {
        if let Ok(rows) = info_stmt.query_map([], |r| r.get::<_, String>(1)) {
            for col in rows.flatten() {
                cols.insert(col.to_ascii_lowercase());
            }
        }
    }
    if !cols.contains("name") {
        return;
    }

    let sel = |col: &str, fallback_sql: &str| -> String {
        if cols.contains(col) {
            format!("COALESCE(CAST({col} AS TEXT), '')")
        } else {
            fallback_sql.to_string()
        }
    };
    let where_clause = if cols.contains("installed") {
        "WHERE COALESCE(installed, 1) = 1"
    } else {
        ""
    };
    let sql = format!(
        "SELECT {}, name, {}, {}, {}, {}, {}, {}, {} FROM games {where_clause}",
        sel("slug", "''"),
        sel("executable", "''"),
        sel("directory", "''"),
        sel("runner", "''"),
        sel("configpath", "''"),
        sel("steamid", "''"),
        sel("service", "''"),
        sel("service_id", "''"),
    );

    let Ok(mut stmt) = conn.prepare(&sql) else {
        return;
    };
    let Ok(rows) = stmt.query_map([], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
            r.get::<_, String>(3)?,
            r.get::<_, String>(4)?,
            r.get::<_, String>(5)?,
            r.get::<_, String>(6)?,
            r.get::<_, String>(7)?,
            r.get::<_, String>(8)?,
        ))
    }) else {
        return;
    };

    for (slug, raw_title, mut exec_hint, mut install_dir, runner, configpath, steamid_s, service, service_id) in
        rows.flatten()
    {
        let title = raw_title.trim().to_string();
        if title.is_empty() {
            continue;
        }
        let stem = configpath
            .trim()
            .strip_suffix(".yml")
            .or_else(|| configpath.trim().strip_suffix(".yaml"))
            .unwrap_or(configpath.trim())
            .to_string();
        let mut wine_prefix = String::new();
        let mut app_id = steamid_s
            .trim()
            .parse::<i64>()
            .ok()
            .filter(|&id| id > 0 && id < 2_000_000_000)
            .or_else(|| {
                if service.trim().eq_ignore_ascii_case("steam") {
                    service_id
                        .trim()
                        .parse::<i64>()
                        .ok()
                        .filter(|&id| id > 0 && id < 2_000_000_000)
                } else {
                    None
                }
            });

        if !stem.is_empty() {
            if let Some(yml_entry) = yml_by_stem.get(&stem) {
                consumed_stems.insert(stem.clone());
                if exec_hint.trim().is_empty() {
                    exec_hint = yml_entry.exec_hint.clone();
                }
                if install_dir.trim().is_empty() {
                    install_dir = yml_entry.install_dir.clone();
                }
                if wine_prefix.is_empty() {
                    wine_prefix = yml_entry.wine_prefix.clone();
                }
                if app_id.is_none() {
                    app_id = yml_entry.app_id;
                }
            }
        }

        let slug_clean = if !slug.trim().is_empty() {
            slug.trim().to_string()
        } else if !stem.is_empty() {
            stem
        } else {
            steam_api::normalize_match_text(&title).replace(' ', "-")
        };

        out.push(LauncherGameEntry {
            id: format!("lutris:{slug_clean}"),
            launcher: if runner.trim().is_empty() {
                "Lutris".to_string()
            } else {
                format!("Lutris ({})", runner.trim())
            },
            app_id,
            title,
            exec_hint,
            install_dir,
            wine_prefix,
            tags: Vec::new(),
            genres: Vec::new(),
            categories: Vec::new(),
        });
    }
}

fn scan_lutris_and_bottles(home: &Path, out: &mut Vec<LauncherGameEntry>) {
    let mut yml_by_stem: HashMap<String, LauncherGameEntry> = HashMap::new();
    for lutris_yml_dir in [
        home.join(".config/lutris/games"),
        // Lutris >= 0.5.18 stores per-game YAML next to `pga.db`.
        home.join(".local/share/lutris/games"),
        home.join(".var/app/net.lutris.Lutris/config/lutris/games"),
        home.join(".var/app/net.lutris.Lutris/data/lutris/games"),
    ] {
        if let Ok(entries) = std::fs::read_dir(&lutris_yml_dir) {
            for entry in entries.flatten() {
                let p = entry.path();
                if matches!(p.extension().and_then(|s| s.to_str()), Some("yml" | "yaml")) {
                    if let Ok(txt) = std::fs::read_to_string(&p) {
                        let id = p.file_stem().and_then(|s| s.to_str()).unwrap_or("game");
                        if let Some(g) = parse_simple_yaml_game(&txt, "Lutris", id) {
                            yml_by_stem.entry(id.to_string()).or_insert(g);
                        }
                    }
                }
            }
        }
    }

    let mut consumed_stems: HashSet<String> = HashSet::new();
    for lutris_db in [
        home.join(".local/share/lutris/pga.db"),
        home.join(".var/app/net.lutris.Lutris/data/lutris/pga.db"),
    ] {
        scan_lutris_pga_db(&lutris_db, &yml_by_stem, &mut consumed_stems, out);
    }

    for (stem, g) in yml_by_stem {
        if !consumed_stems.contains(&stem) {
            out.push(g);
        }
    }

    for bottles_dir in [
        home.join(".local/share/bottles/bottles"),
        home.join(".var/app/com.usebottles.bottles/data/bottles/bottles"),
    ] {
        if let Ok(entries) = std::fs::read_dir(&bottles_dir) {
            for entry in entries.flatten() {
                let yml = entry.path().join("bottle.yml");
                if let Ok(txt) = std::fs::read_to_string(&yml) {
                    let id = entry.file_name().to_string_lossy().to_string();
                    if let Some(mut g) = parse_simple_yaml_game(&txt, "Bottles", &id) {
                        g.install_dir = entry.path().to_string_lossy().to_string();
                        g.wine_prefix = g.install_dir.clone();
                        out.push(g);
                    }
                }
            }
        }
    }
}

/// Config key holding the Lutris game ids Chronos itself moved into `.hidden`,
/// keyed by `pga.db` path, so un-blocking never un-hides games the user hid.
const LUTRIS_HIDDEN_BY_CHRONOS_KEY: &str = "lutris_hidden_by_chronos";
const LUTRIS_HIDDEN_CATEGORY: &str = ".hidden";

fn lutris_pga_db_paths(home: &Path) -> Vec<PathBuf> {
    vec![
        home.join(".local/share/lutris/pga.db"),
        home.join(".var/app/net.lutris.Lutris/data/lutris/pga.db"),
    ]
}

/// Reads `(id, name, steam_appid)` for every installed game in a Lutris `pga.db`.
fn read_lutris_games_for_hiding(conn: &rusqlite::Connection) -> Vec<(i64, String, Option<i64>)> {
    let mut cols = HashSet::new();
    if let Ok(mut st) = conn.prepare("PRAGMA table_info(games)") {
        if let Ok(rows) = st.query_map([], |r| r.get::<_, String>(1)) {
            cols.extend(rows.flatten().map(|c| c.to_ascii_lowercase()));
        }
    }
    if !cols.contains("id") || !cols.contains("name") {
        return Vec::new();
    }
    let col = |c: &str| {
        if cols.contains(c) {
            format!("COALESCE(CAST({c} AS TEXT), '')")
        } else {
            "''".to_string()
        }
    };
    let sql = format!(
        "SELECT id, COALESCE(name, ''), {}, {}, {} FROM games",
        col("service"),
        col("service_id"),
        col("steamid")
    );
    let Ok(mut st) = conn.prepare(&sql) else {
        return Vec::new();
    };
    let Ok(rows) = st.query_map([], |r| {
        Ok((
            r.get::<_, i64>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
            r.get::<_, String>(3)?,
            r.get::<_, String>(4)?,
        ))
    }) else {
        return Vec::new();
    };
    let valid = |raw: &str| raw.trim().parse::<i64>().ok().filter(|&n| n > 0 && n < 2_000_000_000);
    rows.flatten()
        .filter(|(_, name, ..)| !name.trim().is_empty())
        .map(|(id, name, service, service_id, steamid)| {
            let app_id = valid(&steamid).or_else(|| {
                service
                    .trim()
                    .eq_ignore_ascii_case("steam")
                    .then(|| valid(&service_id))
                    .flatten()
            });
            (id, name.trim().to_string(), app_id)
        })
        .collect()
}

fn ensure_lutris_category(conn: &rusqlite::Connection, name: &str) -> Option<i64> {
    let existing: Option<i64> = conn
        .query_row("SELECT id FROM categories WHERE name = ?1", [name], |r| r.get(0))
        .ok();
    if existing.is_some() {
        return existing;
    }
    conn.execute("INSERT INTO categories (name) VALUES (?1)", [name]).ok()?;
    Some(conn.last_insert_rowid())
}

/// Moves Lutris games whose title/tags match the active launcher filters into Lutris'
/// native `.hidden` category (hidden from the library and local search), and restores
/// only the games Chronos hid itself once they stop matching. Returns how many games
/// changed state. Lutris re-reads categories when its view refreshes or restarts.
pub fn sync_lutris_hidden_games_in_home(home: &Path) -> usize {
    let filters = db::get_focus_filters();
    let rules_active = filters.launcher_filter_enabled
        && (!filters.launcher_blocked_tags.is_empty() || !filters.launcher_blocked_names.is_empty());

    let mut ledger: HashMap<String, Vec<i64>> = db::get_config(LUTRIS_HIDDEN_BY_CHRONOS_KEY)
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default();
    let mut changed = 0usize;

    for db_path in lutris_pga_db_paths(home) {
        let key = db_path.to_string_lossy().to_string();
        let previously_hidden: HashSet<i64> = ledger.get(&key).cloned().unwrap_or_default().into_iter().collect();
        if !db_path.exists() {
            if !previously_hidden.is_empty() {
                ledger.remove(&key);
            }
            continue;
        }
        let Ok(conn) = rusqlite::Connection::open(&db_path) else {
            continue;
        };
        let _ = conn.busy_timeout(std::time::Duration::from_secs(2));
        let has_tables: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('categories','games_categories')",
                [],
                |r| r.get(0),
            )
            .unwrap_or(0);
        if has_tables < 2 {
            continue;
        }

        let mut should_hide: HashSet<i64> = HashSet::new();
        if rules_active {
            for (game_id, title, app_id) in read_lutris_games_for_hiding(&conn) {
                let meta = steam_api::lookup_cached_only(app_id, &title);
                if meta.as_ref().map_or(true, steam_api::is_dom_learned_only)
                    && !steam_api::is_generic_storefront_title(&title)
                {
                    trigger_async_metadata_prefetch(app_id, &title);
                }
                if steam_api::match_game_against_filters(&title, &[], meta.as_ref(), &filters).is_some() {
                    should_hide.insert(game_id);
                }
            }
        }

        let Some(cat_id) = (if should_hide.is_empty() && previously_hidden.is_empty() {
            None
        } else {
            ensure_lutris_category(&conn, LUTRIS_HIDDEN_CATEGORY)
        }) else {
            ledger.remove(&key);
            continue;
        };

        let already_in_hidden: HashSet<i64> = conn
            .prepare("SELECT game_id FROM games_categories WHERE category_id = ?1")
            .and_then(|mut st| {
                st.query_map([cat_id], |r| r.get::<_, i64>(0))
                    .map(|rows| rows.flatten().collect())
            })
            .unwrap_or_default();

        let mut owned: HashSet<i64> = previously_hidden.clone();
        for &gid in &should_hide {
            if already_in_hidden.contains(&gid) {
                // Hidden by the user (or already by us): never take ownership of user choices.
                continue;
            }
            if conn
                .execute(
                    "INSERT INTO games_categories (game_id, category_id) VALUES (?1, ?2)",
                    [gid, cat_id],
                )
                .is_ok()
            {
                owned.insert(gid);
                changed += 1;
            }
        }
        for gid in previously_hidden.difference(&should_hide) {
            if conn
                .execute(
                    "DELETE FROM games_categories WHERE game_id = ?1 AND category_id = ?2",
                    [*gid, cat_id],
                )
                .is_ok()
            {
                owned.remove(gid);
                changed += 1;
            }
        }

        if owned.is_empty() {
            ledger.remove(&key);
        } else {
            let mut v: Vec<i64> = owned.into_iter().collect();
            v.sort_unstable();
            ledger.insert(key, v);
        }
    }

    if let Ok(raw) = serde_json::to_string(&ledger) {
        let _ = db::set_config(LUTRIS_HIDDEN_BY_CHRONOS_KEY, &raw);
    }
    changed + sync_lutris_service_games_in_home(home, &filters, rules_active)
}

/// Config key holding full `service_games` rows Chronos removed, keyed by `pga.db` path,
/// so they can be restored verbatim when the game stops matching the filters.
const LUTRIS_SERVICE_GAMES_REMOVED_KEY: &str = "lutris_service_games_removed_by_chronos";
const LUTRIS_SERVICE_GAME_COLS: [&str; 9] =
    ["service", "appid", "name", "slug", "icon", "logo", "url", "details", "lutris_slug"];

/// Lutris' service views (e.g. "Steam") list the cached store library from
/// `service_games`, which ignores the `.hidden` category. Blocked titles are removed
/// from that cache (Lutris rebuilds it from the store library; the periodic sync
/// removes them again) and reinserted once they no longer match the filters.
fn sync_lutris_service_games_in_home(home: &Path, filters: &db::FocusFilters, rules_active: bool) -> usize {
    let mut ledger: HashMap<String, Vec<HashMap<String, String>>> =
        db::get_config(LUTRIS_SERVICE_GAMES_REMOVED_KEY)
            .and_then(|raw| serde_json::from_str(&raw).ok())
            .unwrap_or_default();
    let mut changed = 0usize;

    for db_path in lutris_pga_db_paths(home) {
        let key = db_path.to_string_lossy().to_string();
        if !db_path.exists() {
            continue;
        }
        let Ok(conn) = rusqlite::Connection::open(&db_path) else {
            continue;
        };
        let _ = conn.busy_timeout(std::time::Duration::from_secs(2));
        let mut cols = HashSet::new();
        if let Ok(mut st) = conn.prepare("PRAGMA table_info(service_games)") {
            if let Ok(rows) = st.query_map([], |r| r.get::<_, String>(1)) {
                cols.extend(rows.flatten().map(|c| c.to_ascii_lowercase()));
            }
        }
        if !cols.contains("appid") || !cols.contains("name") || !cols.contains("service") {
            continue;
        }
        let present_cols: Vec<&str> = LUTRIS_SERVICE_GAME_COLS
            .iter()
            .copied()
            .filter(|c| cols.contains(*c))
            .collect();
        let select = format!(
            "SELECT id, {} FROM service_games",
            present_cols
                .iter()
                .map(|c| format!("COALESCE(CAST({c} AS TEXT), '')"))
                .collect::<Vec<_>>()
                .join(", ")
        );

        let rows: Vec<(i64, HashMap<String, String>)> = conn
            .prepare(&select)
            .and_then(|mut st| {
                st.query_map([], |r| {
                    let mut m = HashMap::new();
                    for (i, c) in present_cols.iter().enumerate() {
                        m.insert(c.to_string(), r.get::<_, String>(i + 1)?);
                    }
                    Ok((r.get::<_, i64>(0)?, m))
                })
                .map(|it| it.flatten().collect())
            })
            .unwrap_or_default();

        let is_blocked = |row: &HashMap<String, String>| -> bool {
            if !rules_active {
                return false;
            }
            let title = row.get("name").map(|s| s.trim()).unwrap_or("");
            if title.is_empty() {
                return false;
            }
            let app_id = row
                .get("service")
                .filter(|s| s.trim().eq_ignore_ascii_case("steam"))
                .and_then(|_| row.get("appid"))
                .and_then(|a| a.trim().parse::<i64>().ok())
                .filter(|&n| n > 0);
            let meta = steam_api::lookup_cached_only(app_id, title);
            if meta.as_ref().map_or(true, steam_api::is_dom_learned_only)
                && !steam_api::is_generic_storefront_title(title)
            {
                trigger_async_metadata_prefetch(app_id, title);
            }
            steam_api::match_game_against_filters(title, &[], meta.as_ref(), filters).is_some()
        };
        let row_key = |r: &HashMap<String, String>| {
            format!(
                "{}:{}",
                r.get("service").map(|s| s.to_ascii_lowercase()).unwrap_or_default(),
                r.get("appid").cloned().unwrap_or_default()
            )
        };

        let mut removed = ledger.remove(&key).unwrap_or_default();
        let present_keys: HashSet<String> = rows.iter().map(|(_, r)| row_key(r)).collect();

        // Remove newly blocked rows (keeping a verbatim copy for restoration)
        for (id, row) in &rows {
            if is_blocked(row)
                && conn.execute("DELETE FROM service_games WHERE id = ?1", [id]).is_ok()
            {
                if !removed.iter().any(|r| row_key(r) == row_key(row)) {
                    removed.push(row.clone());
                }
                changed += 1;
            }
        }

        // Restore rows that are no longer blocked
        let mut still_removed = Vec::new();
        for row in removed {
            if is_blocked(&row) {
                still_removed.push(row);
                continue;
            }
            if present_keys.contains(&row_key(&row)) {
                continue; // Lutris already re-synced it from the store library
            }
            let row_cols: Vec<&str> = present_cols.iter().copied().filter(|c| row.contains_key(*c)).collect();
            let sql = format!(
                "INSERT INTO service_games ({}) VALUES ({})",
                row_cols.join(", "),
                (1..=row_cols.len()).map(|i| format!("?{i}")).collect::<Vec<_>>().join(", ")
            );
            let vals: Vec<&String> = row_cols.iter().filter_map(|c| row.get(*c)).collect();
            if conn.execute(&sql, rusqlite::params_from_iter(vals)).is_ok() {
                changed += 1;
            } else {
                still_removed.push(row);
            }
        }
        if !still_removed.is_empty() {
            ledger.insert(key, still_removed);
        }
    }

    if let Ok(raw) = serde_json::to_string(&ledger) {
        let _ = db::set_config(LUTRIS_SERVICE_GAMES_REMOVED_KEY, &raw);
    }
    changed
}

pub fn sync_lutris_hidden_games() -> usize {
    if !crate::profile::allows_system_integrations() {
        return 0;
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    sync_lutris_hidden_games_in_home(Path::new(&home))
}

pub fn discover_installed_games_in_home(home: &Path) -> Vec<LauncherGameEntry> {
    let mut raw = Vec::new();
    scan_steam_roots(home, &mut raw);
    scan_heroic_roots(home, &mut raw);
    scan_lutris_and_bottles(home, &mut raw);

    // Desktop `.desktop` Games fallback (only include games categorized as Jogos)
    for app in engine::list_installed_desktop_apps() {
        if app.icon_name.split(',').any(|t| t.trim() == "Jogos") {
            let lower_exec = app.exec.to_lowercase();
            // Skip pure launcher clients themselves unless treated as launcher entries elsewhere
            if matches!(lower_exec.as_str(), "steam" | "heroic" | "lutris" | "bottles") {
                continue;
            }
            raw.push(LauncherGameEntry {
                id: format!("desktop:{}", app.id),
                launcher: "Desktop".to_string(),
                app_id: None,
                title: app.name,
                exec_hint: app.exec,
                install_dir: String::new(),
                wine_prefix: String::new(),
                tags: Vec::new(),
                genres: Vec::new(),
                categories: Vec::new(),
            });
        }
    }

    let mut dedup: HashMap<String, LauncherGameEntry> = HashMap::new();
    for mut g in raw {
        let key = if let Some(id) = g.app_id {
            format!("appid:{id}")
        } else {
            format!("title:{}", steam_api::normalize_match_text(&g.title))
        };
        if let Some(meta) = steam_api::lookup_cached_only(g.app_id, &g.title) {
            g.tags = meta.tags;
            g.genres = meta.genres;
            g.categories = meta.categories;
            if g.app_id.is_none() {
                g.app_id = meta.app_id;
            }
        }
        dedup
            .entry(key)
            .and_modify(|existing| {
                if existing.exec_hint.is_empty() && !g.exec_hint.is_empty() {
                    existing.exec_hint = g.exec_hint.clone();
                }
                if existing.install_dir.is_empty() && !g.install_dir.is_empty() {
                    existing.install_dir = g.install_dir.clone();
                }
                if existing.wine_prefix.is_empty() && !g.wine_prefix.is_empty() {
                    existing.wine_prefix = g.wine_prefix.clone();
                }
                if existing.app_id.is_none() {
                    existing.app_id = g.app_id;
                }
            })
            .or_insert(g);
    }

    let mut list: Vec<LauncherGameEntry> = dedup.into_values().collect();
    list.sort_by(|a, b| a.title.to_lowercase().cmp(&b.title.to_lowercase()));
    list
}

pub fn discover_installed_games(enrich_via_steam: bool) -> Vec<LauncherGameEntry> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let mut list = discover_installed_games_in_home(Path::new(&home));

    if enrich_via_steam {
        let missing_ids: Vec<i64> = list
            .iter()
            .filter_map(|g| {
                if g.tags.is_empty() && g.genres.is_empty() {
                    g.app_id
                } else {
                    None
                }
            })
            .take(40)
            .collect();
        if !missing_ids.is_empty() {
            let fetched = steam_api::run_async_blocking(async move {
                steam_api::fetch_batch_by_appids_async(&missing_ids).await
            });
            for g in &mut list {
                if let Some(id) = g.app_id {
                    if let Some(meta) = fetched.get(&id) {
                        g.tags = meta.tags.clone();
                        g.genres = meta.genres.clone();
                        g.categories = meta.categories.clone();
                    }
                }
            }
        }
        // Resolve a batch of non-Steam titles (Epic/GOG/Lutris/Itch) via the multi-provider cascade.
        for g in list.iter_mut().filter(|g| g.app_id.is_none() && g.tags.is_empty()).take(16) {
            if let Some(meta) = steam_api::resolve_game_metadata_blocking(None, &g.title) {
                g.app_id = meta.app_id;
                g.tags = meta.tags;
                g.genres = meta.genres;
                g.categories = meta.categories;
            }
        }
    }

    *GAME_CATALOG_CACHE.lock() = Some((now_utc(), list.clone()));
    list
}

fn cached_catalog() -> Vec<LauncherGameEntry> {
    let now = now_utc();
    {
        let cache = GAME_CATALOG_CACHE.lock();
        if let Some((ts, ref list)) = *cache {
            if (now - ts) < 60 {
                return list.clone();
            }
        }
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let list = discover_installed_games_in_home(Path::new(&home));
    *GAME_CATALOG_CACHE.lock() = Some((now, list.clone()));
    list
}

pub fn clean_launcher_window_title(raw_title: &str) -> String {
    let mut t = raw_title.trim().to_string();
    for suffix in [" - Steam", " — Heroic", " - Heroic Games Launcher", " - Lutris", " - Bottles"] {
        if let Some(stripped) = t.strip_suffix(suffix) {
            t = stripped.trim().to_string();
        }
    }
    for prefix in [
        "Steam Community :: Guide :: ",
        "Comunidade Steam :: Guia :: ",
        "Steam Community :: Discussions :: ",
        "Comunidade Steam :: Discussões :: ",
        "Steam Community :: Artwork :: ",
        "Comunidade Steam :: Arte :: ",
        "Steam Community :: ",
        "Comunidade Steam :: ",
        "Guides :: ",
        "Guias :: ",
        "Discussions :: ",
        "Discussões :: ",
        "Artwork :: ",
        "Arte :: ",
        "Workshop :: ",
        "Oficina :: ",
    ] {
        if let Some(idx) = t.to_lowercase().find(&prefix.to_lowercase()) {
            if idx == 0 {
                t = t[prefix.len()..].trim().to_string();
            }
        }
    }
    t
}

pub fn extract_appid_from_cmd(cmd_args: &[String]) -> Option<i64> {
    for arg in cmd_args {
        let lower = arg.to_ascii_lowercase();
        for key in ["steamappid=", "appid="] {
            if let Some(pos) = lower.find(key) {
                let digits: String = lower[pos + key.len()..]
                    .chars()
                    .take_while(|c| c.is_ascii_digit())
                    .collect();
                if let Ok(id) = digits.parse::<i64>() {
                    if id > 0 {
                        return Some(id);
                    }
                }
            }
        }
    }
    None
}

fn trigger_async_metadata_prefetch(app_id: Option<i64>, title: &str) {
    let key = if let Some(id) = app_id {
        format!("appid:{id}")
    } else {
        format!("title:{}", steam_api::normalize_match_text(title))
    };
    {
        let mut guard = PENDING_LOOKUPS.lock();
        let set = guard.get_or_insert_with(HashSet::new);
        if set.len() > 200 || !set.insert(key) {
            return;
        }
    }
    let title_owned = title.to_string();
    std::thread::spawn(move || {
        let _ = steam_api::resolve_game_metadata_blocking(app_id, &title_owned);
    });
}

fn is_launcher_host_window(w: &detector::WindowInfo) -> bool {
    let c = w.class.to_lowercase();
    let ic = w.initial_class.to_lowercase();
    matches!(
        c.as_str(),
        "steam"
            | "steamwebhelper"
            | "heroic"
            | "com.heroicgameslauncher.hgl"
            | "lutris"
            | "net.lutris.lutris"
            | "bottles"
            | "itch"
    ) || matches!(
        ic.as_str(),
        "steam"
            | "steamwebhelper"
            | "heroic"
            | "com.heroicgameslauncher.hgl"
            | "lutris"
            | "net.lutris.lutris"
            | "bottles"
            | "itch"
    ) || c.contains("steam_app_")
}

fn is_pure_launcher_binary(proc_name: &str, cmd_joined_lower: &str) -> bool {
    let lower = proc_name.trim().to_lowercase();
    detector::is_lutris_client_process(&lower, cmd_joined_lower)
        || matches!(
            lower.as_str(),
            "steam"
                | "steamwebhelper"
                | "heroic"
                | "com.heroicgameslauncher.hgl"
                | "lutris"
                | "net.lutris.lutris"
                | "bottles"
                | "itch"
                | "bwrap"
                | "zypak-sandbox"
                | "zypak-helper"
                | "xdg-dbus-proxy"
                | "chronos_app"
                | "chronos_proxy"
        )
}

fn normalize_prefix_path(raw: &str) -> String {
    raw.trim()
        .replace('\\', "/")
        .trim_end_matches('/')
        .to_lowercase()
}

pub fn match_running_process_to_catalog(
    catalog: &[LauncherGameEntry],
    by_appid: &HashMap<i64, &LauncherGameEntry>,
    pname: &str,
    exe_str: &str,
    cmds: &[String],
    cmd_joined_lower: &str,
    env: &HashMap<String, String>,
) -> Option<(Option<i64>, String, String)> {
    if is_pure_launcher_binary(pname, cmd_joined_lower) {
        return None;
    }

    if let Some(appid) = extract_appid_from_cmd(cmds)
        .or_else(|| detector::extract_steam_appid_from_env(env))
    {
        if let Some(g) = by_appid.get(&appid) {
            return Some((Some(appid), g.title.clone(), g.launcher.clone()));
        }
        return Some((Some(appid), pname.to_string(), "Steam".to_string()));
    }

    let exe_norm = exe_str.replace('\\', "/");
    let cmd_norm = cmd_joined_lower.replace('\\', "/");

    if let Some(umu_id) = env
        .get("UMU_ID")
        .or_else(|| env.get("LUTRIS_GAME_UUID"))
        .or_else(|| env.get("LUTRIS_GAME_ID"))
    {
        let u_low = umu_id.trim().to_lowercase();
        let slug_candidate = u_low.strip_prefix("umu-").unwrap_or(&u_low);
        if !slug_candidate.is_empty() {
            if let Some(g) = catalog.iter().find(|g| {
                let id_slug = g
                    .id
                    .strip_prefix("lutris:")
                    .or_else(|| g.id.strip_prefix("Lutris:"))
                    .unwrap_or(&g.id)
                    .to_lowercase();
                id_slug == slug_candidate
            }) {
                return Some((g.app_id, g.title.clone(), g.launcher.clone()));
            }
        }
    }

    if let Some(g) = catalog.iter().find(|g| {
        let dir_l = g.install_dir.to_lowercase().replace('\\', "/");
        (!dir_l.is_empty() && dir_l.len() >= 6 && (exe_norm.contains(&dir_l) || cmd_norm.contains(&dir_l)))
            || detector::exec_matches_process(&g.exec_hint, pname, exe_str, cmd_joined_lower)
    }) {
        return Some((g.app_id, g.title.clone(), g.launcher.clone()));
    }

    if let Some(prefix_val) = env.get("WINEPREFIX") {
        let env_prefix = normalize_prefix_path(prefix_val);
        if !env_prefix.is_empty() && env_prefix.len() >= 8 && !env_prefix.ends_with("/.wine") {
            if let Some(g) = catalog.iter().find(|g| {
                let gp = normalize_prefix_path(&g.wine_prefix);
                !gp.is_empty() && gp.len() >= 8 && !gp.ends_with("/.wine") && gp == env_prefix
            }) {
                return Some((g.app_id, g.title.clone(), g.launcher.clone()));
            }
        }
    }

    None
}

pub fn last_block_event() -> Option<LauncherBlockEvent> {
    LAST_BLOCK_EVENT.lock().clone()
}

/// Reseta o throttle e caches pendentes para reavaliar imediatamente após atualização de filtros.
pub fn invalidate_launcher_caches() {
    *LAST_ENFORCE_MS.lock() = 0;
    *LAST_BLOCK_EVENT.lock() = None;
    if let Some(set) = PENDING_LOOKUPS.lock().as_mut() {
        set.clear();
    }
}

/// Checks running game processes and open launcher/game windows against active tag/name filters.
/// Terminates offending game processes / closes offending launcher subwindows safely.
pub fn detect_and_enforce_launcher_filters() -> Option<LauncherBlockEvent> {
    detect_and_enforce_launcher_filters_with_options(false)
}

pub fn detect_and_enforce_launcher_filters_with_options(force: bool) -> Option<LauncherBlockEvent> {
    let filters = db::get_focus_filters();
    if !filters.launcher_filter_enabled
        || (filters.launcher_blocked_tags.is_empty() && filters.launcher_blocked_names.is_empty())
    {
        *LAST_BLOCK_EVENT.lock() = None;
        return None;
    }

    let now_m = now_ms();
    {
        let mut last = LAST_ENFORCE_MS.lock();
        if !force && (now_m - *last) < 1800 {
            return LAST_BLOCK_EVENT.lock().clone();
        }
        *last = now_m;
    }

    let catalog = cached_catalog();
    let by_appid: HashMap<i64, &LauncherGameEntry> = catalog
        .iter()
        .filter_map(|g| g.app_id.map(|id| (id, g)))
        .collect();

    let mut blocked_event: Option<LauncherBlockEvent> = None;

    // 1. Inspect running processes for SteamAppId/UMU_ID/WINEPREFIX or matching install_dir/exec
    let mut sys = System::new();
    sys.refresh_processes(ProcessesToUpdate::All, true);
    for process in sys.processes().values() {
        let pname = process.name().to_string_lossy().to_string();
        let cmds: Vec<String> = process
            .cmd()
            .iter()
            .map(|s| s.to_string_lossy().to_string())
            .collect();
        let exe_str = process
            .exe()
            .map(|p| p.to_string_lossy().to_lowercase())
            .unwrap_or_default();
        let cmd_joined = cmds.join(" ").to_lowercase();
        if is_pure_launcher_binary(&pname, &cmd_joined) {
            continue;
        }
        let env = detector::read_process_environ_map(process.pid().as_u32());

        let matched_entry = match_running_process_to_catalog(
            &catalog,
            &by_appid,
            &pname,
            &exe_str,
            &cmds,
            &cmd_joined,
            &env,
        );

        if let Some((app_id, title, launcher)) = matched_entry {
            let cached_meta = steam_api::lookup_cached_only(app_id, &title);
            if cached_meta.as_ref().map_or(true, steam_api::is_dom_learned_only) {
                trigger_async_metadata_prefetch(app_id, &title);
            }
            if let Some((kind, term)) =
                steam_api::match_game_against_filters(&title, &[], cached_meta.as_ref(), &filters)
            {
                let killed = process.kill();
                eprintln!(
                    "chronos launcher block: killed={killed} pid={} name={pname} title={title} reason={kind}:{term}",
                    process.pid()
                );
                blocked_event = Some(LauncherBlockEvent {
                    title,
                    launcher,
                    reason: format!("{kind}: {term}"),
                    timestamp_utc: now_utc(),
                });
            }
        }
    }

    // 2. Inspect non-browser windows and launcher/game subwindows currently open on screen
    let windows = detector::ActivityDetector::get_all_windows_info();
    for w in &windows {
        if w.is_browser() || w.class.contains("chronos") || w.title.trim().is_empty() {
            continue;
        }
        let cleaned = clean_launcher_window_title(&w.title);
        if cleaned.is_empty()
            || cleaned.eq_ignore_ascii_case("steam")
            || cleaned.eq_ignore_ascii_case("heroic games launcher")
            || cleaned.eq_ignore_ascii_case("heroic")
            || cleaned.eq_ignore_ascii_case("com.heroicgameslauncher.hgl")
            || cleaned.eq_ignore_ascii_case("lutris")
            || cleaned.eq_ignore_ascii_case("net.lutris.lutris")
            || cleaned.eq_ignore_ascii_case("bottles")
        {
            continue;
        }

        // Check Steam Proton/game class `steam_app_<id>`
        let win_appid = w
            .class
            .strip_prefix("steam_app_")
            .or_else(|| w.initial_class.strip_prefix("steam_app_"))
            .and_then(|s| s.parse::<i64>().ok());

        let catalog_hit = win_appid
            .and_then(|id| by_appid.get(&id).copied())
            .or_else(|| {
                let c_norm = steam_api::normalize_match_text(&cleaned);
                catalog.iter().find(|g| {
                    let g_norm = steam_api::normalize_match_text(&g.title);
                    !g_norm.is_empty() && c_norm.contains(&g_norm)
                })
            });

        let effective_title = catalog_hit
            .map(|g| g.title.as_str())
            .unwrap_or(cleaned.as_str());
        let effective_appid = win_appid.or_else(|| catalog_hit.and_then(|g| g.app_id));
        let cached_meta = steam_api::lookup_cached_only(effective_appid, effective_title);

        if (is_launcher_host_window(w) || catalog_hit.is_some())
            && cached_meta.as_ref().map_or(true, steam_api::is_dom_learned_only)
            && !steam_api::is_generic_storefront_title(effective_title)
        {
            trigger_async_metadata_prefetch(effective_appid, effective_title);
        }

        if let Some((kind, term)) = steam_api::match_game_against_filters(
            effective_title,
            &[],
            cached_meta.as_ref(),
            &filters,
        ) {
            eprintln!(
                "chronos launcher block: window title={} class={} pid={} reason={kind}:{term}",
                w.title, w.class, w.pid
            );
            if !w.address.is_empty() {
                let _ = Command::new("hyprctl")
                    .args(["dispatch", "closewindow", &format!("address:{}", w.address)])
                    .output();
            } else {
                detector::ActivityDetector::close_window_by_title(&w.title);
            }
            if w.pid > 0 && !is_launcher_host_window(w) {
                let _ = Command::new("kill").args(["-15", &w.pid.to_string()]).output();
            }
            blocked_event = Some(LauncherBlockEvent {
                title: effective_title.to_string(),
                launcher: catalog_hit
                    .map(|g| g.launcher.clone())
                    .unwrap_or_else(|| "Launcher".to_string()),
                reason: format!("{kind}: {term}"),
                timestamp_utc: now_utc(),
            });
        }
    }

    if let Some(ref ev) = blocked_event {
        *LAST_BLOCK_EVENT.lock() = Some(ev.clone());
        let _ = Command::new("notify-send")
            .args([
                "-a",
                "Chronos Focus",
                "-u",
                "critical",
                "Conteúdo Bloqueado no Launcher",
                &format!("{} bloqueado ({})", ev.title, ev.reason),
            ])
            .output();
    }

    blocked_event
}

fn find_proxy_ca_cert(home: &Path) -> Option<PathBuf> {
    let candidates = [
        home.join(".local/share/chronos/ca/chronos-proxy-ca.crt"),
        PathBuf::from("/usr/local/share/chronos/chronos-proxy-ca.crt"),
        PathBuf::from("/etc/ca-certificates/trust-source/anchors/chronos-proxy-ca.crt"),
        PathBuf::from("/usr/local/share/ca-certificates/chronos-proxy-ca.crt"),
        home.join(".local/share/chronos/ca/chronos-ca.crt"),
    ];
    candidates.into_iter().find(|p| p.exists())
}

fn build_combined_ca_bundle(home: &Path, ca_cert: &Path) -> Option<PathBuf> {
    let ca_pem = std::fs::read_to_string(ca_cert).ok()?;
    if !ca_pem.contains("BEGIN CERTIFICATE") {
        return None;
    }

    let mut combined = String::with_capacity(ca_pem.len() + 256 * 1024);
    for sys_bundle in [
        "/etc/ssl/certs/ca-certificates.crt",
        "/etc/pki/tls/certs/ca-bundle.crt",
        "/etc/ssl/cert.pem",
    ] {
        if let Ok(sys_pem) = std::fs::read_to_string(sys_bundle) {
            if !sys_pem.is_empty() {
                combined.push_str(&sys_pem);
                if !combined.ends_with('\n') {
                    combined.push('\n');
                }
                break;
            }
        }
    }
    if !combined.contains(ca_pem.trim()) {
        combined.push_str("\n# Chronos Local Focus CA\n");
        combined.push_str(&ca_pem);
        if !combined.ends_with('\n') {
            combined.push('\n');
        }
    }

    let ca_dir = home.join(".local/share/chronos/ca");
    let _ = std::fs::create_dir_all(&ca_dir);
    let out_path = ca_dir.join("chronos-combined-ca-bundle.crt");
    if std::fs::write(&out_path, combined).is_ok() {
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = std::fs::set_permissions(&out_path, std::fs::Permissions::from_mode(0o644));
        }
        Some(out_path)
    } else {
        None
    }
}

fn find_steamrt_libnss3(home: &Path) -> Option<PathBuf> {
    let pv_roots = [
        home.join(".local/share/Steam/steamrt64/pv-runtime/steam-runtime-steamrt"),
        home.join(".steam/steam/steamrt64/pv-runtime/steam-runtime-steamrt"),
        home.join(".steam/debian-installation/steamrt64/pv-runtime/steam-runtime-steamrt"),
    ];
    let mut candidates: Vec<(String, PathBuf)> = Vec::new();
    for root in pv_roots {
        let Ok(entries) = std::fs::read_dir(&root) else {
            continue;
        };
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if !name.starts_with("steamrt") {
                continue;
            }
            let lib_dir = entry.path().join("files/lib/x86_64-linux-gnu");
            let libnss = lib_dir.join("libnss3.so");
            let libsoftokn = lib_dir.join("nss/libsoftokn3.so");
            if libnss.exists() && libsoftokn.exists() {
                candidates.push((name, libnss));
            }
        }
    }
    candidates.sort_by(|a, b| b.0.cmp(&a.0));
    candidates.into_iter().map(|(_, p)| p).next()
}

fn pem_to_der_bytes(ca_cert: &Path) -> Option<Vec<u8>> {
    let pem = std::fs::read(ca_cert).ok()?;
    let x509 = openssl::x509::X509::from_pem(&pem).ok()?;
    x509.to_der().ok()
}

#[cfg(unix)]
mod nss_ffi {
    use std::ffi::{c_char, c_int, c_uint, c_void, CString};
    use std::os::unix::ffi::OsStrExt;
    use std::path::{Path, PathBuf};
    use parking_lot::Mutex;

    const RTLD_NOW: c_int = 2;
    // CERTDB_VALID_CA (0x08) | CERTDB_TRUSTED_CA (0x10) | CERTDB_NS_TRUSTED_CA (0x20) | CERTDB_TRUSTED_CLIENT_CA (0x80)
    const TRUST_SSL_CA: c_uint = 0xB8;
    const SI_BUFFER: c_uint = 0;

    #[repr(C)]
    struct SecItem {
        item_type: c_uint,
        data: *mut u8,
        len: c_uint,
    }

    #[repr(C)]
    struct CertCertTrust {
        ssl_flags: c_uint,
        email_flags: c_uint,
        object_signing_flags: c_uint,
    }

    #[cfg_attr(target_os = "linux", link(name = "dl"))]
    extern "C" {
        fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
        fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    }

    // Keep loaded libnss3.so handle open for process lifetime (dlclose is unsafe with NSS)
    // and serialize NSS_InitReadWrite / NSS_Shutdown calls across threads.
    static NSS_LIB_LOCK: Mutex<Option<(PathBuf, usize)>> = Mutex::new(None);

    unsafe fn sym<T>(handle: *mut c_void, name: &[u8]) -> Option<T> {
        let cname = std::ffi::CStr::from_bytes_with_nul(name).ok()?;
        let ptr = dlsym(handle, cname.as_ptr());
        if ptr.is_null() {
            return None;
        }
        Some(std::mem::transmute_copy(&ptr))
    }

    pub fn register_ca_via_nss_shared_lib(
        libnss_path: &Path,
        nss_dir_arg: &str,
        cert_der: &[u8],
    ) -> bool {
        if cert_der.is_empty() || cert_der.len() > u32::MAX as usize {
            return false;
        }
        let Ok(c_dir) = CString::new(nss_dir_arg) else {
            return false;
        };
        let Ok(c_nick) = CString::new("Chronos Local Focus CA") else {
            return false;
        };

        let mut guard = NSS_LIB_LOCK.lock();
        let handle = if let Some((_, cached_ptr)) = guard.as_ref() {
            *cached_ptr as *mut c_void
        } else {
            let Ok(c_lib) = CString::new(libnss_path.as_os_str().as_bytes()) else {
                return false;
            };
            let h = unsafe { dlopen(c_lib.as_ptr(), RTLD_NOW) };
            if h.is_null() {
                return false;
            }
            *guard = Some((libnss_path.to_path_buf(), h as usize));
            h
        };
        if handle.is_null() {
            return false;
        }

        type FnInitReadWrite = unsafe extern "C" fn(*const c_char) -> c_int;
        type FnGetInternalKeySlot = unsafe extern "C" fn() -> *mut c_void;
        type FnGetDefaultCertDB = unsafe extern "C" fn() -> *mut c_void;
        type FnNewTempCert =
            unsafe extern "C" fn(*mut c_void, *mut SecItem, *const c_char, c_int, c_int) -> *mut c_void;
        type FnImportCert =
            unsafe extern "C" fn(*mut c_void, *mut c_void, usize, *const c_char, c_int) -> c_int;
        type FnChangeCertTrust =
            unsafe extern "C" fn(*mut c_void, *mut c_void, *mut CertCertTrust) -> c_int;
        type FnDestroyCert = unsafe extern "C" fn(*mut c_void);
        type FnFreeSlot = unsafe extern "C" fn(*mut c_void);
        type FnShutdown = unsafe extern "C" fn() -> c_int;

        unsafe {
            let Some(nss_init) = sym::<FnInitReadWrite>(handle, b"NSS_InitReadWrite\0") else {
                return false;
            };
            let Some(get_slot) = sym::<FnGetInternalKeySlot>(handle, b"PK11_GetInternalKeySlot\0") else {
                return false;
            };
            let Some(get_db) = sym::<FnGetDefaultCertDB>(handle, b"CERT_GetDefaultCertDB\0") else {
                return false;
            };
            let Some(new_temp) = sym::<FnNewTempCert>(handle, b"CERT_NewTempCertificate\0") else {
                return false;
            };
            let Some(import_cert) = sym::<FnImportCert>(handle, b"PK11_ImportCert\0") else {
                return false;
            };
            let Some(change_trust) = sym::<FnChangeCertTrust>(handle, b"CERT_ChangeCertTrust\0") else {
                return false;
            };
            let Some(destroy_cert) = sym::<FnDestroyCert>(handle, b"CERT_DestroyCertificate\0") else {
                return false;
            };
            let Some(free_slot) = sym::<FnFreeSlot>(handle, b"PK11_FreeSlot\0") else {
                return false;
            };
            let Some(nss_shutdown) = sym::<FnShutdown>(handle, b"NSS_Shutdown\0") else {
                return false;
            };

            if nss_init(c_dir.as_ptr()) != 0 {
                return false;
            }

            let mut ok = false;
            let slot = get_slot();
            let db = get_db();
            if !slot.is_null() && !db.is_null() {
                let mut der_buf = cert_der.to_vec();
                let mut item = SecItem {
                    item_type: SI_BUFFER,
                    data: der_buf.as_mut_ptr(),
                    len: der_buf.len() as c_uint,
                };
                let cert = new_temp(db, &mut item, std::ptr::null(), 0, 1);
                if !cert.is_null() {
                    let ir = import_cert(slot, cert, 0, c_nick.as_ptr(), 0);
                    let mut trust = CertCertTrust {
                        ssl_flags: TRUST_SSL_CA,
                        email_flags: 0,
                        object_signing_flags: 0,
                    };
                    let cr = change_trust(db, cert, &mut trust);
                    destroy_cert(cert);
                    ok = ir == 0 && cr == 0;
                }
            }
            if !slot.is_null() {
                free_slot(slot);
            }
            let _ = nss_shutdown();
            ok
        }
    }
}

fn register_ca_in_nss_db_for_home(nssdb: &Path, ca_cert: &Path, home: Option<&Path>) {
    if std::fs::create_dir_all(nssdb).is_err() {
        return;
    }
    let nss_arg = format!("sql:{}", nssdb.to_string_lossy());
    if !nssdb.join("cert9.db").exists() {
        let _ = Command::new("certutil")
            .args(["-d", &nss_arg, "-N", "--empty-password"])
            .output();
    }
    // Remove up to 4 old/duplicate entries so Steam/CEF never reads an obsolete or conflicting CA
    for _ in 0..4 {
        let out = Command::new("certutil")
            .args(["-d", &nss_arg, "-D", "-n", "Chronos Local Focus CA"])
            .output();
        if !out.map(|o| o.status.success()).unwrap_or(false) {
            break;
        }
    }

    #[cfg(unix)]
    if let (Some(h), Some(der)) = (home, pem_to_der_bytes(ca_cert)) {
        if let Some(libnss) = find_steamrt_libnss3(h) {
            if nss_ffi::register_ca_via_nss_shared_lib(&libnss, &nss_arg, &der) {
                return;
            }
        }
    }

    let _ = Command::new("certutil")
        .args([
            "-d",
            &nss_arg,
            "-A",
            "-t",
            "CT,,",
            "-n",
            "Chronos Local Focus CA",
            "-i",
            ca_cert.to_string_lossy().as_ref(),
        ])
        .output();
}

#[allow(dead_code)]
fn register_ca_in_nss_db(nssdb: &Path, ca_cert: &Path) {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    register_ca_in_nss_db_for_home(nssdb, ca_cert, home.as_deref());
}

fn sync_system_ca_if_needed(home: &Path, ca_cert: &Path) {
    let guard_bin = Path::new("/usr/local/lib/chronos/chronos-guard");
    if !guard_bin.exists() {
        return;
    }
    // Arch (p11-kit anchors) or Debian/Ubuntu (update-ca-certificates).
    let local_bytes = std::fs::read(ca_cert).unwrap_or_default();
    let installed = [
        "/etc/ca-certificates/trust-source/anchors/chronos-proxy-ca.crt",
        "/usr/local/share/ca-certificates/chronos-proxy-ca.crt",
    ]
    .iter()
    .any(|p| std::fs::read(p).is_ok_and(|b| b == local_bytes));
    if local_bytes.is_empty() || installed {
        return;
    }
    let expected_ca = home.join(".local/share/chronos/ca/chronos-proxy-ca.crt");
    let pac_path = home.join(".local/share/chronos/proxy.pac");
    if !expected_ca.exists() || !pac_path.exists() {
        return;
    }
    // Executa exatamente a linha liberada na regra Polkit (`49-chronos-guard.rules`) sem pedir senha.
    let _ = Command::new("pkexec")
        .args([
            "--disable-internal-agent",
            guard_bin.to_string_lossy().as_ref(),
            "update-ca",
            expected_ca.to_string_lossy().as_ref(),
            pac_path.to_string_lossy().as_ref(),
        ])
        .output();
}

const TARGET_LAUNCHER_DESKTOPS: [&str; 6] = [
    "steam.desktop",
    "com.valvesoftware.Steam.desktop",
    "heroic.desktop",
    "com.heroicgameslauncher.hgl.desktop",
    "lutris.desktop",
    "net.lutris.Lutris.desktop",
];

const TARGET_FLATPAK_LAUNCHERS: [&str; 3] = [
    "com.valvesoftware.Steam",
    "com.heroicgameslauncher.hgl",
    "net.lutris.Lutris",
];

const LAUNCHER_OVERRIDE_MARKER: &str = "# Chronos Launcher Proxy Override";
const LAUNCHER_WRAPPER_VERSION_MARKER: &str = "# Chronos Launcher Proxy Env v2";

fn desktop_search_dirs(home: &Path) -> [PathBuf; 4] {
    [
        PathBuf::from("/usr/share/applications"),
        PathBuf::from("/usr/local/share/applications"),
        PathBuf::from("/var/lib/flatpak/exports/share/applications"),
        home.join(".local/share/flatpak/exports/share/applications"),
    ]
}

fn find_source_desktop_file(dirs: &[PathBuf], desktop_name: &str) -> Option<PathBuf> {
    dirs.iter()
        .map(|d| d.join(desktop_name))
        .find(|p| p.exists())
}

/// Installs/removes NSS CA trust (`~/.pki/nssdb` + Flatpak NSS DBs + combined CA bundle)
/// and fail-open `.desktop` overrides for Steam/Heroic/Lutris/Electron launchers so internal
/// Store/Guides/Discussions/Artworks route through `chronos_proxy` (`127.0.0.1:4546`).
pub fn has_launcher_proxy_configured_in_home(home: &Path) -> bool {
    let wrapper_path = home.join(".local/share/chronos/bin/chronos-launcher-env");
    if wrapper_path.exists() {
        return true;
    }
    let user_apps_dir = home.join(".local/share/applications");
    for name in TARGET_LAUNCHER_DESKTOPS {
        let p = user_apps_dir.join(name);
        if let Ok(content) = std::fs::read_to_string(&p) {
            if content.contains(LAUNCHER_OVERRIDE_MARKER) {
                return true;
            }
        }
    }
    false
}

pub fn has_launcher_proxy_configured() -> bool {
    let Some(home) = std::env::var_os("HOME").map(PathBuf::from) else {
        return false;
    };
    has_launcher_proxy_configured_in_home(&home)
}

/// Returns true when launcher proxy was previously enabled AND at least one installed launcher
/// `.desktop`, Flatpak CA dir/NSS DB, or the `chronos-launcher-env` wrapper needs (re)sync.
pub fn needs_launcher_proxy_resync_in_home_with_dirs(
    home: &Path,
    search_sys_dirs: &[PathBuf],
) -> bool {
    if !has_launcher_proxy_configured_in_home(home) {
        return false;
    }
    let wrapper_path = home.join(".local/share/chronos/bin/chronos-launcher-env");
    let Ok(wrapper_txt) = std::fs::read_to_string(&wrapper_path) else {
        return true;
    };
    if !wrapper_txt.contains(LAUNCHER_WRAPPER_VERSION_MARKER) {
        return true;
    }

    let user_apps_dir = home.join(".local/share/applications");
    for desktop_name in TARGET_LAUNCHER_DESKTOPS {
        if find_source_desktop_file(search_sys_dirs, desktop_name).is_some() {
            let dst = user_apps_dir.join(desktop_name);
            let ok = std::fs::read_to_string(&dst)
                .map(|c| c.contains(LAUNCHER_OVERRIDE_MARKER))
                .unwrap_or(false);
            if !ok {
                return true;
            }
        }
    }

    for app_id in TARGET_FLATPAK_LAUNCHERS {
        let app_dir = home.join(".var/app").join(app_id);
        if app_dir.exists() {
            let ca_ok = app_dir
                .join("data/chronos-ca/chronos-combined-ca-bundle.crt")
                .exists()
                && app_dir
                    .join("data/chronos-ca/chronos-proxy-ca.crt")
                    .exists();
            let nss_ok = app_dir.join("data/pki/nssdb/cert9.db").exists()
                && app_dir.join(".pki/nssdb/cert9.db").exists();
            if !ca_ok || !nss_ok {
                return true;
            }
        }
    }

    false
}

pub fn needs_launcher_proxy_resync_in_home(home: &Path) -> bool {
    needs_launcher_proxy_resync_in_home_with_dirs(home, &desktop_search_dirs(home))
}

/// Re-applies launcher proxy wrapper, NSS CA trust, Flatpak sandbox CA files,
/// and `.desktop` overrides if launcher proxy was previously enabled.
pub fn sync_launcher_proxy_if_configured() -> bool {
    if !crate::profile::allows_system_integrations() {
        return false;
    }
    let Some(home) = std::env::var_os("HOME").map(PathBuf::from) else {
        return false;
    };
    if !has_launcher_proxy_configured_in_home(&home) {
        return false;
    }
    configure_native_launcher_proxy_for_home(&home, true).is_ok()
}

/// Fast periodic check that re-syncs only if launcher proxy is enabled and out of date
/// (for instance when Heroic or Lutris was installed after enabling launcher proxy).
pub fn sync_launcher_proxy_if_needed() -> bool {
    if !crate::profile::allows_system_integrations() {
        return false;
    }
    let Some(home) = std::env::var_os("HOME").map(PathBuf::from) else {
        return false;
    };
    if !needs_launcher_proxy_resync_in_home(&home) {
        return false;
    }
    configure_native_launcher_proxy_for_home(&home, true).is_ok()
}

pub fn configure_native_launcher_proxy(enable: bool) -> Result<String, String> {
    if !crate::profile::allows_system_integrations() {
        return Err("Indisponível no modo dev (não altera atalhos de launchers do sistema).".to_string());
    }
    let home_str = std::env::var("HOME").map_err(|_| "HOME not set".to_string())?;
    let home = PathBuf::from(&home_str);
    configure_native_launcher_proxy_for_home(&home, enable)
}

pub fn configure_native_launcher_proxy_for_home(
    home: &Path,
    enable: bool,
) -> Result<String, String> {
    let search_sys_dirs = desktop_search_dirs(home);
    configure_native_launcher_proxy_for_home_with_dirs(home, enable, &search_sys_dirs)
}

pub fn configure_native_launcher_proxy_for_home_with_dirs(
    home: &Path,
    enable: bool,
    search_sys_dirs: &[PathBuf],
) -> Result<String, String> {
    let bin_dir = home.join(".local/share/chronos/bin");
    let wrapper_path = bin_dir.join("chronos-launcher-env");
    let user_apps_dir = home.join(".local/share/applications");

    if !enable {
        for name in TARGET_LAUNCHER_DESKTOPS {
            let p = user_apps_dir.join(name);
            if let Ok(content) = std::fs::read_to_string(&p) {
                if content.contains(LAUNCHER_OVERRIDE_MARKER) {
                    let _ = std::fs::remove_file(&p);
                }
            }
        }
        for app_id in TARGET_FLATPAK_LAUNCHERS {
            let ca_stage = home.join(".var/app").join(app_id).join("data/chronos-ca");
            if ca_stage.exists() {
                let _ = std::fs::remove_dir_all(&ca_stage);
            }
        }
        let _ = std::fs::remove_file(&wrapper_path);
        return Ok(
            "Proxy interno nos launchers desativado. Reinicie os launchers se estiverem abertos."
                .to_string(),
        );
    }

    let ca_cert = find_proxy_ca_cert(home).ok_or_else(|| {
        "Certificado CA do proxy não encontrado. Inicie o proxy do Chronos ao menos uma vez primeiro."
            .to_string()
    })?;

    // 1. Register CA in ~/.pki/nssdb + Flatpak NSS DBs + combined PEM bundle + Flatpak sandbox CA dir
    sync_system_ca_if_needed(home, &ca_cert);
    register_ca_in_nss_db_for_home(&home.join(".pki/nssdb"), &ca_cert, Some(home));
    // Ubuntu snaps keep their own NSS DB inside ~/snap/<name>/current.
    for snap in ["chromium", "brave", "opera", "vivaldi"] {
        let dir = home.join("snap").join(snap);
        if dir.is_dir() {
            register_ca_in_nss_db_for_home(&dir.join("current/.pki/nssdb"), &ca_cert, Some(home));
        }
    }
    let combined_bundle = build_combined_ca_bundle(home, &ca_cert);
    let combined_path_str = combined_bundle
        .as_ref()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|| ca_cert.to_string_lossy().to_string());
    let ca_path_str = ca_cert.to_string_lossy().to_string();

    for app_id in TARGET_FLATPAK_LAUNCHERS {
        let app_dir = home.join(".var/app").join(app_id);
        if !app_dir.exists() {
            continue;
        }
        for rel in [".pki/nssdb", "data/pki/nssdb"] {
            register_ca_in_nss_db_for_home(&app_dir.join(rel), &ca_cert, Some(home));
        }
        let stage_dir = app_dir.join("data/chronos-ca");
        if std::fs::create_dir_all(&stage_dir).is_ok() {
            let stage_ca = stage_dir.join("chronos-proxy-ca.crt");
            let stage_combined = stage_dir.join("chronos-combined-ca-bundle.crt");
            let _ = std::fs::copy(&ca_cert, &stage_ca);
            if let Some(ref bundle) = combined_bundle {
                let _ = std::fs::copy(bundle, &stage_combined);
            } else {
                let _ = std::fs::copy(&ca_cert, &stage_combined);
            }
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = std::fs::set_permissions(&stage_dir, std::fs::Permissions::from_mode(0o755));
                let _ = std::fs::set_permissions(&stage_ca, std::fs::Permissions::from_mode(0o644));
                let _ = std::fs::set_permissions(&stage_combined, std::fs::Permissions::from_mode(0o644));
            }
        }
    }

    // 2. Write fail-open launcher env wrapper (supports native & Flatpak `--env` + `--file-forwarding`)
    std::fs::create_dir_all(&bin_dir).map_err(|e| e.to_string())?;
    let wrapper_script = format!(
        r#"#!/usr/bin/env bash
{LAUNCHER_WRAPPER_VERSION_MARKER}
if ! (echo >/dev/tcp/127.0.0.1/4546) >/dev/null 2>&1; then
  exec "$@"
fi

PROXY_URL="http://127.0.0.1:4546"
CHRONOS_NO_PROXY="localhost,127.0.0.1,::1,steamloopback.host,.steamloopback.host,.local,login.steampowered.com,api.steampowered.com,checkout.steampowered.com,steamserver.net,.steamserver.net,steam-chat.com,.steam-chat.com,steamcontent.com,.steamcontent.com,steamusercontent.com,.steamusercontent.com,steamstatic.com,.steamstatic.com,akamaihd.net,.akamaihd.net"

export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export ALL_PROXY="$PROXY_URL"
export NSS_USE_SHARED_DB="enabled"
export no_proxy="$CHRONOS_NO_PROXY"
export NO_PROXY="$CHRONOS_NO_PROXY"
if [ -f "{combined_path_str}" ]; then
  export SSL_CERT_FILE="{combined_path_str}"
  export CURL_CA_BUNDLE="{combined_path_str}"
  export REQUESTS_CA_BUNDLE="{combined_path_str}"
fi
if [ -f "{ca_path_str}" ]; then
  export NODE_EXTRA_CA_CERTS="{ca_path_str}"
fi

CMD_BASE="$(basename "${{1:-}}")"
if [ "$CMD_BASE" = "flatpak" ] && [ "${{2:-}}" = "run" ]; then
  FLATPAK_BIN="$1"
  shift 2
  APP_ID=""
  for arg in "$@"; do
    case "$arg" in
      com.valvesoftware.Steam|com.heroicgameslauncher.hgl|net.lutris.Lutris)
        APP_ID="$arg"
        break
        ;;
    esac
  done

  ENV_ARGS=(
    "--env=http_proxy=$PROXY_URL"
    "--env=https_proxy=$PROXY_URL"
    "--env=HTTP_PROXY=$PROXY_URL"
    "--env=HTTPS_PROXY=$PROXY_URL"
    "--env=ALL_PROXY=$PROXY_URL"
    "--env=NSS_USE_SHARED_DB=enabled"
    "--env=no_proxy=$CHRONOS_NO_PROXY"
    "--env=NO_PROXY=$CHRONOS_NO_PROXY"
  )
  if [ -n "$APP_ID" ]; then
    SB_COMBINED="$HOME/.var/app/$APP_ID/data/chronos-ca/chronos-combined-ca-bundle.crt"
    SB_CA="$HOME/.var/app/$APP_ID/data/chronos-ca/chronos-proxy-ca.crt"
    if [ -f "$SB_COMBINED" ]; then
      ENV_ARGS+=(
        "--env=SSL_CERT_FILE=$SB_COMBINED"
        "--env=CURL_CA_BUNDLE=$SB_COMBINED"
        "--env=REQUESTS_CA_BUNDLE=$SB_COMBINED"
      )
    fi
    if [ -f "$SB_CA" ]; then
      ENV_ARGS+=("--env=NODE_EXTRA_CA_CERTS=$SB_CA")
    fi
  fi

  if [ "$APP_ID" = "com.heroicgameslauncher.hgl" ]; then
    NEW_ARGS=()
    INSERTED=0
    for arg in "$@"; do
      NEW_ARGS+=("$arg")
      if [ "$INSERTED" = "0" ] && [ "$arg" = "com.heroicgameslauncher.hgl" ]; then
        NEW_ARGS+=("--proxy-server=$PROXY_URL" "--proxy-bypass-list=localhost;127.0.0.1;::1")
        INSERTED=1
      fi
    done
    exec "$FLATPAK_BIN" run "${{ENV_ARGS[@]}}" "${{NEW_ARGS[@]}}"
  fi

  exec "$FLATPAK_BIN" run "${{ENV_ARGS[@]}}" "$@"
fi

case "$CMD_BASE" in
  heroic|heroic-bin|heroic-run)
    exec "$@" "--proxy-server=$PROXY_URL" "--proxy-bypass-list=localhost;127.0.0.1;::1"
    ;;
esac

exec "$@"
"#
    );
    std::fs::write(&wrapper_path, wrapper_script).map_err(|e| e.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&wrapper_path, std::fs::Permissions::from_mode(0o755));
    }

    // 3. Create user-level `.desktop` overrides wrapping system `.desktop` Exec lines
    std::fs::create_dir_all(&user_apps_dir).map_err(|e| e.to_string())?;
    let mut wrapped_count = 0;
    for desktop_name in TARGET_LAUNCHER_DESKTOPS {
        let Some(src) = find_source_desktop_file(search_sys_dirs, desktop_name) else {
            continue;
        };
        let Ok(raw) = std::fs::read_to_string(&src) else {
            continue;
        };
        let mut out_lines = Vec::with_capacity(raw.lines().count() + 2);
        out_lines.push(LAUNCHER_OVERRIDE_MARKER.to_string());
        for line in raw.lines() {
            if line.eq_ignore_ascii_case("DBusActivatable=true") {
                out_lines.push("DBusActivatable=false".to_string());
            } else if let Some(cmd) = line.strip_prefix("Exec=") {
                if cmd.contains("chronos-launcher-env") {
                    out_lines.push(line.to_string());
                } else {
                    out_lines.push(format!("Exec={} {}", wrapper_path.to_string_lossy(), cmd.trim()));
                }
            } else {
                out_lines.push(line.to_string());
            }
        }
        let dst = user_apps_dir.join(desktop_name);
        if std::fs::write(&dst, out_lines.join("\n") + "\n").is_ok() {
            wrapped_count += 1;
        }
    }

    Ok(format!(
        "Proteção de loja/comunidade ativada ({wrapped_count} atalho(s) de launcher configurado(s) + CA NSS). Reinicie a Steam/Heroic/Lutris para aplicar na loja interna."
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_steam_vdf_and_acf_parsers() {
        let vdf = r#"
        "libraryfolders"
        {
            "0"
            {
                "path"		"/home/user/.local/share/Steam"
            }
            "1"
            {
                "path"		"/mnt/games/SteamLibrary"
            }
        }
        "#;
        let libs = parse_steam_library_folders_vdf(vdf);
        assert_eq!(libs.len(), 2);
        assert!(libs[1].ends_with("SteamLibrary/steamapps"));

        let acf_game = r#"
        "AppState"
        {
            "appid"		"1145360"
            "name"		"Hades"
            "installdir"		"Hades"
        }
        "#;
        let entry = parse_steam_appmanifest_acf(acf_game).expect("valid game");
        assert_eq!(entry.app_id, Some(1145360));
        assert_eq!(entry.title, "Hades");

        let acf_proton = r#"
        "AppState"
        {
            "appid"		"1493710"
            "name"		"Proton Experimental"
            "installdir"		"Proton - Experimental"
        }
        "#;
        assert!(parse_steam_appmanifest_acf(acf_proton).is_none());
    }

    #[test]
    fn test_heroic_and_window_helpers() {
        let legendary = r#"{
          "Hades": { "title": "Hades", "install_path": "/home/u/Games/Heroic/Hades", "executable": "Hades.exe" }
        }"#;
        let items = parse_heroic_installed_json(legendary, "Epic");
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].title, "Hades");
        assert_eq!(items[0].launcher, "Heroic (Epic)");

        assert_eq!(
            clean_launcher_window_title("Guides :: Counter-Strike 2 - Steam"),
            "Counter-Strike 2"
        );
        assert_eq!(
            clean_launcher_window_title("Discussões :: Hollow Knight"),
            "Hollow Knight"
        );
        assert_eq!(
            extract_appid_from_cmd(&["reaper".to_string(), "SteamAppId=730".to_string()]),
            Some(730)
        );
    }

    #[test]
    fn test_find_proxy_ca_cert_and_combined_bundle() {
        let tmp = std::env::temp_dir().join(format!("chronos_ca_bundle_test_{}", std::process::id()));
        let ca_dir = tmp.join(".local/share/chronos/ca");
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(&ca_dir).unwrap();

        let ca = crate::proxy::CertAuthority::load_or_create(&ca_dir).unwrap();
        let _ = ca;
        let found = find_proxy_ca_cert(&tmp).expect("should find chronos-proxy-ca.crt");
        assert!(found.ends_with("chronos-proxy-ca.crt"));

        let bundle = build_combined_ca_bundle(&tmp, &found).expect("bundle should be written");
        assert!(bundle.exists());
        let bundle_text = std::fs::read_to_string(&bundle).unwrap();
        let ca_text = std::fs::read_to_string(&found).unwrap();
        assert!(bundle_text.contains(ca_text.trim()));

        let der = pem_to_der_bytes(&found).expect("valid PEM should convert to DER");
        assert!(!der.is_empty());

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_has_launcher_proxy_and_wrapper_generation() {
        let tmp = std::env::temp_dir().join(format!("chronos_launcher_wrap_{}", std::process::id()));
        let ca_dir = tmp.join(".local/share/chronos/ca");
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(&ca_dir).unwrap();
        let _ca = crate::proxy::CertAuthority::load_or_create(&ca_dir).unwrap();

        assert!(!has_launcher_proxy_configured_in_home(&tmp));

        let res = configure_native_launcher_proxy_for_home(&tmp, true);
        assert!(res.is_ok(), "unexpected error: {:?}", res);
        assert!(has_launcher_proxy_configured_in_home(&tmp));

        let wrapper = tmp.join(".local/share/chronos/bin/chronos-launcher-env");
        let wrapper_text = std::fs::read_to_string(&wrapper).unwrap();
        assert!(wrapper_text.contains("NSS_USE_SHARED_DB=\"enabled\""));
        assert!(wrapper_text.contains("chronos-combined-ca-bundle.crt"));
        assert!(wrapper_text.contains("http://127.0.0.1:4546"));

        let nssdb = tmp.join(".pki/nssdb");
        assert!(nssdb.join("cert9.db").exists());

        let off = configure_native_launcher_proxy_for_home(&tmp, false);
        assert!(off.is_ok());
        assert!(!has_launcher_proxy_configured_in_home(&tmp));

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_lutris_hidden_category_sync_and_new_yaml_dir() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let tmp = std::env::temp_dir().join(format!("chronos_lutris_hide_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        let data_dir = tmp.join(".local/share/lutris");
        std::fs::create_dir_all(data_dir.join("games")).unwrap();
        let db_file = tmp.join("chronos.db");
        db::init_db(db_file.to_str().unwrap()).expect("init temp db");

        // Lutris 0.5.22 layout: YAML next to pga.db, Steam service games
        std::fs::write(
            data_dir.join("games/steam-250900-1.yml"),
            "system: {}\nnull: {}\ngame:\n  appid: '250900'\n",
        )
        .unwrap();
        let pga = data_dir.join("pga.db");
        {
            let conn = rusqlite::Connection::open(&pga).unwrap();
            conn.execute_batch(
                "CREATE TABLE games (id INTEGER PRIMARY KEY, name TEXT, slug TEXT, runner TEXT,
                    executable TEXT, directory TEXT, installed INTEGER, configpath TEXT,
                    service TEXT, service_id TEXT);
                 CREATE TABLE service_games (id INTEGER PRIMARY KEY, service TEXT, appid TEXT, name TEXT,
                    slug TEXT, icon TEXT, logo TEXT, url TEXT, details TEXT, lutris_slug TEXT);
                 INSERT INTO service_games (service, appid, name, slug, details) VALUES
                    ('steam','250900','The Binding of Isaac: Rebirth','isaac','details-isaac'),
                    ('steam','105600','Terraria','terraria','{}');
                 CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT UNIQUE);
                 CREATE TABLE games_categories (game_id INTEGER, category_id INTEGER);
                 INSERT INTO games VALUES (1,'The Binding of Isaac: Rebirth','the-binding-of-isaac-rebirth','steam','','',1,'steam-250900-1','steam','250900');
                 INSERT INTO games VALUES (2,'Terraria','terraria','steam','','',1,'steam-105600-1','steam','105600');
                 INSERT INTO games VALUES (3,'User Hidden Rogue','user-hidden-rogue','linux','','',1,'','','');
                 INSERT INTO categories (id, name) VALUES (7, '.hidden');
                 INSERT INTO games_categories VALUES (3, 7);",
            )
            .unwrap();
        }

        let meta = |title: &str, app_id: Option<i64>, tags: &[&str]| steam_api::GameMetadata {
            app_id,
            title: title.to_string(),
            tags: tags.iter().map(|t| t.to_string()).collect(),
            genres: Vec::new(),
            categories: Vec::new(),
            source: "steam_browse_service".to_string(),
        };
        steam_api::save_cached_metadata("appid:250900", &meta("The Binding of Isaac: Rebirth", Some(250900), &["Roguelike"]));
        steam_api::save_cached_metadata("appid:105600", &meta("Terraria", Some(105600), &["Sandbox"]));
        steam_api::save_cached_metadata(
            &format!("title:{}", steam_api::normalize_match_text("User Hidden Rogue")),
            &meta("User Hidden Rogue", None, &["Roguelike"]),
        );

        // New YAML dir is scanned and merged into the pga.db entry
        let games = discover_installed_games_in_home(&tmp);
        assert!(games.iter().any(|g| g.app_id == Some(250900)));

        let hidden_ids = || -> Vec<i64> {
            let conn = rusqlite::Connection::open(&pga).unwrap();
            let mut st = conn
                .prepare("SELECT game_id FROM games_categories gc JOIN categories c ON c.id = gc.category_id WHERE c.name = '.hidden' ORDER BY game_id")
                .unwrap();
            st.query_map([], |r| r.get::<_, i64>(0)).unwrap().flatten().collect()
        };

        let mut filters = db::FocusFilters::default();
        filters.launcher_filter_enabled = true;
        filters.launcher_blocked_tags = vec!["Roguelike".to_string()];
        db::set_focus_filters(&filters);

        let service_rows = || -> Vec<String> {
            let conn = rusqlite::Connection::open(&pga).unwrap();
            let mut st = conn
                .prepare("SELECT appid || ':' || name || ':' || details FROM service_games ORDER BY appid")
                .unwrap();
            st.query_map([], |r| r.get::<_, String>(0)).unwrap().flatten().collect()
        };

        sync_lutris_hidden_games_in_home(&tmp);
        assert_eq!(hidden_ids(), vec![1, 3], "Isaac hidden, Terraria visible, user-hidden kept");
        assert_eq!(service_rows(), vec!["105600:Terraria:{}".to_string()], "Isaac removed from Steam service view");
        // Idempotent
        assert_eq!(sync_lutris_hidden_games_in_home(&tmp), 0);

        // Unblocking restores only what Chronos hid; the user's own hidden game stays hidden
        filters.launcher_blocked_tags = vec!["FPS".to_string()];
        db::set_focus_filters(&filters);
        sync_lutris_hidden_games_in_home(&tmp);
        assert_eq!(hidden_ids(), vec![3]);
        assert_eq!(
            service_rows(),
            vec![
                "105600:Terraria:{}".to_string(),
                "250900:The Binding of Isaac: Rebirth:details-isaac".to_string()
            ],
            "Isaac row restored verbatim"
        );

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_lutris_discovery_yaml_pga_and_wine_process_matching() {
        let _lock = crate::tests::TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let tmp = std::env::temp_dir().join(format!("chronos_lutris_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);

        let yml_dir = tmp.join(".config/lutris/games");
        let fp_db_dir = tmp.join(".var/app/net.lutris.Lutris/data/lutris");
        std::fs::create_dir_all(&yml_dir).unwrap();
        std::fs::create_dir_all(&fp_db_dir).unwrap();

        // Indented Lutris YAML WITHOUT root `name:`
        let isaac_yml = r#"
game:
  exe: /home/u/Games/Isaac/isaac-ng.exe
  prefix: /home/u/Games/Prefixes/isaac-pfx
  working_dir: /home/u/Games/Isaac
  appid: 250900
runner: wine
"#;
        std::fs::write(
            yml_dir.join("the-binding-of-isaac-rebirth-1700000001.yml"),
            isaac_yml,
        )
        .unwrap();

        let standalone = parse_simple_yaml_game(
            isaac_yml,
            "Lutris",
            "the-binding-of-isaac-rebirth-1700000001",
        )
        .expect("should parse Lutris YAML without root name");
        assert_eq!(standalone.title, "The Binding Of Isaac Rebirth");
        assert_eq!(standalone.app_id, Some(250900));
        assert_eq!(standalone.wine_prefix, "/home/u/Games/Prefixes/isaac-pfx");

        // Flatpak `pga.db` referencing `configpath` merges executable + wine_prefix + app_id
        let pga_db_path = fp_db_dir.join("pga.db");
        let conn = rusqlite::Connection::open(&pga_db_path).unwrap();
        conn.execute(
            "CREATE TABLE games (
                id INTEGER PRIMARY KEY,
                slug TEXT,
                name TEXT,
                runner TEXT,
                executable TEXT,
                directory TEXT,
                configpath TEXT,
                installed INTEGER
            )",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO games (slug, name, runner, executable, directory, configpath, installed)
             VALUES (?1, ?2, ?3, '', '', ?4, 1)",
            rusqlite::params![
                "the-binding-of-isaac-rebirth",
                "The Binding of Isaac: Rebirth",
                "wine",
                "the-binding-of-isaac-rebirth-1700000001"
            ],
        )
        .unwrap();
        drop(conn);

        let mut catalog = Vec::new();
        scan_lutris_and_bottles(&tmp, &mut catalog);
        assert_eq!(catalog.len(), 1);
        let entry = &catalog[0];
        assert_eq!(entry.title, "The Binding of Isaac: Rebirth");
        assert_eq!(entry.exec_hint, "/home/u/Games/Isaac/isaac-ng.exe");
        assert_eq!(entry.wine_prefix, "/home/u/Games/Prefixes/isaac-pfx");
        assert_eq!(entry.app_id, Some(250900));

        let by_appid: HashMap<i64, &LauncherGameEntry> = catalog
            .iter()
            .filter_map(|g| g.app_id.map(|id| (id, g)))
            .collect();

        // 1. Matches Wine process with Windows Z:\ path + WINEPREFIX
        let mut wine_env = HashMap::new();
        wine_env.insert(
            "WINEPREFIX".to_string(),
            "/home/u/Games/Prefixes/isaac-pfx".to_string(),
        );
        let m_wine = match_running_process_to_catalog(
            &catalog,
            &by_appid,
            "isaac-ng.exe",
            "/usr/bin/wine64-preloader",
            &[r"Z:\home\u\Games\Isaac\isaac-ng.exe".to_string()],
            r"z:\home\u\games\isaac\isaac-ng.exe",
            &wine_env,
        );
        assert_eq!(m_wine.map(|x| x.1), Some("The Binding of Isaac: Rebirth".to_string()));

        // 2. Never matches Lutris GUI client (`python3 /usr/bin/lutris` or `lutris`)
        assert!(match_running_process_to_catalog(
            &catalog,
            &by_appid,
            "python3",
            "/usr/bin/python3",
            &["/usr/bin/python3".to_string(), "/usr/bin/lutris".to_string()],
            "/usr/bin/python3 /usr/bin/lutris",
            &wine_env,
        )
        .is_none());

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_flatpak_heroic_lutris_nss_ca_staging_and_wrapper_resync() {
        let tmp = std::env::temp_dir().join(format!("chronos_flatpak_wrap_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        let ca_dir = tmp.join(".local/share/chronos/ca");
        let sys_apps = tmp.join("mock_sys_apps");
        let heroic_app_dir = tmp.join(".var/app/com.heroicgameslauncher.hgl");
        let lutris_app_dir = tmp.join(".var/app/net.lutris.Lutris");
        std::fs::create_dir_all(&ca_dir).unwrap();
        std::fs::create_dir_all(&sys_apps).unwrap();
        std::fs::create_dir_all(&heroic_app_dir).unwrap();
        std::fs::create_dir_all(&lutris_app_dir).unwrap();

        let _ca = crate::proxy::CertAuthority::load_or_create(&ca_dir).unwrap();

        std::fs::write(
            sys_apps.join("com.heroicgameslauncher.hgl.desktop"),
            "[Desktop Entry]\nName=Heroic\nExec=/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=heroic-run --file-forwarding com.heroicgameslauncher.hgl @@u %u @@\n",
        )
        .unwrap();

        let search_dirs = vec![sys_apps.clone()];
        let res = configure_native_launcher_proxy_for_home_with_dirs(&tmp, true, &search_dirs);
        assert!(res.is_ok(), "unexpected error: {:?}", res);

        // Verify both `.pki/nssdb` and `data/pki/nssdb` + `data/chronos-ca/` staged for Flatpaks
        assert!(heroic_app_dir.join(".pki/nssdb/cert9.db").exists());
        assert!(heroic_app_dir.join("data/pki/nssdb/cert9.db").exists());
        assert!(heroic_app_dir.join("data/chronos-ca/chronos-combined-ca-bundle.crt").exists());
        assert!(lutris_app_dir.join("data/chronos-ca/chronos-proxy-ca.crt").exists());

        // Validate `bash -n` syntax of generated `chronos-launcher-env`
        let wrapper = tmp.join(".local/share/chronos/bin/chronos-launcher-env");
        let bash_check = Command::new("bash").args(["-n", wrapper.to_str().unwrap()]).output().unwrap();
        assert!(bash_check.status.success(), "bash -n failed: {:?}", bash_check);

        // Verify no resync needed once synced, then detects newly installed Lutris `.desktop`!
        assert!(!needs_launcher_proxy_resync_in_home_with_dirs(&tmp, &search_dirs));
        std::fs::write(
            sys_apps.join("net.lutris.Lutris.desktop"),
            "[Desktop Entry]\nName=Lutris\nExec=/usr/bin/flatpak run net.lutris.Lutris %U\n",
        )
        .unwrap();
        assert!(needs_launcher_proxy_resync_in_home_with_dirs(&tmp, &search_dirs));

        let res2 = configure_native_launcher_proxy_for_home_with_dirs(&tmp, true, &search_dirs);
        assert!(res2.is_ok());
        assert!(!needs_launcher_proxy_resync_in_home_with_dirs(&tmp, &search_dirs));
        let wrapped_lutris = std::fs::read_to_string(
            tmp.join(".local/share/applications/net.lutris.Lutris.desktop"),
        )
        .unwrap();
        assert!(wrapped_lutris.contains("chronos-launcher-env"));

        // Disable removes wrapper, overrides, AND staged `data/chronos-ca`
        let off = configure_native_launcher_proxy_for_home_with_dirs(&tmp, false, &search_dirs);
        assert!(off.is_ok());
        assert!(!heroic_app_dir.join("data/chronos-ca").exists());

        let _ = std::fs::remove_dir_all(&tmp);
    }
}
