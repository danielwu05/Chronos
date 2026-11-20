// Chronos Focus Engine - Content Script (Multi-Navegador, v1.2.0)
(function () {
  const core = globalThis.ChronosFocusCore;
  const hudFactory = globalThis.ChronosHudPanel;
  let activeFocusFilters = null;
  let activeTagDisplayMap = {};
  let activePrimaryLanguage = "pt-BR";
  let activeAntiCheatActive = false;
  let activeRevision = 0;
  let lastPathSeen = window.location.pathname;
  let styleObserver = null;
  let mountRafPending = false;

  function currentOrigin() {
    try {
      return window.location.origin;
    } catch (_) {
      return `${window.location.protocol}//${window.location.host}`;
    }
  }

  function isEligiblePage() {
    if (window.top !== window.self) return false;
    const href = window.location.href || "";
    if (!href.startsWith("http")) return false;
    const host = (window.location.hostname || "").toLowerCase();
    return host !== "127.0.0.1" && host !== "localhost";
  }

  function ensureStyleTag(cssText) {
    const root = document.documentElement;
    if (!root) return;
    let styleEl = document.getElementById("chronos-focus-filters");
    if (!styleEl) {
      styleEl = document.createElement("style");
      styleEl.id = "chronos-focus-filters";
      (document.head || root).appendChild(styleEl);
    }
    if (styleEl.textContent !== cssText) {
      styleEl.textContent = cssText;
    }
  }

  const hudPanel =
    hudFactory && isEligiblePage()
      ? hudFactory.create({
          source: "extension",
          getHost: () => (window.location.hostname || "").toLowerCase(),
          getInitialFilters: () => activeFocusFilters || {},
          getTagDisplayMap: () => activeTagDisplayMap,
          getPrimaryLanguage: () => activePrimaryLanguage,
          getAntiCheatActive: () => activeAntiCheatActive,
          onApplyFilters: (filters) => {
            applyFocusFilters(
              filters,
              activeRevision,
              activeTagDisplayMap,
              activePrimaryLanguage,
              activeAntiCheatActive
            );
          },
          onSaveFilters: (nextFilters, done) => {
            try {
              chrome.runtime.sendMessage(
                { type: "SET_FOCUS_FILTERS", filters: nextFilters },
                (response) => {
                  if (chrome.runtime.lastError || !response) {
                    done({ success: false, isConnected: false });
                    return;
                  }
                  if (typeof response.revision === "number" && response.revision >= activeRevision) {
                    activeRevision = response.revision;
                  }
                  if (typeof response.antiCheatActive === "boolean") {
                    activeAntiCheatActive = response.antiCheatActive;
                  }
                  if (response.filters) {
                    applyFocusFilters(
                      response.filters,
                      response.revision,
                      response.tagDisplayMap,
                      response.primaryLanguage,
                      response.antiCheatActive
                    );
                  }
                  done({
                    success: !!response.success,
                    filters: response.filters,
                    tagDisplayMap: response.tagDisplayMap,
                    primaryLanguage: response.primaryLanguage,
                    antiCheatActive: !!response.antiCheatActive,
                    antiCheatLocked: !!response.antiCheatLocked,
                    message: response.message || "",
                    isConnected:
                      typeof response.isConnected === "boolean"
                        ? response.isConnected
                        : !!response.success,
                  });
                }
              );
            } catch (_) {
              done({ success: false, isConnected: false });
            }
          },
          onRequestStatus: (done) => {
            try {
              chrome.runtime.sendMessage({ type: "GET_STATUS" }, (response) => {
                if (chrome.runtime.lastError || !response) {
                  done({ isConnected: false });
                  return;
                }
                if (typeof response.revision === "number" && response.revision > activeRevision) {
                  activeRevision = response.revision;
                }
                if (response.tagDisplayMap && typeof response.tagDisplayMap === "object") {
                  activeTagDisplayMap = Object.assign({}, activeTagDisplayMap, response.tagDisplayMap);
                }
                if (typeof response.primaryLanguage === "string" && response.primaryLanguage) {
                  activePrimaryLanguage = response.primaryLanguage;
                }
                if (typeof response.antiCheatActive === "boolean") {
                  activeAntiCheatActive = response.antiCheatActive;
                }
                done({
                  isConnected: !!response.isConnected,
                  antiCheatActive: !!response.antiCheatActive,
                  focusFilters: response.focusFilters,
                  tagDisplayMap: response.tagDisplayMap,
                  primaryLanguage: response.primaryLanguage,
                  sites: response.sites,
                });
              });
            } catch (_) {
              done({ isConnected: false });
            }
          },
          onSearchLauncherAutocomplete: (kind, query, done) => {
            try {
              chrome.runtime.sendMessage(
                {
                  type: "SEARCH_STEAM_AUTOCOMPLETE",
                  kind,
                  query,
                  lang: activePrimaryLanguage,
                },
                (response) => {
                  if (chrome.runtime.lastError || !response) {
                    done({ success: false, results: [] });
                    return;
                  }
                  done(response);
                }
              );
            } catch (_) {
              done({ success: false, results: [] });
            }
          },
          loadPosition: (done) => {
            try {
              if (chrome.storage && chrome.storage.local) {
                chrome.storage.local.get(["chronosHudPos"], (res) => {
                  done(res ? res.chronosHudPos || null : null);
                });
                return;
              }
            } catch (_) {}
            done(null);
          },
          savePosition: (pos) => {
            try {
              if (chrome.storage && chrome.storage.local) {
                if (pos) {
                  chrome.storage.local.set({ chronosHudPos: pos });
                } else {
                  chrome.storage.local.remove(["chronosHudPos"]);
                }
              }
            } catch (_) {}
          },
        })
      : null;

  let launcherFilterTimer = null;
  let launcherTagCatalogLoaded = false;

  function ensureLauncherTagCatalog() {
    if (launcherTagCatalogLoaded) return;
    const launcherFilter = globalThis.ChronosLauncherDomFilter;
    const host = (window.location.hostname || "").toLowerCase();
    if (!launcherFilter || !launcherFilter.isLauncherStoreHost || !launcherFilter.isLauncherStoreHost(host)) {
      return;
    }
    launcherTagCatalogLoaded = true;
    try {
      chrome.runtime.sendMessage({ type: "GET_POPULAR_STEAM_TAGS" }, (res) => {
        if (!chrome.runtime.lastError && res && res.tagMap && typeof launcherFilter.setTagCatalogMap === "function") {
          launcherFilter.setTagCatalogMap(res.tagMap);
          if (activeFocusFilters) runLauncherDomFilter();
        }
      });
    } catch (_) {}
  }

  function runLauncherDomFilter() {
    const launcherFilter = globalThis.ChronosLauncherDomFilter;
    if (!launcherFilter || typeof launcherFilter.apply !== "function" || !activeFocusFilters) return;
    if (!isEligiblePage()) return;
    ensureLauncherTagCatalog();
    launcherFilter.apply(activeFocusFilters, {
      document,
      location: window.location,
      url: window.location.href,
      host: window.location.hostname.toLowerCase(),
      resolveItems: (items, done, metaOpts) => {
        try {
          chrome.runtime.sendMessage(
            {
              type: "RESOLVE_LAUNCHER_ITEMS",
              items,
              keepalive: !!(metaOpts && metaOpts.keepalive),
            },
            (resp) => {
              if (chrome.runtime.lastError || !resp) {
                done({ success: false, results: [] });
                return;
              }
              done(resp);
            }
          );
        } catch (_) {
          done({ success: false, results: [] });
        }
      },
      onBlockPage: (info) => {
        const siteLabel = (info && info.title) || window.location.hostname || "Jogo";
        const reason = (info && info.reason) || "Conte\u00fado bloqueado por filtro de launcher";
        const targetUrl =
          "http://127.0.0.1:4545/blocked?entity=launcher_filter&site=" +
          encodeURIComponent(siteLabel) +
          "&reason=" +
          encodeURIComponent(reason) +
          "&url=" +
          encodeURIComponent((info && info.url) || window.location.href);
        window.location.replace(targetUrl);
      },
    });
  }

  function skipCurrentShort() {
    const nextBtn =
      document.querySelector("#navigation-button-down button") ||
      document.querySelector('button[aria-label*="Next" i], button[aria-label*="Próximo" i]');
    if (nextBtn) {
      nextBtn.click();
      return;
    }
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", code: "ArrowDown", keyCode: 40, bubbles: true }));
  }

  function runYoutubeTypeFilter() {
    const ytFilter = globalThis.ChronosYoutubeTypeFilter;
    if (!ytFilter || typeof ytFilter.apply !== "function" || !activeFocusFilters) return;
    if (!window.location.hostname.toLowerCase().includes("youtube.com")) return;
    ytFilter.apply(activeFocusFilters, {
      document,
      location: window.location,
      classifyItems: (items, done) => {
        try {
          chrome.runtime.sendMessage({ type: "CLASSIFY_YT_VIDEOS", items }, (resp) => {
            done(chrome.runtime.lastError || !resp ? { success: false, results: [] } : resp);
          });
        } catch (_) {
          done({ success: false, results: [] });
        }
      },
      skipShort: skipCurrentShort,
    });
  }

  // Local image AI (+18 images): settings come with the CHECK_URL response.
  let activeAdultFilter = null;
  let imageAiStateSent = "";
  function runImageNsfwFilter() {
    if (!core || !core.imageNsfwFilter || document.visibilityState === "hidden") return;
    const state = `${window.location.hostname} cfg=${JSON.stringify(activeAdultFilter)} imgs=${document.images.length} pending=${
      document.querySelectorAll('img[data-chronos-img="pending"]').length
    }`;
    if (state !== imageAiStateSent && /google|bing|duckduckgo/.test(window.location.hostname)) {
      imageAiStateSent = state;
      try {
        chrome.runtime.sendMessage({ type: "IMAGE_AI_PAGE_STATE", state });
      } catch (_) {}
    }
    core.imageNsfwFilter.apply(activeAdultFilter, {
      document,
      location: window.location,
      classify: (url) =>
        new Promise((resolve) => {
          try {
            chrome.runtime.sendMessage({ type: "CLASSIFY_IMAGE", url }, (resp) => {
              resolve(chrome.runtime.lastError ? null : resp || null);
            });
          } catch (_) {
            resolve(null);
          }
        }),
      onBlockPage: (reason) => {
        try {
          chrome.runtime.sendMessage({ type: "BLOCK_ADULT_PAGE", url: window.location.href, reason, kind: "image" });
        } catch (_) {}
      },
    });
  }

  // +18 posts/pages on Reddit and X (focus filters rdBlockNsfw / twBlockSensitive).
  let adultPageReported = "";
  // X +18 signals from x_sensitive_hook.js (page world, Chromium only).
  const xSensitive = { tweets: new Set(), users: new Set(), communities: new Set() };
  const xTweetCommunity = new Map();
  // Firefox (MV2) has no "world": "MAIN": inject the API hook as a page script
  // (Chromium MV3 loads it through the manifest).
  try {
    const h = window.location.hostname.toLowerCase();
    const mv2 = chrome.runtime.getManifest().manifest_version === 2;
    if (mv2 && (h === "x.com" || h.endsWith(".x.com") || h.includes("twitter.com"))) {
      const s = document.createElement("script");
      s.src = chrome.runtime.getURL("x_sensitive_hook.js");
      s.onload = () => s.remove();
      (document.head || document.documentElement).appendChild(s);
    }
  } catch (_) {}
  window.addEventListener("chronos-x-sensitive", (ev) => {
    try {
      const data = JSON.parse(ev.detail || "{}");
      (data.tweets || []).forEach((t) => xSensitive.tweets.add(String(t)));
      (data.users || []).forEach((u) => xSensitive.users.add(String(u).toLowerCase()));
      (data.communities || []).forEach((c) => xSensitive.communities.add(String(c)));
      (data.tweetCommunities || []).forEach((pair) => {
        if (Array.isArray(pair) && pair.length === 2) xTweetCommunity.set(String(pair[0]), String(pair[1]));
      });
      xTweetCommunity.forEach((comm, tweet) => {
        if (xSensitive.communities.has(comm)) xSensitive.tweets.add(tweet);
      });
      if (xTweetCommunity.size > 5000) xTweetCommunity.clear();
      if (xSensitive.tweets.size > 5000) xSensitive.tweets.clear();
      runAdultSocialFilter();
    } catch (_) {}
  });
  function runAdultSocialFilter() {
    if (!core || typeof core.scanAdultSocial !== "function" || !activeFocusFilters) return;
    const host = window.location.hostname.toLowerCase();
    if (!host.includes("reddit.com") && !host.includes("twitter.com") && host !== "x.com" && !host.endsWith(".x.com")) return;
    let reason = null;
    try {
      reason = core.scanAdultSocial(activeFocusFilters, host, window.location.pathname, document, xSensitive);
    } catch (_) {}
    if (reason && adultPageReported !== window.location.href) {
      adultPageReported = window.location.href;
      try {
        chrome.runtime.sendMessage({ type: "BLOCK_ADULT_PAGE", url: window.location.href, reason });
      } catch (_) {}
    }
  }

  function scheduleLauncherDomFilter() {
    if (launcherFilterTimer) return;
    launcherFilterTimer = setTimeout(() => {
      launcherFilterTimer = null;
      runLauncherDomFilter();
      runYoutubeTypeFilter();
      runAdultSocialFilter();
      runImageNsfwFilter();
    }, 150);
  }

  function applyFocusFilters(filters, rev, nextTagMap, nextLang, nextAntiCheatActive) {
    if (!filters || !core) return;
    if (nextTagMap && typeof nextTagMap === "object") {
      activeTagDisplayMap = Object.assign({}, activeTagDisplayMap, nextTagMap);
    }
    if (typeof nextLang === "string" && nextLang) {
      activePrimaryLanguage = nextLang;
    }
    if (typeof nextAntiCheatActive === "boolean") {
      activeAntiCheatActive = nextAntiCheatActive;
    }
    if (typeof rev === "number" && rev < activeRevision) {
      if (hudPanel) {
        hudPanel.syncFilters(
          null,
          activeTagDisplayMap,
          activePrimaryLanguage,
          activeAntiCheatActive
        );
      }
      return;
    }
    if (typeof rev === "number") activeRevision = rev;

    activeFocusFilters = filters;
    const host = window.location.hostname.toLowerCase();
    const path = window.location.pathname || "/";
    const root = document.documentElement;

    core.syncHtmlAttributes(filters, host, path, root);

    const redirectUrl = core.getRedirectTarget(filters, host, path, currentOrigin());
    if (redirectUrl && redirectUrl !== window.location.href) {
      document.querySelectorAll("video, audio").forEach((m) => {
        try {
          m.pause();
        } catch (_) {}
      });
      window.location.replace(redirectUrl);
      return;
    }

    const css = core.buildFocusCss(filters, host, path);
    ensureStyleTag(css);
    runLauncherDomFilter();
    if (hudPanel) {
      hudPanel.syncFilters(
        filters,
        activeTagDisplayMap,
        activePrimaryLanguage,
        activeAntiCheatActive
      );
    }
  }

  function onRouteChange() {
    lastPathSeen = window.location.pathname;
    checkCurrentPage();
    if (activeFocusFilters) {
      applyFocusFilters(activeFocusFilters, activeRevision);
    }
  }

  function checkCurrentPage() {
    if (!isEligiblePage()) return;
    if (document.visibilityState === "hidden") return;

    const currentUrl = window.location.href;
    const currentTitle = document.title || "";

    try {
      chrome.runtime.sendMessage(
        // Visible tabs in unfocused windows still get block checks, but must not be
        // recorded as the active tab (that would hide the tab really being watched).
        { type: "CHECK_URL", url: currentUrl, title: currentTitle, focused: document.hasFocus() },
        (response) => {
          if (chrome.runtime.lastError || !response) return;

          if (response.blocked && response.rule) {
            const blockUrl = `http://127.0.0.1:4545/blocked?entity=${encodeURIComponent(
              response.rule.entityId
            )}&site=${encodeURIComponent(
              response.rule.displayName || response.rule.entityId
            )}&url=${encodeURIComponent(currentUrl)}`;

            window.location.replace(blockUrl);
            return;
          }

          if (
            response.focusFilters &&
            (activeFocusFilters === null ||
              (typeof response.revision === "number" &&
                response.revision > activeRevision))
          ) {
            applyFocusFilters(
              response.focusFilters,
              response.revision,
              response.tagDisplayMap,
              response.primaryLanguage
            );
          } else if (response.tagDisplayMap || response.primaryLanguage) {
            applyFocusFilters(
              activeFocusFilters,
              activeRevision,
              response.tagDisplayMap,
              response.primaryLanguage
            );
          }

          if (response.adultFilter !== undefined) {
            activeAdultFilter = response.adultFilter;
            runImageNsfwFilter();
          }
          if (hudPanel) {
            hudPanel.updateRule(response.matched && response.rule ? response.rule : null);
          }
        }
      );
    } catch (_) {}
  }

  // Fallback para Firefox MV2 (quando world: MAIN não está no manifest)
  function installFirefoxMainWorldNavHook() {
    try {
      if (typeof window.wrappedJSObject !== "object" || typeof exportFunction !== "function") {
        return;
      }
      const rawHistory = window.wrappedJSObject.history;
      if (!rawHistory || rawHistory.__chronosWrapped) return;
      rawHistory.__chronosWrapped = true;

      for (const method of ["pushState", "replaceState"]) {
        const orig = rawHistory[method];
        if (typeof orig !== "function") continue;
        const wrapped = exportFunction(function () {
          const ret = orig.apply(this, arguments);
          try {
            window.dispatchEvent(new CustomEvent("chronos-route-change"));
          } catch (_) {}
          return ret;
        }, window.wrappedJSObject);
        rawHistory[method] = wrapped;
      }
    } catch (_) {}
  }

  installFirefoxMainWorldNavHook();

  // Inicializa filtros de forma determinística: background autoritativo primeiro
  try {
    chrome.runtime.sendMessage({ type: "GET_FOCUS_FILTERS" }, (response) => {
      if (!chrome.runtime.lastError && response && response.filters) {
        applyFocusFilters(
          response.filters,
          response.revision ?? 0,
          response.tagDisplayMap,
          response.primaryLanguage,
          response.antiCheatActive
        );
      } else if (chrome.storage && chrome.storage.local && activeFocusFilters === null) {
        chrome.storage.local.get(
          ["focusFilters", "tagDisplayMap", "primaryLanguage", "antiCheatActive"],
          (res) => {
            if (activeFocusFilters === null && res && res.focusFilters) {
              applyFocusFilters(
                res.focusFilters,
                0,
                res.tagDisplayMap,
                res.primaryLanguage,
                res.antiCheatActive
              );
            }
          }
        );
      }
    });
  } catch (_) {}

  if (chrome.runtime && chrome.runtime.onMessage) {
    chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
      if (!msg) return;
      if (msg.type === "FOCUS_FILTERS_UPDATED" && msg.filters) {
        applyFocusFilters(
          msg.filters,
          msg.revision,
          msg.tagDisplayMap,
          msg.primaryLanguage,
          msg.antiCheatActive
        );
      } else if (msg.type === "FOCUS_ROUTE_CHANGED") {
        onRouteChange();
      } else if (msg.type === "GET_HUD_STATE" && typeof sendResponse === "function") {
        sendResponse({
          available: !!hudPanel,
          hidden: hudPanel ? hudPanel.isHidden() : false,
        });
      } else if (msg.type === "SET_HUD_HIDDEN" && typeof sendResponse === "function") {
        if (hudPanel) {
          hudPanel.setHidden(!!msg.hidden, { showToast: !!msg.hidden });
        }
        sendResponse({
          available: !!hudPanel,
          hidden: hudPanel ? hudPanel.isHidden() : false,
        });
      } else if (msg.type === "TOGGLE_HUD" && typeof sendResponse === "function") {
        if (hudPanel) {
          const next = !hudPanel.isHidden();
          hudPanel.setHidden(next, { showToast: next });
        }
        sendResponse({
          available: !!hudPanel,
          hidden: hudPanel ? hudPanel.isHidden() : false,
        });
      }
    });
  }

  if (chrome.storage && chrome.storage.onChanged && hudPanel) {
    chrome.storage.onChanged.addListener((changes, areaName) => {
      if (areaName === "local" && changes) {
        if (changes.chronosHudPos) {
          hudPanel.setPosition(changes.chronosHudPos.newValue || null);
        }
        if (changes.antiCheatActive && typeof changes.antiCheatActive.newValue === "boolean") {
          activeAntiCheatActive = changes.antiCheatActive.newValue;
          hudPanel.syncFilters(
            null,
            activeTagDisplayMap,
            activePrimaryLanguage,
            activeAntiCheatActive
          );
        }
      }
    });
  }

  // Re-garante <style> e o HUD flutuante caso a SPA recrie nós durante hidratação inicial
  const targetObserve = document.documentElement;
  if (targetObserve && !styleObserver) {
    styleObserver = new MutationObserver(() => {
      if (activeFocusFilters && !document.getElementById("chronos-focus-filters")) {
        applyFocusFilters(activeFocusFilters, activeRevision);
      }
      if (window.location.pathname !== lastPathSeen) {
        onRouteChange();
      }
      if (activeFocusFilters) {
        scheduleLauncherDomFilter();
      }
      if (hudPanel && !mountRafPending) {
        mountRafPending = true;
        requestAnimationFrame(() => {
          mountRafPending = false;
          hudPanel.ensureMounted();
        });
      }
    });
    styleObserver.observe(targetObserve, { childList: true, subtree: true });
  }

  window.addEventListener("chronos-route-change", onRouteChange);
  window.addEventListener("popstate", onRouteChange);
  window.addEventListener("hashchange", onRouteChange);
  document.addEventListener("yt-navigate-start", onRouteChange);
  document.addEventListener("yt-navigate-finish", onRouteChange);
  document.addEventListener("yt-page-data-updated", onRouteChange);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      checkCurrentPage();
      if (activeFocusFilters) applyFocusFilters(activeFocusFilters, activeRevision);
      if (hudPanel) {
        hudPanel.ensureMounted();
        hudPanel.pollIfPanelOpen();
      }
    }
  });

  if (hudPanel) {
    if (document.readyState === "loading") {
      document.addEventListener(
        "DOMContentLoaded",
        () => {
          hudPanel.ensureMounted();
          runLauncherDomFilter();
        },
        { once: true }
      );
    } else {
      hudPanel.ensureMounted();
      runLauncherDomFilter();
    }
  } else if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => runLauncherDomFilter(), { once: true });
  }

  checkCurrentPage();
  setInterval(() => {
    if (window.location.pathname !== lastPathSeen) {
      onRouteChange();
    } else {
      checkCurrentPage();
      if (activeFocusFilters && document.visibilityState !== "hidden") {
        runLauncherDomFilter();
        runAdultSocialFilter();
      }
      runImageNsfwFilter();
    }
    if (hudPanel) {
      hudPanel.pollIfPanelOpen();
    }
  }, 1500);
})();
