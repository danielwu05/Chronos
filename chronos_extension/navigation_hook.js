// Chronos Focus Engine - Main-World SPA Navigation Hook (MV3 world: MAIN)
(function () {
  if (window.__chronosNavHookInstalled) return;
  window.__chronosNavHookInstalled = true;

  function emitRouteChange() {
    try {
      window.dispatchEvent(
        new CustomEvent("chronos-route-change", {
          detail: {
            href: window.location.href,
            pathname: window.location.pathname,
          },
        })
      );
    } catch (_) {}
  }

  function wrapHistory(method) {
    const original = history[method];
    if (typeof original !== "function") return;
    history[method] = function () {
      const result = original.apply(this, arguments);
      emitRouteChange();
      return result;
    };
  }

  wrapHistory("pushState");
  wrapHistory("replaceState");

  window.addEventListener("popstate", emitRouteChange);
  window.addEventListener("hashchange", emitRouteChange);
  document.addEventListener("yt-navigate-start", emitRouteChange, true);
  document.addEventListener("yt-navigate-finish", emitRouteChange, true);
  document.addEventListener("yt-page-data-updated", emitRouteChange, true);
})();
