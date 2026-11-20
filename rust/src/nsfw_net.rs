//! Local NSFW image classifier: the same NSFWJS MobileNetV2 model the browser extension
//! runs with TF.js, evaluated here in plain Rust (no ML runtime dependency).
//!
//! Model: TF.js "layers" format (`model.json` Keras functional graph + one binary shard
//! of uint8-quantized weights, value = q * scale + min). Supported layers are exactly
//! the ones this model uses: InputLayer, ZeroPadding2D, Conv2D, DepthwiseConv2D,
//! BatchNormalization (folded into scale/shift), ReLU (max 6), Add, AveragePooling2D,
//! Flatten, Dropout (identity) and Dense.
//!
//! Input: RGB in [0,1], 224x224 (bilinear, align corners, like the extension).
//! Output order: Drawing, Hentai, Neutral, Porn, Sexy.

use std::collections::HashMap;
use std::path::Path;

pub const INPUT: usize = 224;
pub const CLASSES: [&str; 5] = ["drawing", "hentai", "neutral", "porn", "sexy"];

/// Feature map in HWC order (Dense outputs are 1x1xC).
#[derive(Clone)]
struct Tensor {
    h: usize,
    w: usize,
    c: usize,
    data: Vec<f32>,
}

impl Tensor {
    fn zeros(h: usize, w: usize, c: usize) -> Self {
        Self { h, w, c, data: vec![0.0; h * w * c] }
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Act {
    Linear,
    Relu,
    Softmax,
}

enum Op {
    Input,
    Pad { top: usize, bottom: usize, left: usize, right: usize },
    Conv { k: Vec<f32>, bias: Option<Vec<f32>>, kh: usize, kw: usize, cin: usize, cout: usize, stride: usize, same: bool, act: Act },
    Depthwise { k: Vec<f32>, bias: Option<Vec<f32>>, kh: usize, kw: usize, c: usize, stride: usize, same: bool, act: Act },
    BatchNorm { scale: Vec<f32>, shift: Vec<f32> },
    Relu { max: f32 },
    Add,
    AvgPool { ph: usize, pw: usize, stride: usize },
    Flatten,
    Identity,
    Dense { k: Vec<f32>, bias: Option<Vec<f32>>, units: usize, act: Act },
}

struct Node {
    name: String,
    op: Op,
    inputs: Vec<String>,
}

pub struct NsfwNet {
    nodes: Vec<Node>,
    output: String,
}

fn act_of(cfg: &serde_json::Value) -> Result<Act, String> {
    match cfg.get("activation").and_then(|a| a.as_str()).unwrap_or("linear") {
        "linear" => Ok(Act::Linear),
        "relu" => Ok(Act::Relu),
        "softmax" => Ok(Act::Softmax),
        other => Err(format!("unsupported activation {other}")),
    }
}

fn usize_at(v: &serde_json::Value, i: usize) -> usize {
    v.get(i).and_then(|x| x.as_u64()).unwrap_or(1) as usize
}

impl NsfwNet {
    /// Loads `model.json` + its weight shard(s) from `dir`.
    pub fn load(dir: &Path) -> Result<Self, String> {
        let model: serde_json::Value = serde_json::from_slice(
            &std::fs::read(dir.join("model.json")).map_err(|e| format!("model.json: {e}"))?,
        )
        .map_err(|e| format!("model.json: {e}"))?;

        // ---- weights
        let mut weights: HashMap<String, Vec<f32>> = HashMap::new();
        for group in model["weightsManifest"].as_array().ok_or("weightsManifest")? {
            let mut bytes = Vec::new();
            for p in group["paths"].as_array().ok_or("paths")? {
                let name = p.as_str().ok_or("path")?;
                if name.contains('/') || name.contains("..") {
                    return Err("invalid shard path".into());
                }
                bytes.extend(std::fs::read(dir.join(name)).map_err(|e| format!("{name}: {e}"))?);
            }
            let mut off = 0usize;
            for w in group["weights"].as_array().ok_or("weights")? {
                let name = w["name"].as_str().ok_or("weight name")?.to_string();
                let n: usize = w["shape"].as_array().ok_or("shape")?.iter().map(|d| d.as_u64().unwrap_or(1) as usize).product();
                let q = &w["quantization"];
                let vals: Vec<f32> = match (w["dtype"].as_str(), q["dtype"].as_str()) {
                    (_, Some("uint8")) => {
                        let (min, scale) = (q["min"].as_f64().unwrap_or(0.0) as f32, q["scale"].as_f64().unwrap_or(1.0) as f32);
                        let raw = bytes.get(off..off + n).ok_or("weights truncated")?;
                        off += n;
                        raw.iter().map(|&b| b as f32 * scale + min).collect()
                    }
                    (Some("float32"), None) => {
                        let raw = bytes.get(off..off + n * 4).ok_or("weights truncated")?;
                        off += n * 4;
                        raw.chunks_exact(4).map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]])).collect()
                    }
                    other => return Err(format!("unsupported weight dtype {other:?}")),
                };
                weights.insert(name, vals);
            }
        }
        let mut take = |layer: &str, kind: &str| -> Result<Vec<f32>, String> {
            weights.remove(&format!("{layer}/{kind}")).ok_or_else(|| format!("missing weight {layer}/{kind}"))
        };

        // ---- graph (Keras lists layers in topological order)
        let cfg = &model["modelTopology"]["model_config"]["config"];
        let output = cfg["output_layers"][0][0].as_str().ok_or("output layer")?.to_string();
        let mut nodes = Vec::new();
        let mut channels: HashMap<String, usize> = HashMap::new();
        for layer in cfg["layers"].as_array().ok_or("layers")? {
            let class = layer["class_name"].as_str().unwrap_or("");
            let c = &layer["config"];
            let name = layer["name"].as_str().or_else(|| c["name"].as_str()).ok_or("layer name")?.to_string();
            let inputs: Vec<String> = layer["inbound_nodes"]
                .get(0)
                .and_then(|n| n.as_array())
                .map(|arr| arr.iter().filter_map(|i| i.get(0).and_then(|s| s.as_str()).map(str::to_string)).collect())
                .unwrap_or_default();
            let in_c = inputs.first().and_then(|i| channels.get(i)).copied().unwrap_or(3);
            let same = c["padding"].as_str() == Some("same");
            let op = match class {
                "InputLayer" => Op::Input,
                "ZeroPadding2D" => {
                    let p = &c["padding"];
                    Op::Pad { top: usize_at(&p[0], 0), bottom: usize_at(&p[0], 1), left: usize_at(&p[1], 0), right: usize_at(&p[1], 1) }
                }
                "Conv2D" => {
                    let cout = c["filters"].as_u64().ok_or("filters")? as usize;
                    let bias = if c["use_bias"].as_bool().unwrap_or(true) { Some(take(&name, "bias")?) } else { None };
                    Op::Conv {
                        k: take(&name, "kernel")?,
                        bias,
                        kh: usize_at(&c["kernel_size"], 0),
                        kw: usize_at(&c["kernel_size"], 1),
                        cin: in_c,
                        cout,
                        stride: usize_at(&c["strides"], 0),
                        same,
                        act: act_of(c)?,
                    }
                }
                "DepthwiseConv2D" => {
                    if c["depth_multiplier"].as_u64().unwrap_or(1) != 1 {
                        return Err("depth_multiplier != 1".into());
                    }
                    let bias = if c["use_bias"].as_bool().unwrap_or(true) { Some(take(&name, "bias")?) } else { None };
                    Op::Depthwise {
                        k: take(&name, "depthwise_kernel")?,
                        bias,
                        kh: usize_at(&c["kernel_size"], 0),
                        kw: usize_at(&c["kernel_size"], 1),
                        c: in_c,
                        stride: usize_at(&c["strides"], 0),
                        same,
                        act: act_of(c)?,
                    }
                }
                "BatchNormalization" => {
                    let eps = c["epsilon"].as_f64().unwrap_or(1e-3) as f32;
                    let gamma = if c["scale"].as_bool().unwrap_or(true) { take(&name, "gamma")? } else { vec![1.0; in_c] };
                    let beta = if c["center"].as_bool().unwrap_or(true) { take(&name, "beta")? } else { vec![0.0; in_c] };
                    let mean = take(&name, "moving_mean")?;
                    let var = take(&name, "moving_variance")?;
                    let scale: Vec<f32> = gamma.iter().zip(&var).map(|(g, v)| g / (v + eps).sqrt()).collect();
                    let shift: Vec<f32> = beta.iter().zip(&mean).zip(&scale).map(|((b, m), s)| b - m * s).collect();
                    Op::BatchNorm { scale, shift }
                }
                "ReLU" => {
                    if c["negative_slope"].as_f64().unwrap_or(0.0) != 0.0 || c["threshold"].as_f64().unwrap_or(0.0) != 0.0 {
                        return Err("unsupported ReLU parameters".into());
                    }
                    Op::Relu { max: c["max_value"].as_f64().map(|m| m as f32).unwrap_or(f32::INFINITY) }
                }
                "Add" => Op::Add,
                "AveragePooling2D" => {
                    if same {
                        return Err("unsupported pooling padding".into());
                    }
                    Op::AvgPool { ph: usize_at(&c["pool_size"], 0), pw: usize_at(&c["pool_size"], 1), stride: usize_at(&c["strides"], 0) }
                }
                "Flatten" => Op::Flatten,
                "Dropout" => Op::Identity,
                "Dense" => {
                    let units = c["units"].as_u64().ok_or("units")? as usize;
                    let bias = if c["use_bias"].as_bool().unwrap_or(true) { Some(take(&name, "bias")?) } else { None };
                    Op::Dense { k: take(&name, "kernel")?, bias, units, act: act_of(c)? }
                }
                other => return Err(format!("unsupported layer {other}")),
            };
            let out_c = match &op {
                Op::Conv { cout, k, kh, kw, .. } => {
                    if k.len() != kh * kw * in_c * cout {
                        return Err(format!("{name}: kernel size mismatch"));
                    }
                    *cout
                }
                Op::Dense { units, .. } => *units,
                Op::Flatten => in_c, // only used after 1x1 pooling here
                _ => in_c,
            };
            channels.insert(name.clone(), out_c);
            nodes.push(Node { name, op, inputs });
        }
        Ok(Self { nodes, output })
    }

    /// Class probabilities for a 224x224 RGB image with values in [0,1] (HWC).
    pub fn classify(&self, rgb: &[f32]) -> Result<[f32; 5], String> {
        if rgb.len() != INPUT * INPUT * 3 {
            return Err("input must be 224x224x3".into());
        }
        let mut values: HashMap<&str, Tensor> = HashMap::new();
        // Number of remaining readers of each value: free feature maps early.
        let mut readers: HashMap<&str, usize> = HashMap::new();
        for n in &self.nodes {
            for i in &n.inputs {
                *readers.entry(i.as_str()).or_default() += 1;
            }
        }
        for n in &self.nodes {
            let get = |values: &HashMap<&str, Tensor>, i: usize| -> Result<Tensor, String> {
                let key = n.inputs.get(i).ok_or_else(|| format!("{}: missing input", n.name))?;
                values.get(key.as_str()).cloned().ok_or_else(|| format!("{}: input {key} not computed", n.name))
            };
            let out = match &n.op {
                Op::Input => Tensor { h: INPUT, w: INPUT, c: 3, data: rgb.to_vec() },
                Op::Identity | Op::Flatten => {
                    let t = get(&values, 0)?;
                    Tensor { h: 1, w: 1, c: t.data.len(), data: t.data }
                }
                Op::Pad { top, bottom, left, right } => pad(&get(&values, 0)?, *top, *bottom, *left, *right),
                Op::Conv { k, bias, kh, kw, cin, cout, stride, same, act } => {
                    conv(&get(&values, 0)?, k, bias.as_deref(), *kh, *kw, *cin, *cout, *stride, *same, *act)
                }
                Op::Depthwise { k, bias, kh, kw, c, stride, same, act } => {
                    depthwise(&get(&values, 0)?, k, bias.as_deref(), *kh, *kw, *c, *stride, *same, *act)
                }
                Op::BatchNorm { scale, shift } => {
                    let mut t = get(&values, 0)?;
                    let c = t.c;
                    for (i, v) in t.data.iter_mut().enumerate() {
                        *v = *v * scale[i % c] + shift[i % c];
                    }
                    t
                }
                Op::Relu { max } => {
                    let mut t = get(&values, 0)?;
                    for v in t.data.iter_mut() {
                        *v = v.clamp(0.0, *max);
                    }
                    t
                }
                Op::Add => {
                    let mut a = get(&values, 0)?;
                    for idx in 1..n.inputs.len() {
                        let b = get(&values, idx)?;
                        if b.data.len() != a.data.len() {
                            return Err(format!("{}: add shape mismatch", n.name));
                        }
                        for (x, y) in a.data.iter_mut().zip(&b.data) {
                            *x += y;
                        }
                    }
                    a
                }
                Op::AvgPool { ph, pw, stride } => avg_pool(&get(&values, 0)?, *ph, *pw, *stride),
                Op::Dense { k, bias, units, act } => {
                    let t = get(&values, 0)?;
                    let inp = t.data.len();
                    if k.len() != inp * units {
                        return Err(format!("{}: dense size mismatch", n.name));
                    }
                    let mut out = bias.clone().unwrap_or_else(|| vec![0.0; *units]);
                    for (i, x) in t.data.iter().enumerate() {
                        let row = &k[i * units..(i + 1) * units];
                        for (o, w) in out.iter_mut().zip(row) {
                            *o += x * w;
                        }
                    }
                    apply_act(&mut out, *act, *units);
                    Tensor { h: 1, w: 1, c: *units, data: out }
                }
            };
            for i in &n.inputs {
                if let Some(r) = readers.get_mut(i.as_str()) {
                    *r -= 1;
                    if *r == 0 && i != &self.output {
                        values.remove(i.as_str());
                    }
                }
            }
            values.insert(n.name.as_str(), out);
        }
        let out = values.get(self.output.as_str()).ok_or("no output")?;
        if out.data.len() != 5 {
            return Err(format!("expected 5 classes, got {}", out.data.len()));
        }
        Ok([out.data[0], out.data[1], out.data[2], out.data[3], out.data[4]])
    }
}

fn apply_act(v: &mut [f32], act: Act, c: usize) {
    match act {
        Act::Linear => {}
        Act::Relu => v.iter_mut().for_each(|x| *x = x.max(0.0)),
        Act::Softmax => {
            for chunk in v.chunks_mut(c) {
                let m = chunk.iter().cloned().fold(f32::NEG_INFINITY, f32::max);
                let mut sum = 0.0;
                for x in chunk.iter_mut() {
                    *x = (*x - m).exp();
                    sum += *x;
                }
                chunk.iter_mut().for_each(|x| *x /= sum);
            }
        }
    }
}

fn pad(t: &Tensor, top: usize, bottom: usize, left: usize, right: usize) -> Tensor {
    let mut o = Tensor::zeros(t.h + top + bottom, t.w + left + right, t.c);
    for y in 0..t.h {
        let src = &t.data[y * t.w * t.c..(y + 1) * t.w * t.c];
        let start = ((y + top) * o.w + left) * t.c;
        o.data[start..start + src.len()].copy_from_slice(src);
    }
    o
}

/// TensorFlow "same"/"valid" geometry: (out size, padding before).
fn geometry(inp: usize, k: usize, stride: usize, same: bool) -> (usize, usize) {
    if same {
        let out = inp.div_ceil(stride);
        let total = ((out - 1) * stride + k).saturating_sub(inp);
        (out, total / 2)
    } else {
        ((inp - k) / stride + 1, 0)
    }
}

#[allow(clippy::too_many_arguments)]
fn conv(t: &Tensor, k: &[f32], bias: Option<&[f32]>, kh: usize, kw: usize, cin: usize, cout: usize, stride: usize, same: bool, act: Act) -> Tensor {
    let (oh, pt) = geometry(t.h, kh, stride, same);
    let (ow, pl) = geometry(t.w, kw, stride, same);
    let mut o = Tensor::zeros(oh, ow, cout);
    for oy in 0..oh {
        for ox in 0..ow {
            let acc = &mut o.data[(oy * ow + ox) * cout..(oy * ow + ox + 1) * cout];
            if let Some(b) = bias {
                acc.copy_from_slice(b);
            }
            for ky in 0..kh {
                let iy = (oy * stride + ky) as isize - pt as isize;
                if iy < 0 || iy >= t.h as isize {
                    continue;
                }
                for kx in 0..kw {
                    let ix = (ox * stride + kx) as isize - pl as isize;
                    if ix < 0 || ix >= t.w as isize {
                        continue;
                    }
                    let px = &t.data[(iy as usize * t.w + ix as usize) * cin..][..cin];
                    let kbase = (ky * kw + kx) * cin * cout;
                    for (ci, &x) in px.iter().enumerate() {
                        if x == 0.0 {
                            continue; // post-ReLU maps are sparse
                        }
                        let row = &k[kbase + ci * cout..kbase + (ci + 1) * cout];
                        for (a, &w) in acc.iter_mut().zip(row) {
                            *a += x * w;
                        }
                    }
                }
            }
        }
    }
    apply_act(&mut o.data, act, cout);
    o
}

#[allow(clippy::too_many_arguments)]
fn depthwise(t: &Tensor, k: &[f32], bias: Option<&[f32]>, kh: usize, kw: usize, c: usize, stride: usize, same: bool, act: Act) -> Tensor {
    let (oh, pt) = geometry(t.h, kh, stride, same);
    let (ow, pl) = geometry(t.w, kw, stride, same);
    let mut o = Tensor::zeros(oh, ow, c);
    for oy in 0..oh {
        for ox in 0..ow {
            let acc = &mut o.data[(oy * ow + ox) * c..(oy * ow + ox + 1) * c];
            if let Some(b) = bias {
                acc.copy_from_slice(b);
            }
            for ky in 0..kh {
                let iy = (oy * stride + ky) as isize - pt as isize;
                if iy < 0 || iy >= t.h as isize {
                    continue;
                }
                for kx in 0..kw {
                    let ix = (ox * stride + kx) as isize - pl as isize;
                    if ix < 0 || ix >= t.w as isize {
                        continue;
                    }
                    let px = &t.data[(iy as usize * t.w + ix as usize) * c..][..c];
                    let kr = &k[(ky * kw + kx) * c..][..c];
                    for ((a, &x), &w) in acc.iter_mut().zip(px).zip(kr) {
                        *a += x * w;
                    }
                }
            }
        }
    }
    apply_act(&mut o.data, act, c);
    o
}

fn avg_pool(t: &Tensor, ph: usize, pw: usize, stride: usize) -> Tensor {
    let oh = (t.h - ph) / stride + 1;
    let ow = (t.w - pw) / stride + 1;
    let mut o = Tensor::zeros(oh, ow, t.c);
    let n = (ph * pw) as f32;
    for oy in 0..oh {
        for ox in 0..ow {
            for y in 0..ph {
                for x in 0..pw {
                    let src = &t.data[((oy * stride + y) * t.w + ox * stride + x) * t.c..][..t.c];
                    let dst = &mut o.data[(oy * ow + ox) * t.c..][..t.c];
                    for (d, s) in dst.iter_mut().zip(src) {
                        *d += s / n;
                    }
                }
            }
        }
    }
    o
}

/// Bilinear resize with align_corners=true (tf.image.resizeBilinear(..., true)) of an
/// 8-bit RGB image, scaled to [0,1].
pub fn resize_to_input(rgb: &[u8], w: usize, h: usize) -> Vec<f32> {
    let mut out = vec![0f32; INPUT * INPUT * 3];
    if w == 0 || h == 0 || rgb.len() < w * h * 3 {
        return out;
    }
    let sy = if INPUT > 1 { (h - 1) as f32 / (INPUT - 1) as f32 } else { 0.0 };
    let sx = if INPUT > 1 { (w - 1) as f32 / (INPUT - 1) as f32 } else { 0.0 };
    for oy in 0..INPUT {
        let fy = oy as f32 * sy;
        let y0 = fy.floor() as usize;
        let y1 = (y0 + 1).min(h - 1);
        let dy = fy - y0 as f32;
        for ox in 0..INPUT {
            let fx = ox as f32 * sx;
            let x0 = fx.floor() as usize;
            let x1 = (x0 + 1).min(w - 1);
            let dx = fx - x0 as f32;
            for ch in 0..3 {
                let p = |y: usize, x: usize| rgb[(y * w + x) * 3 + ch] as f32 / 255.0;
                let top = p(y0, x0) + (p(y0, x1) - p(y0, x0)) * dx;
                let bot = p(y1, x0) + (p(y1, x1) - p(y1, x0)) * dx;
                out[(oy * INPUT + ox) * 3 + ch] = top + (bot - top) * dy;
            }
        }
    }
    out
}

/// Same rule as the extension (`focus_filters_core.isNsfwVerdict`).
pub fn is_nsfw(p: &[f32; 5]) -> bool {
    p[3] >= 0.6 || p[1] >= 0.6 || p[4] >= 0.85
}

#[cfg(test)]
mod tests {
    use super::*;

    fn model_dir() -> std::path::PathBuf {
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../chronos_extension/vendor/nsfw_model")
    }

    #[test]
    fn same_geometry_matches_tensorflow() {
        assert_eq!(geometry(112, 3, 1, true), (112, 1));
        assert_eq!(geometry(113, 3, 2, false), (56, 0));
        assert_eq!(geometry(7, 7, 7, false), (1, 0));
    }

    #[test]
    fn real_model_outputs_probabilities() {
        let dir = model_dir();
        if !dir.join("model.json").is_file() {
            return;
        }
        let net = NsfwNet::load(&dir).expect("model loads");
        // Synthetic image: gradient.
        let mut img = vec![0u8; 300 * 200 * 3];
        for (i, v) in img.iter_mut().enumerate() {
            *v = (i % 251) as u8;
        }
        let input = resize_to_input(&img, 300, 200);
        let t = std::time::Instant::now();
        let p = net.classify(&input).expect("classify");
        eprintln!("nsfw probs {:?} in {:?}", p, t.elapsed());
        let sum: f32 = p.iter().sum();
        assert!((sum - 1.0).abs() < 1e-3, "softmax sums to 1: {sum}");
        assert!(p.iter().all(|x| (0.0..=1.0).contains(x)));
    }
}
