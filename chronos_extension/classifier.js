// Offscreen document (Chrome MV3): answers NSFW_CLASSIFY_OFFSCREEN from the background.
chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (!msg || msg.type !== "NSFW_CLASSIFY_OFFSCREEN") return false;
  globalThis.ChronosNsfwClassifier.classifyUrl(msg.url)
    .then((probs) => sendResponse({ ok: true, probs }))
    .catch((e) => {
      const tf = globalThis.tf;
      const info = ` | tfKeys=${tf ? Object.keys(tf).length : "none"} loadErrors=${JSON.stringify(
        (globalThis.__chronosLoadErrors || []).slice(0, 3)
      )}`;
      sendResponse({ ok: false, error: "offscreen: " + String((e && e.message) || e) + info });
    });
  return true;
});
