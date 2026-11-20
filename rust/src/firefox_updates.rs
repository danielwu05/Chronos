//! Firefox extension updates through the app (like Chromium's local update.xml).
//!
//! Firefox only updates a signed add-on through the manifest `update_url`, which must be
//! HTTPS. The daemon serves it on https://127.0.0.1:4547 with a certificate issued by the
//! Chronos CA (Firefox trusts it through the guard's `Certificates` policy):
//!   /extension/firefox-updates.json   update manifest (version + link)
//!   /extension/chronos.xpi            the Mozilla-signed XPI
//! Only signed XPIs are offered (unsigned ones cannot be installed by Firefox release).

use std::path::PathBuf;
use tokio::io::AsyncWriteExt;
use tokio::net::TcpListener;

pub const FIREFOX_ADDON_ID: &str = "chronos-focus@chronos.local";
pub const UPDATE_PORT: u16 = 4547;

/// Signed XPI candidates: dev-signed copy, then the one the app packaged for the guard
/// (the bundled release `signed.xpi` is copied there), then the root store.
fn signed_xpi_path() -> Option<PathBuf> {
    let data = crate::profile::data_dir();
    [
        data.join("chronos-signed.xpi"),
        data.join("guard/build/chronos.xpi"),
        PathBuf::from("/usr/local/share/chronos/chronos.xpi"),
    ]
    .into_iter()
    .filter(|p| p.is_file() && xpi_is_signed(p))
    .max_by_key(|p| {
        xpi_manifest_version(p)
            .map(|v| crate::local_api::version_sort_key_pub(&v))
            .unwrap_or_default()
    })
}

pub fn xpi_is_signed(path: &std::path::Path) -> bool {
    std::fs::read(path)
        .map(|b| b.windows(20).any(|w| w == b"META-INF/mozilla.rsa"))
        .unwrap_or(false)
}

pub fn xpi_manifest_version(path: &std::path::Path) -> Option<String> {
    let bytes = std::fs::read(path).ok()?;
    let manifest = crate::local_api::read_zip_entry_pub(&bytes, "manifest.json")?;
    let parsed: serde_json::Value = serde_json::from_slice(&manifest).ok()?;
    parsed.get("version")?.as_str().map(str::to_string)
}

/// Version of the signed XPI the app can deliver to Firefox (None = nothing to offer).
pub fn latest_firefox_version() -> Option<String> {
    signed_xpi_path().and_then(|p| xpi_manifest_version(&p))
}

pub fn update_manifest_json() -> serde_json::Value {
    let updates: Vec<serde_json::Value> = latest_firefox_version()
        .map(|v| {
            vec![serde_json::json!({
                "version": v,
                "update_link": format!("https://127.0.0.1:{UPDATE_PORT}/extension/chronos.xpi"),
            })]
        })
        .unwrap_or_default();
    serde_json::json!({ "addons": { FIREFOX_ADDON_ID: { "updates": updates } } })
}

pub async fn run_firefox_update_server(ca_dir: PathBuf) -> Result<(), String> {
    let ca = crate::proxy::CertAuthority::load_or_create(&ca_dir)?;
    let tls = ca.server_config_for_host("127.0.0.1")?;
    let acceptor = tokio_rustls::TlsAcceptor::from(tls);
    let bind = format!("127.0.0.1:{UPDATE_PORT}");
    let listener = TcpListener::bind(&bind)
        .await
        .map_err(|e| format!("Failed binding Firefox update server on {bind}: {e}"))?;
    loop {
        let Ok((tcp, _)) = listener.accept().await else {
            continue;
        };
        let acceptor = acceptor.clone();
        tokio::spawn(async move {
            let Ok(mut stream) = acceptor.accept(tcp).await else {
                return;
            };
            let Ok(Some(req)) = crate::proxy::read_http_head(&mut stream).await else {
                return;
            };
            let path = req.target_or_reason.split('?').next().unwrap_or("").to_string();
            eprintln!("chronos firefox update: GET {}", req.target_or_reason);
            let _ = match path.as_str() {
                "/extension/firefox-updates.json" => {
                    let body = update_manifest_json().to_string();
                    crate::proxy::send_simple_response(&mut stream, "200 OK", "application/json", &[], body.as_bytes()).await
                }
                "/extension/chronos.xpi" => match signed_xpi_path().and_then(|p| std::fs::read(p).ok()) {
                    Some(bytes) => {
                        crate::proxy::send_simple_response(
                            &mut stream,
                            "200 OK",
                            "application/x-xpinstall",
                            &[],
                            &bytes,
                        )
                        .await
                    }
                    None => crate::proxy::send_simple_response(&mut stream, "404 Not Found", "text/plain", &[], b"no signed xpi").await,
                },
                _ => crate::proxy::send_simple_response(&mut stream, "404 Not Found", "text/plain", &[], b"").await,
            };
            let _ = stream.shutdown().await;
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manifest_has_addon_and_no_unsigned_updates() {
        let m = update_manifest_json();
        assert!(m["addons"][FIREFOX_ADDON_ID]["updates"].is_array());
        let tmp = std::env::temp_dir().join(format!("chronos_unsigned_{}.xpi", std::process::id()));
        std::fs::write(&tmp, b"PK\x03\x04 not signed").unwrap();
        assert!(!xpi_is_signed(&tmp));
        let _ = std::fs::remove_file(tmp);
        // A real signed XPI on this machine (if any) exposes its version.
        let dev = crate::profile::data_dir().join("chronos-signed.xpi");
        if dev.is_file() {
            assert!(xpi_manifest_version(&dev).is_some(), "version readable from signed XPI (data descriptors)");
        }
    }
}
