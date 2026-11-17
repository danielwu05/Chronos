//! Signed self-update primitives for Chronos releases published on GitHub.
//!
//! Trust chain: `latest.json` is signed with the release Ed25519 key (private part lives
//! only in the `CHRONOS_UPDATE_SIGNING_KEY` GitHub secret); the manifest pins the SHA-256
//! of every downloadable asset. The app verifies the manifest signature against the
//! public key embedded below, then checks the downloaded archive against the pinned hash.

use std::io::Read;

use ring::signature::{UnparsedPublicKey, ED25519};
use serde::Deserialize;

/// Raw 32-byte Ed25519 public key (base64), printed by `scripts/release-keygen.sh`.
pub const UPDATE_PUBLIC_KEY_B64: &str = "eOeAJxxLfHQ2RSTUzC+hxwzJVXJAkIc+bsnHbSu6P4g=";

#[derive(Debug, Clone)]
pub struct ReleaseAssetDto {
    pub platform: String,
    pub name: String,
    pub sha256: String,
    pub size: i64,
}

#[derive(Debug, Clone)]
pub struct ReleaseManifestDto {
    pub version: String,
    pub published_at: String,
    pub notes: String,
    pub guard_sha256: String,
    pub assets: Vec<ReleaseAssetDto>,
}

#[derive(Deserialize)]
struct RawAsset {
    name: String,
    sha256: String,
    #[serde(default)]
    size: i64,
}

#[derive(Deserialize)]
struct RawManifest {
    version: String,
    #[serde(default)]
    published_at: String,
    #[serde(default)]
    notes: String,
    #[serde(default)]
    guard_sha256: String,
    #[serde(default)]
    assets: std::collections::BTreeMap<String, RawAsset>,
}

fn decode_base64(input: &str) -> Result<Vec<u8>, String> {
    let mut out = Vec::with_capacity(input.len() * 3 / 4);
    let mut buf = 0u32;
    let mut bits = 0u32;
    for c in input.trim().bytes() {
        let v = match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' | b'-' => 62,
            b'/' | b'_' => 63,
            b'=' => break,
            b'\r' | b'\n' | b' ' | b'\t' => continue,
            _ => return Err("Assinatura em base64 inválida".to_string()),
        } as u32;
        buf = (buf << 6) | v;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((buf >> bits) as u8);
            buf &= (1 << bits) - 1;
        }
    }
    Ok(out)
}

fn verify_with_key(manifest_json: &[u8], signature_b64: &str, public_key: &[u8]) -> Result<ReleaseManifestDto, String> {
    let signature = decode_base64(signature_b64)?;
    UnparsedPublicKey::new(&ED25519, public_key)
        .verify(manifest_json, &signature)
        .map_err(|_| "Assinatura da atualização inválida — pacote recusado.".to_string())?;

    let raw: RawManifest =
        serde_json::from_slice(manifest_json).map_err(|e| format!("Manifesto inválido: {e}"))?;
    if raw.version.trim().is_empty() {
        return Err("Manifesto sem versão".to_string());
    }
    let assets = raw
        .assets
        .into_iter()
        .map(|(platform, a)| ReleaseAssetDto {
            platform,
            name: a.name,
            sha256: a.sha256.to_ascii_lowercase(),
            size: a.size,
        })
        .collect();
    Ok(ReleaseManifestDto {
        version: raw.version.trim().trim_start_matches('v').to_string(),
        published_at: raw.published_at,
        notes: raw.notes,
        guard_sha256: raw.guard_sha256.to_ascii_lowercase(),
        assets,
    })
}

/// Verifies `latest.json` (exact bytes) against its detached Ed25519 signature and
/// returns the parsed manifest only when the signature is valid.
pub fn verify_release_manifest(manifest_json: Vec<u8>, signature_b64: String) -> Result<ReleaseManifestDto, String> {
    let key = decode_base64(UPDATE_PUBLIC_KEY_B64)?;
    verify_with_key(&manifest_json, &signature_b64, &key)
}

/// Lowercase hex SHA-256 of a file, streamed in blocks.
pub fn sha256_file(path: String) -> Result<String, String> {
    let mut file = std::fs::File::open(&path).map_err(|e| format!("{path}: {e}"))?;
    let mut ctx = ring::digest::Context::new(&ring::digest::SHA256);
    let mut buf = vec![0u8; 256 * 1024];
    loop {
        let n = file.read(&mut buf).map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        ctx.update(&buf[..n]);
    }
    Ok(ctx
        .finish()
        .as_ref()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect())
}

fn version_key(v: &str) -> Vec<u64> {
    v.trim()
        .trim_start_matches('v')
        .split(['-', '+'])
        .next()
        .unwrap_or("")
        .split('.')
        .map(|n| n.trim().parse::<u64>().unwrap_or(0))
        .collect()
}

/// Semantic-ish version compare: -1 if a < b, 0 if equal, 1 if a > b.
/// Pre-release/build suffixes (`-dev`, `+3`) are ignored for ordering.
#[flutter_rust_bridge::frb(sync)]
pub fn compare_versions(a: String, b: String) -> i32 {
    let (mut ka, mut kb) = (version_key(&a), version_key(&b));
    let len = ka.len().max(kb.len());
    ka.resize(len, 0);
    kb.resize(len, 0);
    match ka.cmp(&kb) {
        std::cmp::Ordering::Less => -1,
        std::cmp::Ordering::Equal => 0,
        std::cmp::Ordering::Greater => 1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ring::signature::{Ed25519KeyPair, KeyPair};

    fn encode_base64(data: &[u8]) -> String {
        const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let mut out = String::new();
        for chunk in data.chunks(3) {
            let b = [chunk[0], *chunk.get(1).unwrap_or(&0), *chunk.get(2).unwrap_or(&0)];
            let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
            for i in 0..4 {
                if i <= chunk.len() {
                    out.push(T[((n >> (18 - 6 * i)) & 63) as usize] as char);
                } else {
                    out.push('=');
                }
            }
        }
        out
    }

    #[test]
    fn test_manifest_signature_hash_and_version_compare() {
        let rng = ring::rand::SystemRandom::new();
        let pkcs8 = Ed25519KeyPair::generate_pkcs8(&rng).unwrap();
        let pair = Ed25519KeyPair::from_pkcs8(pkcs8.as_ref()).unwrap();
        let manifest = br#"{"version":"v1.2.3","notes":"n","guard_sha256":"AB",
            "assets":{"linux-x64":{"name":"chronos-linux-x64-1.2.3.tar.gz","sha256":"DEADbeef","size":10}}}"#;
        let sig = encode_base64(pair.sign(manifest).as_ref());

        let parsed = verify_with_key(manifest, &sig, pair.public_key().as_ref()).expect("valid");
        assert_eq!(parsed.version, "1.2.3");
        assert_eq!(parsed.guard_sha256, "ab");
        assert_eq!(parsed.assets[0].platform, "linux-x64");
        assert_eq!(parsed.assets[0].sha256, "deadbeef");

        let mut tampered = manifest.to_vec();
        tampered[15] ^= 1;
        assert!(verify_with_key(&tampered, &sig, pair.public_key().as_ref()).is_err());

        let other = Ed25519KeyPair::from_pkcs8(Ed25519KeyPair::generate_pkcs8(&rng).unwrap().as_ref()).unwrap();
        assert!(verify_with_key(manifest, &sig, other.public_key().as_ref()).is_err());
        assert!(verify_release_manifest(manifest.to_vec(), sig).is_err(), "embedded key must not accept a foreign signature");

        assert_eq!(decode_base64(UPDATE_PUBLIC_KEY_B64).unwrap().len(), 32);
        // Fixture signed by the real release key (scripts/release-keygen.sh): proves the
        // embedded public key accepts what CI signs with CHRONOS_UPDATE_SIGNING_KEY.
        let real = verify_release_manifest(br#"{"version":"0.0.1","assets":{}}"#.to_vec(), "mY1lN0CCtv6wOTNENo17eFRi3kfvN9do/iyQudobErPiHJ77lwJbAfUzQ2dBQXeS4ufz29D2+ZxT7/ZRrV9RBQ==".to_string())
            .expect("embedded key must verify the real release signature");
        assert_eq!(real.version, "0.0.1");

        let dir = std::env::temp_dir().join(format!("chronos_sha_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let f = dir.join("abc.txt");
        std::fs::write(&f, b"abc").unwrap();
        assert_eq!(
            sha256_file(f.to_string_lossy().to_string()).unwrap(),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        let _ = std::fs::remove_dir_all(dir);

        assert_eq!(compare_versions("1.10.0".into(), "1.9.9".into()), 1);
        assert_eq!(compare_versions("v1.2".into(), "1.2.0".into()), 0);
        assert_eq!(compare_versions("0.0.0-dev".into(), "1.0.0".into()), -1);
        assert_eq!(compare_versions("1.2.3+4".into(), "1.2.4".into()), -1);
    }
}
