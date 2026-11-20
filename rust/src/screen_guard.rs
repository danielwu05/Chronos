//! Whole-screen +18 detector: every ~2 s the daemon captures the focused window
//! (Hyprland + `grim`, in memory only, never written to disk), runs the local NSFW model
//! ([`crate::nsfw_net`]) and, on a hit, publishes an alert that the app turns into a
//! full-screen cover. The attempt is recorded in the adult filter log.
//!
//! Alert file (`<data>/screen_alert.json`): `{seq, at_ms, kind, name, reason}`; `seq`
//! grows by one per event so the app reacts once. `kind` is `adult` (this detector) or
//! `app` (a blocked app was closed by the engine, see [`publish_app_block`]).

use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use crate::nsfw_net::{self, NsfwNet};

const BASE_INTERVAL: Duration = Duration::from_secs(2);
const MAX_INTERVAL: Duration = Duration::from_secs(8);
/// Longest side of the captured image (enough for a 224 px model input).
const CAPTURE_SIDE: f64 = 448.0;

pub fn alert_path() -> PathBuf {
    crate::profile::data_dir().join("screen_alert.json")
}

fn model_dir() -> Option<PathBuf> {
    let mut candidates = vec![crate::profile::data_dir().join("model")];
    if let Some(dir) = std::env::current_exe().ok().and_then(|p| p.parent().map(|d| d.to_path_buf())) {
        candidates.push(dir.join("data/chronos_assets/chronos_extension/vendor/nsfw_model"));
    }
    candidates.push(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../chronos_extension/vendor/nsfw_model"));
    candidates.into_iter().find(|d| d.join("model.json").is_file())
}

/// Whether the whole-screen detector can run on this desktop (Hyprland + grim).
pub fn supported() -> bool {
    std::env::var("HYPRLAND_INSTANCE_SIGNATURE").is_ok() && which("grim") && which("hyprctl")
}

fn which(bin: &str) -> bool {
    std::env::var("PATH")
        .unwrap_or_default()
        .split(':')
        .any(|d| std::path::Path::new(d).join(bin).is_file())
}

struct ActiveWindow {
    address: String,
    class: String,
    x: i64,
    y: i64,
    w: i64,
    h: i64,
}

fn active_window() -> Option<ActiveWindow> {
    let out = Command::new("hyprctl").args(["activewindow", "-j"]).output().ok()?;
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).ok()?;
    let at = v.get("at")?.as_array()?;
    let size = v.get("size")?.as_array()?;
    let w = ActiveWindow {
        address: v.get("address")?.as_str()?.to_string(),
        class: v.get("class").and_then(|c| c.as_str()).unwrap_or("").to_string(),
        x: at.first()?.as_i64()?,
        y: at.get(1)?.as_i64()?,
        w: size.first()?.as_i64()?,
        h: size.get(1)?.as_i64()?,
    };
    (w.w > 32 && w.h > 32).then_some(w)
}

fn screen_locked() -> bool {
    ["hyprlock", "swaylock", "gtklock"].iter().any(|p| {
        Command::new("pidof").arg(p).stdout(Stdio::null()).status().map(|s| s.success()).unwrap_or(false)
    })
}

/// Captures a window region as 8-bit RGB (width, height, pixels).
fn capture(win: &ActiveWindow) -> Option<(usize, usize, Vec<u8>)> {
    let scale = (CAPTURE_SIDE / win.w.max(win.h) as f64).min(1.0);
    let geometry = format!("{},{} {}x{}", win.x, win.y, win.w, win.h);
    let out = Command::new("grim")
        .args(["-g", &geometry, "-s", &format!("{scale:.4}"), "-t", "ppm", "-"])
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    parse_ppm(&out.stdout)
}

/// Binary PPM (P6, maxval 255) parser.
pub fn parse_ppm(bytes: &[u8]) -> Option<(usize, usize, Vec<u8>)> {
    let mut fields = Vec::new();
    let mut i = 0;
    while fields.len() < 4 && i < bytes.len() {
        if bytes[i] == b'#' {
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
        } else if bytes[i].is_ascii_whitespace() {
            i += 1;
        } else {
            let start = i;
            while i < bytes.len() && !bytes[i].is_ascii_whitespace() {
                i += 1;
            }
            fields.push(std::str::from_utf8(&bytes[start..i]).ok()?.to_string());
        }
    }
    if fields.len() < 4 || fields[0] != "P6" || fields[3] != "255" {
        return None;
    }
    let (w, h): (usize, usize) = (fields[1].parse().ok()?, fields[2].parse().ok()?);
    let data = bytes.get(i + 1..i + 1 + w * h * 3)?.to_vec();
    Some((w, h, data))
}

/// Crops (x, y, w, h) out of an RGB image.
fn crop(rgb: &[u8], width: usize, x: usize, y: usize, w: usize, h: usize) -> Vec<u8> {
    let mut out = Vec::with_capacity(w * h * 3);
    for row in y..y + h {
        let start = (row * width + x) * 3;
        out.extend_from_slice(&rgb[start..start + w * 3]);
    }
    out
}

/// Regions analyzed in a frame: the whole window, plus its two halves (as squares)
/// when it is much wider or taller than it is high, so a photo in one half still fills
/// enough of the model input.
fn regions(w: usize, h: usize) -> Vec<(usize, usize, usize, usize)> {
    let mut r = vec![(0, 0, w, h)];
    if w * 10 > h * 14 {
        r.push((0, 0, h.min(w), h));
        r.push((w - h.min(w), 0, h.min(w), h));
    } else if h * 10 > w * 14 {
        r.push((0, 0, w, w.min(h)));
        r.push((0, h - w.min(h), w, w.min(h)));
    }
    r
}

/// Probability that any region of the frame is +18 (worst region wins).
pub fn classify_frame(net: &NsfwNet, w: usize, h: usize, rgb: &[u8]) -> Option<[f32; 5]> {
    let mut worst: Option<[f32; 5]> = None;
    for (x, y, cw, ch) in regions(w, h) {
        let part = crop(rgb, w, x, y, cw, ch);
        let p = net.classify(&nsfw_net::resize_to_input(&part, cw, ch)).ok()?;
        let score = |p: &[f32; 5]| p[1].max(p[3]).max(p[4] * 0.7);
        if worst.is_none_or(|wst| score(&p) > score(&wst)) {
            worst = Some(p);
        }
        if nsfw_net::is_nsfw(&p) {
            break;
        }
    }
    worst
}

/// Cheap fingerprint of a frame (sampled pixels) to skip unchanged screens.
fn fingerprint(rgb: &[u8]) -> u64 {
    let step = (rgb.len() / 4096).max(1);
    rgb.iter().step_by(step).fold(0xcbf29ce484222325u64, |h, &b| (h ^ (b >> 3) as u64).wrapping_mul(0x100000001b3))
}

fn publish_alert(kind: &str, name: &str, reason: &str) {
    let path = alert_path();
    let prev_seq = std::fs::read_to_string(&path)
        .ok()
        .and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok())
        .and_then(|v| v.get("seq").and_then(|s| s.as_i64()))
        .unwrap_or(0);
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0);
    let body = serde_json::json!({
        "seq": prev_seq + 1,
        "at_ms": now,
        "kind": kind,
        "name": name,
        "reason": reason,
    });
    let tmp = path.with_extension(format!("json.{}.tmp", std::process::id()));
    if std::fs::write(&tmp, body.to_string()).is_ok() {
        let _ = std::fs::rename(&tmp, &path);
    }
}

/// A blocked app was closed: show the block screen (at most every 8 s per app).
pub fn publish_app_block(app_name: &str, reason: &str) {
    static LAST: std::sync::OnceLock<parking_lot::Mutex<std::collections::HashMap<String, Instant>>> =
        std::sync::OnceLock::new();
    {
        let mut last = LAST.get_or_init(Default::default).lock();
        if last.get(app_name).is_some_and(|t| t.elapsed() < Duration::from_secs(8)) {
            return;
        }
        last.insert(app_name.to_string(), Instant::now());
    }
    publish_alert("app", app_name, reason);
}

fn enabled() -> bool {
    let s = crate::adult::settings();
    s.enabled && s.screen_ai
}

/// Runs forever on its own low-priority thread (call once from the daemon).
pub fn spawn() {
    std::thread::Builder::new()
        .name("chronos-screen-guard".into())
        .spawn(|| {
            // Lowest CPU priority for this thread only (Linux renices a TID).
            if let Some(tid) = std::fs::read_link("/proc/thread-self")
                .ok()
                .and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_string()))
            {
                let _ = Command::new("renice")
                    .args(["-n", "19", "-p", &tid])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status();
            }
            run();
        })
        .ok();
}

fn run() {
    let mut net: Option<NsfwNet> = None;
    let mut interval = BASE_INTERVAL;
    let mut last_safe: Option<(String, u64)> = None;
    let mut last_alert: Option<(String, Instant)> = None;
    loop {
        std::thread::sleep(interval);
        if !enabled() || !supported() || screen_locked() {
            continue;
        }
        if net.is_none() {
            match model_dir().map(|d| NsfwNet::load(&d)) {
                Some(Ok(n)) => net = Some(n),
                Some(Err(e)) => {
                    eprintln!("chronos screen guard: model error: {e}");
                    std::thread::sleep(Duration::from_secs(60));
                    continue;
                }
                None => {
                    std::thread::sleep(Duration::from_secs(60));
                    continue;
                }
            }
        }
        let Some(win) = active_window() else { continue };
        if win.class.to_lowercase().contains("chronos") {
            continue; // our own cover / app
        }
        let Some((w, h, rgb)) = capture(&win) else { continue };
        let fp = fingerprint(&rgb);
        if last_safe.as_ref().is_some_and(|(a, f)| *a == win.address && *f == fp) {
            continue;
        }
        let started = Instant::now();
        let verdict = net.as_ref().and_then(|n| classify_frame(n, w, h, &rgb));
        let took = started.elapsed();
        interval = if took > Duration::from_millis(1500) { (interval * 2).min(MAX_INTERVAL) } else { BASE_INTERVAL };
        let Some(p) = verdict else { continue };
        if nsfw_net::is_nsfw(&p) {
            last_safe = None;
            // One alert per window every 3 s at most (the cover takes focus anyway).
            if last_alert.as_ref().is_some_and(|(a, t)| *a == win.address && t.elapsed() < Duration::from_secs(3)) {
                continue;
            }
            last_alert = Some((win.address.clone(), Instant::now()));
            eprintln!("chronos screen guard: +18 on screen ({}) p={:?}", win.class, p);
            crate::adult::log_screen_attempt(&win.class);
            publish_alert("adult", &win.class, "");
        } else {
            last_safe = Some((win.address.clone(), fp));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Live check on this desktop: `cargo test --release -- --ignored live_capture --nocapture`
    #[test]
    #[ignore]
    fn live_capture_and_classify() {
        assert!(supported(), "needs Hyprland + grim");
        let net = NsfwNet::load(&model_dir().expect("model")).expect("load");
        let win = active_window().expect("active window");
        let t = Instant::now();
        let (w, h, rgb) = capture(&win).expect("capture");
        let cap = t.elapsed();
        let p = classify_frame(&net, w, h, &rgb).expect("classify");
        eprintln!("{} {}x{} capture {:?} total {:?} p={:?} nsfw={}", win.class, w, h, cap, t.elapsed(), p, nsfw_net::is_nsfw(&p));
    }

    #[test]
    fn parses_ppm_and_regions() {
        let mut ppm = b"P6\n# grim\n3 2\n255\n".to_vec();
        ppm.extend((0..18).map(|i| i as u8));
        let (w, h, px) = parse_ppm(&ppm).expect("ppm");
        assert_eq!((w, h, px.len()), (3, 2, 18));
        assert_eq!(px[17], 17);
        assert_eq!(crop(&px, 3, 1, 1, 2, 1), vec![12, 13, 14, 15, 16, 17]);
        assert_eq!(regions(1920, 1080).len(), 3);
        assert_eq!(regions(800, 700).len(), 1);
        assert_eq!(regions(1920, 1080)[2], (840, 0, 1080, 1080));
        assert!(parse_ppm(b"P5\n1 1\n255\n\0").is_none());
    }
}
