//! Standalone persistent daemon serving both Chronos selective proxy (`127.0.0.1:4546`)
//! and local Web API / blocked page (`127.0.0.1:4545`).

use std::path::PathBuf;

use rust_lib_chronos_app::{db, launchers, local_api, proxy};

fn parse_arg(args: &[String], flag: &str) -> Option<String> {
    args.windows(2)
        .find(|w| w[0] == flag)
        .map(|w| w[1].clone())
}

fn default_db_path() -> String {
    if let Ok(p) = std::env::var("CHRONOS_DB_PATH") {
        if !p.trim().is_empty() {
            return p;
        }
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let docs_db = PathBuf::from(&home).join("Documents/chronos.db");
    docs_db.to_string_lossy().into_owned()
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if let Some(ca_dir) = parse_arg(&args, "--ca-dir") {
        std::env::set_var("CHRONOS_CA_DIR", ca_dir);
    }
    let db_path = parse_arg(&args, "--db").unwrap_or_else(default_db_path);
    if let Some(parent) = std::path::Path::new(&db_path).parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    db::init_db(&db_path).expect("chronos_proxy: failed initializing SQLite database");

    let api_bind = std::env::var("CHRONOS_API_BIND")
        .unwrap_or_else(|_| format!("127.0.0.1:{}", local_api::API_DEFAULT_PORT));
    let proxy_cfg = proxy::ProxyConfig::from_env();

    let rt = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(4)
        .enable_all()
        .build()
        .expect("chronos_proxy: failed building Tokio runtime");

    rt.block_on(async move {
        let api_handle = tokio::spawn(async move {
            if let Err(e) = local_api::run_local_api_server(&api_bind).await {
                eprintln!("chronos_proxy API error: {e}");
                std::process::exit(1);
            }
            eprintln!("chronos_proxy API stopped unexpectedly");
            std::process::exit(1);
        });
        let proxy_handle = tokio::spawn(async move {
            if let Err(e) = proxy::run_proxy_server(proxy_cfg).await {
                eprintln!("chronos_proxy proxy error: {e}");
                std::process::exit(1);
            }
            eprintln!("chronos_proxy proxy stopped unexpectedly");
            std::process::exit(1);
        });
        let _launcher_sync_handle = tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(900)).await;
            let _ = tokio::task::spawn_blocking(|| {
                let _ = launchers::sync_launcher_proxy_if_configured();
            })
            .await;
        });
        let launcher_watchdog_handle = tokio::spawn(async move {
            let notify = local_api::subscribe_watchdog_notify();
            let mut last_rev = db::get_state_revision();
            let mut last_periodic = std::time::Instant::now();
            let mut last_proxy_sync = std::time::Instant::now();
            let mut last_lutris_hide_sync: Option<std::time::Instant> = None;
            loop {
                let notified = tokio::time::timeout(
                    std::time::Duration::from_millis(250),
                    notify.notified(),
                )
                .await
                .is_ok();
                let current_rev = db::get_state_revision();
                let rev_changed = current_rev != last_rev;
                if rev_changed {
                    last_rev = current_rev;
                    local_api::notify_state_changed();
                }
                let force = notified || rev_changed;
                if force || last_periodic.elapsed() >= std::time::Duration::from_secs(2) {
                    last_periodic = std::time::Instant::now();
                    let _ = tokio::task::spawn_blocking(move || {
                        let _ = launchers::detect_and_enforce_launcher_filters_with_options(force);
                    })
                    .await;
                }
                if rev_changed
                    || last_lutris_hide_sync
                        .map_or(true, |t| t.elapsed() >= std::time::Duration::from_secs(30))
                {
                    last_lutris_hide_sync = Some(std::time::Instant::now());
                    let _ = tokio::task::spawn_blocking(|| {
                        let _ = launchers::sync_lutris_hidden_games();
                    })
                    .await;
                }
                if last_proxy_sync.elapsed() >= std::time::Duration::from_secs(10) {
                    last_proxy_sync = std::time::Instant::now();
                    let _ = tokio::task::spawn_blocking(|| {
                        let _ = launchers::sync_launcher_proxy_if_needed();
                    })
                    .await;
                }
            }
        });

        let _ = api_handle.await;
        let _ = proxy_handle.await;
        let _ = launcher_watchdog_handle.await;
    });
}
