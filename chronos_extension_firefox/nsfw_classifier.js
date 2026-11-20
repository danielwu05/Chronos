// Chronos - local +18 image classifier (TensorFlow.js + NSFWJS MobileNetV2 model).
// Runs in the Chrome offscreen document (classifier.html) or the Firefox background
// page. Images are fetched by the extension (host permissions), so cross-origin images
// can be read; nothing leaves the computer. Preprocessing matches NSFWJS:
// RGB -> /255 -> bilinear 224x224 -> [1,224,224,3]; classes Drawing, Hentai, Neutral, Porn, Sexy.
(function (g) {
  const MODEL_URL = (g.chrome || g.browser).runtime.getURL("vendor/nsfw_model/model.json");
  let modelPromise = null;

  function loadModel() {
    if (!modelPromise) {
      modelPromise = (async () => {
        const tf = g.tf;
        try {
          await tf.setBackend("webgl");
        } catch (_) {
          await tf.setBackend("cpu");
        }
        await tf.ready();
        return tf.loadLayersModel(MODEL_URL);
      })();
      modelPromise.catch(() => {
        modelPromise = null;
      });
    }
    return modelPromise;
  }

  async function classifyUrl(url) {
    const tf = g.tf;
    const res = await fetch(url, { credentials: "include" });
    if (!res.ok) throw new Error("HTTP " + res.status);
    const blob = await res.blob();
    if (blob.type && !/^image\//i.test(blob.type)) throw new Error("not an image");
    if (/svg/i.test(blob.type || "")) throw new Error("svg");
    const bitmap = await createImageBitmap(blob);
    try {
      if (bitmap.width < 48 || bitmap.height < 48) {
        return { drawing: 0, hentai: 0, neutral: 1, porn: 0, sexy: 0, small: true };
      }
      const model = await loadModel();
      const p = tf.tidy(() => {
        let t = tf.browser.fromPixels(bitmap).toFloat().div(255);
        t = tf.image.resizeBilinear(t, [224, 224], true).reshape([1, 224, 224, 3]);
        return model.predict(t).dataSync();
      });
      return { drawing: p[0], hentai: p[1], neutral: p[2], porn: p[3], sexy: p[4] };
    } finally {
      if (bitmap.close) bitmap.close();
    }
  }

  g.ChronosNsfwClassifier = { classifyUrl, loadModel };
})(globalThis);
