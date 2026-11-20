// Records script errors while the classifier page loads (reported with failures).
globalThis.__chronosLoadErrors = [];
addEventListener("error", (e) => {
  globalThis.__chronosLoadErrors.push(String((e && e.message) || e) + " @" + ((e && e.filename) || "").split("/").pop() + ":" + ((e && e.lineno) || 0));
});

// tf.min.js bundles regenerator-runtime, which does `regeneratorRuntime = r` and falls back
// to Function("r", ...) (eval, blocked by the MV3 CSP) when the global does not exist.
// Declaring it first keeps TensorFlow.js from aborting while it loads.
if (!("regeneratorRuntime" in globalThis)) globalThis.regeneratorRuntime = undefined;
