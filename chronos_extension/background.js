// Chronos Focus Engine - Background Service Worker (Chromium MV3, v1.1.0)
importScripts("focus_filters_core.js");

const CHRONOS_SERVER_URL = "http://127.0.0.1:4545";
const core = globalThis.ChronosFocusCore;

const DEFAULT_FOCUS_FILTERS = {
  ytBlockShorts: true,
  ytEducationalMode: false,
  ytBlockSidebar: false,
  ytBlockComments: false,
  igBlockReels: true,
  igBlockFeed: false,
  igBlockComments: false,
  ttBlockFeed: true,
  rdBlockFeed: false,
  rdBlockComments: false,
  twBlockFeed: false,
  twBlockTrends: false,
  liBlockFeed: false,
  globalGrayscale: false,
  globalBlockNotifications: false,
  hudAlpha: 0.94,
  hudScale: 1.0,
  hudHideToEye: true,
  launcherFilterEnabled: true,
  launcherBlockedTags: [],
  launcherBlockedNames: [],
};

let cachedSites = [];
let isConnected = false;
let antiCheatActive = false;
let antiCheatMode = "OFF";
let cachedFocusFilters = null;
let cachedTagDisplayMap = {};
let cachedPrimaryLanguage = "pt-BR";
let lastServerRevision = "";
let filterRevision = 0;
let isStorageHydrated = false;
let sseRunning = false;
let sseAbortController = null;
let sseReconnectTimer = null;
const injectedCssByTab = new Map();
const cssStorage = chrome.storage.session || chrome.storage.local;

let storageHydratedResolve;
const storageHydrated = new Promise((resolve) => {
  storageHydratedResolve = resolve;
});

async function syncCssToTab(tab) {
  await storageHydrated;
  const activeFilters = cachedFocusFilters || DEFAULT_FOCUS_FILTERS;
  if (!tab || !tab.id || !tab.url || !tab.url.startsWith("http") || !activeFilters || !core) {
    return;
  }
  try {
    const parsed = new URL(tab.url);
    if (parsed.hostname === "127.0.0.1" || parsed.hostname === "localhost") return;

    const nextCss = core.buildFocusCss(activeFilters, parsed.hostname, parsed.pathname);
    const storageKey = `chronos_tab_css_${tab.id}`;
    cssStorage.get([storageKey], (stored) => {
      const prevCss = injectedCssByTab.get(tab.id) || (stored && stored[storageKey]) || "";
      if (nextCss === prevCss && injectedCssByTab.get(tab.id) === nextCss) return;

      if (chrome.scripting && chrome.scripting.insertCSS) {
        const done = () => {
          if (nextCss) {
            chrome.scripting
              .insertCSS({
                target: { tabId: tab.id },
                css: nextCss,
                origin: "USER",
              })
              .then(() => {
                injectedCssByTab.set(tab.id, nextCss);
                cssStorage.set({ [storageKey]: nextCss });
              })
              .catch(() => {});
          } else {
            injectedCssByTab.delete(tab.id);
            cssStorage.remove([storageKey]);
          }
        };

        if (prevCss) {
          chrome.scripting
            .removeCSS({
              target: { tabId: tab.id },
              css: prevCss,
              origin: "USER",
            })
            .then(done)
            .catch(done);
        } else {
          done();
        }
      }
    });
  } catch (_) {}
}

function broadcastFocusFilters(filters) {
  if (!filters) return;
  try {
    chrome.tabs.query({}, (tabs) => {
      if (chrome.runtime.lastError || !tabs) return;
      for (const tab of tabs) {
        if (!tab.id) continue;
        syncCssToTab(tab);
        chrome.tabs
          .sendMessage(tab.id, {
            type: "FOCUS_FILTERS_UPDATED",
            filters,
            tagDisplayMap: cachedTagDisplayMap,
            primaryLanguage: cachedPrimaryLanguage,
            antiCheatActive,
            antiCheatMode,
            revision: filterRevision,
          })
          .catch(() => {});
      }
    });
  } catch (_) {}
}

function broadcastStatePush() {
  try {
    const res = chrome.runtime.sendMessage({
      type: "CHRONOS_STATE_PUSH",
      isConnected,
      antiCheatActive,
      antiCheatMode,
      sites: cachedSites,
      focusFilters: cachedFocusFilters || DEFAULT_FOCUS_FILTERS,
      tagDisplayMap: cachedTagDisplayMap,
      primaryLanguage: cachedPrimaryLanguage,
      revision: filterRevision,
    });
    if (res && typeof res.catch === "function") res.catch(() => {});
  } catch (_) {}
}

const browserAction = chrome.action || chrome.browserAction;

chrome.storage.local.get(
  [
    "cachedSites",
    "isConnected",
    "focusFilters",
    "tagDisplayMap",
    "primaryLanguage",
    "filterRevision",
    "antiCheatActive",
    "antiCheatMode",
  ],
  (result) => {
    if (result && Array.isArray(result.cachedSites)) {
      cachedSites = result.cachedSites;
      isConnected = !!result.isConnected;
    }
    if (result && result.focusFilters) {
      cachedFocusFilters = result.focusFilters;
      filterRevision = typeof result.filterRevision === "number" ? result.filterRevision : 1;
    }
    if (result && result.tagDisplayMap && typeof result.tagDisplayMap === "object") {
      cachedTagDisplayMap = result.tagDisplayMap;
    }
    if (result && typeof result.primaryLanguage === "string" && result.primaryLanguage) {
      cachedPrimaryLanguage = result.primaryLanguage;
    }
    if (result && typeof result.antiCheatActive === "boolean") {
      antiCheatActive = result.antiCheatActive;
    }
    if (result && typeof result.antiCheatMode === "string") {
      antiCheatMode = result.antiCheatMode;
    }
    isStorageHydrated = true;
    if (storageHydratedResolve) storageHydratedResolve();
    syncWithChronos();
    startSseStream();
  }
);

function getActiveTabInfo() {
  return new Promise((resolve) => {
    try {
      if (chrome.windows && chrome.windows.getLastFocused) {
        chrome.windows.getLastFocused({ populate: false }, (win) => {
          const isWindowFocused = !!(win && win.focused);
          chrome.tabs.query({}, (tabs) => {
            if (chrome.runtime.lastError || !tabs) {
              resolve({ url: "", title: "", audibleUrl: "", audibleTitle: "" });
              return;
            }
            const focusedActiveTab = isWindowFocused
              ? tabs.find((t) => t.active && t.windowId === win.id)
              : null;
            const audibleTab = tabs.find((t) => t.audible);
            resolve({
              url: focusedActiveTab ? focusedActiveTab.url || "" : "",
              title: focusedActiveTab ? focusedActiveTab.title || "" : "",
              audibleUrl: audibleTab ? audibleTab.url || "" : "",
              audibleTitle: audibleTab ? audibleTab.title || "" : "",
            });
          });
        });
      } else {
        chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
          if (chrome.runtime.lastError || !tabs || tabs.length === 0) {
            resolve({ url: "", title: "", audibleUrl: "", audibleTitle: "" });
            return;
          }
          const activeTab = tabs[0];
          chrome.tabs.query({ audible: true }, (audibleTabs) => {
            const audibleTab = audibleTabs && audibleTabs.length > 0 ? audibleTabs[0] : null;
            resolve({
              url: activeTab ? activeTab.url || "" : "",
              title: activeTab ? activeTab.title || "" : "",
              audibleUrl: audibleTab ? audibleTab.url || "" : "",
              audibleTitle: audibleTab ? audibleTab.title || "" : "",
            });
          });
        });
      }
    } catch (_) {
      resolve({ url: "", title: "", audibleUrl: "", audibleTitle: "" });
    }
  });
}

const KNOWN_APP_DOMAINS = {
  youtube: ["youtube.com", "m.youtube.com", "youtu.be"],
  instagram: ["instagram.com"],
  tiktok: ["tiktok.com"],
  reddit: ["reddit.com"],
  twitter: ["twitter.com", "x.com"],
  x: ["x.com", "twitter.com"],
  facebook: ["facebook.com"],
  twitch: ["twitch.tv"],
  discord: ["discord.com"],
  netflix: ["netflix.com"],
  spotify: ["open.spotify.com", "spotify.com"],
  whatsapp: ["web.whatsapp.com"],
  telegram: ["web.telegram.org"],
};

function extractSitePatterns(site) {
  const result = new Set();
  const raw = (site.pattern || "").trim();

  if (raw.startsWith("{")) {
    try {
      const parsed = JSON.parse(raw);
      if (parsed && Array.isArray(parsed.sites)) {
        for (const s of parsed.sites) {
          const clean = String(s).trim().toLowerCase();
          if (clean) result.add(clean);
        }
      }
      if (parsed && Array.isArray(parsed.apps)) {
        for (const app of parsed.apps) {
          const appName = String(app.name || "").trim().toLowerCase();
          const appExec = String(app.exec || "").trim().toLowerCase();
          for (const key of Object.keys(KNOWN_APP_DOMAINS)) {
            if (appName.includes(key) || appExec.includes(key)) {
              for (const dom of KNOWN_APP_DOMAINS[key]) {
                result.add(dom);
              }
            }
          }
        }
      }
      return Array.from(result);
    } catch (_) {
      return [];
    }
  }

  const type = (site.targetType || "SITE").toUpperCase();
  if (type === "APP") {
    const lowerName = String(site.displayName || site.entityId || "").toLowerCase();
    for (const key of Object.keys(KNOWN_APP_DOMAINS)) {
      if (lowerName.includes(key)) {
        return KNOWN_APP_DOMAINS[key];
      }
    }
    return [];
  }

  const list = raw
    .split(",")
    .map((p) => p.trim().toLowerCase())
    .filter(Boolean);
  if (list.length === 0 && site.entityId) {
    list.push(site.entityId.toLowerCase());
  }
  return list;
}

function scheduleSseReconnect(delayMs = 2000) {
  if (sseReconnectTimer) return;
  sseReconnectTimer = setTimeout(() => {
    sseReconnectTimer = null;
    startSseStream();
  }, delayMs);
}

function handleSseEventBlock(rawBlock) {
  const lines = String(rawBlock || "").split("\n");
  let eventName = "message";
  const dataParts = [];
  for (const line of lines) {
    if (!line || line.startsWith(":")) continue;
    if (line.startsWith("event:")) {
      eventName = line.slice(6).trim();
    } else if (line.startsWith("data:")) {
      dataParts.push(line.slice(5).trim());
    }
  }
  if (!dataParts.length) return;
  try {
    const data = JSON.parse(dataParts.join("\n"));
    if (eventName === "chronos_update" && data && typeof data === "object") {
      let changed = false;
      if (typeof data.antiCheatActive === "boolean") {
        if (antiCheatActive !== data.antiCheatActive) {
          changed = true;
        }
        antiCheatActive = data.antiCheatActive;
      }
      if (typeof data.antiCheatMode === "string" && data.antiCheatMode) {
        if (antiCheatMode !== data.antiCheatMode) {
          changed = true;
        }
        antiCheatMode = data.antiCheatMode;
      }
      if (data.tagDisplayMap && typeof data.tagDisplayMap === "object") {
        cachedTagDisplayMap = data.tagDisplayMap;
        changed = true;
      }
      if (typeof data.primaryLanguage === "string" && data.primaryLanguage) {
        cachedPrimaryLanguage = data.primaryLanguage;
      }
      if (data.focusFilters) {
        const nextJson = JSON.stringify(data.focusFilters);
        const prevJson = JSON.stringify(cachedFocusFilters);
        if (nextJson !== prevJson) {
          filterRevision += 1;
          changed = true;
        }
        cachedFocusFilters = data.focusFilters;
      }
      if (data.revision && data.revision !== lastServerRevision) {
        lastServerRevision = String(data.revision);
        filterRevision += 1;
        changed = true;
      }
      isConnected = true;
      chrome.storage.local.set({
        isConnected: true,
        antiCheatActive,
        antiCheatMode,
        focusFilters: cachedFocusFilters,
        tagDisplayMap: cachedTagDisplayMap,
        primaryLanguage: cachedPrimaryLanguage,
        filterRevision,
      });
      if (changed) {
        broadcastFocusFilters(cachedFocusFilters);
        broadcastStatePush();
        syncWithChronos();
      }
    }
  } catch (_) {}
}

async function startSseStream() {
  if (sseRunning) return;
  sseRunning = true;
  if (sseAbortController) {
    try {
      sseAbortController.abort();
    } catch (_) {}
  }
  sseAbortController = new AbortController();
  try {
    const resp = await fetch(`${CHRONOS_SERVER_URL}/api/events`, {
      method: "GET",
      headers: { Accept: "text/event-stream" },
      cache: "no-store",
      signal: sseAbortController.signal,
    });
    if (!resp.ok || !resp.body || typeof resp.body.getReader !== "function") {
      throw new Error("SSE stream unavailable");
    }
    const reader = resp.body.getReader();
    const decoder = new TextDecoder("utf-8");
    let buffer = "";
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true }).replace(/\r\n/g, "\n");
      let sepIdx = buffer.indexOf("\n\n");
      while (sepIdx !== -1) {
        const block = buffer.slice(0, sepIdx);
        buffer = buffer.slice(sepIdx + 2);
        handleSseEventBlock(block);
        sepIdx = buffer.indexOf("\n\n");
      }
    }
    sseRunning = false;
    scheduleSseReconnect(800);
  } catch (_) {
    sseRunning = false;
    scheduleSseReconnect(2500);
  }
}

async function syncWithChronos() {
  await storageHydrated;
  if (!sseRunning && !sseReconnectTimer) {
    startSseStream();
  }
  try {
    const activeTab = await getActiveTabInfo();
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 1200);

    const qs = new URLSearchParams();
    if (activeTab.url && activeTab.url.startsWith("http") && !activeTab.url.includes("127.0.0.1:4545")) {
      qs.set("activeUrl", activeTab.url);
      qs.set("activeTitle", activeTab.title || "");
    }
    if (activeTab.audibleUrl && activeTab.audibleUrl.startsWith("http") && !activeTab.audibleUrl.includes("127.0.0.1:4545")) {
      qs.set("audibleUrl", activeTab.audibleUrl);
      qs.set("audibleTitle", activeTab.audibleTitle || "");
    }

    const statusUrl = qs.toString()
      ? `${CHRONOS_SERVER_URL}/api/status?${qs.toString()}`
      : `${CHRONOS_SERVER_URL}/api/status`;

    const resp = await fetch(statusUrl, {
      signal: controller.signal,
    });
    clearTimeout(timeoutId);

    if (resp.ok) {
      const data = await resp.json();
      cachedSites = data.sites || [];
      antiCheatActive = data.antiCheatActive === true;
      antiCheatMode =
        typeof data.antiCheatMode === "string"
          ? data.antiCheatMode
          : antiCheatActive
            ? "CHALLENGE"
            : "OFF";
      if (data.tagDisplayMap && typeof data.tagDisplayMap === "object") {
        cachedTagDisplayMap = data.tagDisplayMap;
      }
      if (typeof data.primaryLanguage === "string" && data.primaryLanguage) {
        cachedPrimaryLanguage = data.primaryLanguage;
      }
      if (data.revision) {
        lastServerRevision = String(data.revision);
      }
      if (data.focusFilters) {
        const nextJson = JSON.stringify(data.focusFilters);
        const prevJson = JSON.stringify(cachedFocusFilters);
        if (nextJson !== prevJson) {
          filterRevision += 1;
        }
        cachedFocusFilters = data.focusFilters;
      }
      isConnected = true;
      chrome.storage.local.set({
        cachedSites,
        isConnected: true,
        antiCheatActive,
        antiCheatMode,
        focusFilters: cachedFocusFilters,
        tagDisplayMap: cachedTagDisplayMap,
        primaryLanguage: cachedPrimaryLanguage,
        filterRevision,
        lastSync: Date.now(),
      });
      broadcastFocusFilters(cachedFocusFilters);
      broadcastStatePush();
      checkOpenTabsAgainstBlockedRules();
      updateBadge();
    }
  } catch (err) {
    isConnected = false;
    if (!cachedFocusFilters) {
      cachedFocusFilters = { ...DEFAULT_FOCUS_FILTERS };
    }
    chrome.storage.local.set({ isConnected: false });
    updateBadge();
  }
}

function matchAnyRule(urlStr, titleStr = "") {
  if (!urlStr || !urlStr.startsWith("http")) return null;

  try {
    const parsed = new URL(urlStr);
    const host = parsed.hostname.toLowerCase();
    const full = urlStr.toLowerCase();
    const titleLower = (titleStr || "").toLowerCase();

    if (host === "127.0.0.1" || host === "localhost") return null;

    for (const site of cachedSites) {
      const patterns = extractSitePatterns(site);
      if (patterns.length === 0) continue;

      for (const pat of patterns) {
        const cleanPat = pat
          .replace("https://", "")
          .replace("http://", "")
          .replace("www.", "")
          .replace(/\/+$/, "");
        if (!cleanPat) continue;

        if (
          host.includes(cleanPat) ||
          full.includes(cleanPat) ||
          (titleLower && titleLower.includes(cleanPat))
        ) {
          return site;
        }
      }
    }
  } catch (_) {}

  return null;
}

function matchBlockedRule(urlStr, titleStr = "") {
  const matched = matchAnyRule(urlStr, titleStr);
  if (!matched) return null;

  const isBlocked =
    matched.isBlocked ||
    (matched.remainingSeconds !== undefined && matched.remainingSeconds <= 0);
  return isBlocked ? matched : null;
}

function updateBadge() {
  if (!browserAction || !browserAction.setBadgeText) return;

  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    if (chrome.runtime.lastError || !tabs || !tabs[0] || !tabs[0].url) {
      browserAction.setBadgeText({ text: "" });
      return;
    }

    const currentTab = tabs[0];
    const matched = matchAnyRule(currentTab.url, currentTab.title);

    if (!matched) {
      browserAction.setBadgeText({ text: "" });
      return;
    }

    const isBlocked =
      matched.isBlocked ||
      (matched.remainingSeconds !== undefined && matched.remainingSeconds <= 0);

    if (isBlocked) {
      browserAction.setBadgeText({ text: "BLOQ" });
      if (browserAction.setBadgeBackgroundColor) {
        browserAction.setBadgeBackgroundColor({ color: "#E53935" });
      }
    } else {
      const rem = matched.remainingSeconds || 0;
      const m = Math.ceil(rem / 60);
      const text = m > 60 ? `${Math.floor(m / 60)}h` : `${m}m`;
      browserAction.setBadgeText({ text });
      if (browserAction.setBadgeBackgroundColor) {
        browserAction.setBadgeBackgroundColor({
          color: m <= 5 ? "#E53935" : m <= 15 ? "#FB8C00" : "#43A047",
        });
      }
    }
  });
}

function redirectToBlockPage(tabId, originalUrl, matchedRule) {
  const blockUrl = `${CHRONOS_SERVER_URL}/blocked?entity=${encodeURIComponent(
    matchedRule.entityId
  )}&site=${encodeURIComponent(
    matchedRule.displayName || matchedRule.entityId
  )}&url=${encodeURIComponent(originalUrl)}`;

  chrome.tabs.update(tabId, { url: blockUrl });
}

const launcherNavInflight = new Set();
let launcherTagMapLoaded = false;

function ensureBackgroundTagMap() {
  if (launcherTagMapLoaded || !core || !core.launcherDomFilter) return;
  launcherTagMapLoaded = true;
  fetch(`${CHRONOS_SERVER_URL}/api/launchers/tags`)
    .then((r) => (r.ok ? r.json() : null))
    .then((data) => {
      if (data && data.tagMap && typeof core.launcherDomFilter.setTagCatalogMap === "function") {
        core.launcherDomFilter.setTagCatalogMap(data.tagMap);
      } else {
        launcherTagMapLoaded = false;
      }
    })
    .catch(() => {
      launcherTagMapLoaded = false;
    });
}

function redirectToLauncherBlockPage(tabId, origUrl, siteLabel, reason) {
  const targetUrl =
    `${CHRONOS_SERVER_URL}/blocked?entity=launcher_filter` +
    `&site=${encodeURIComponent(siteLabel || "Jogo")}` +
    `&reason=${encodeURIComponent(reason || "Conte\u00fado bloqueado por filtro de launcher")}` +
    `&url=${encodeURIComponent(origUrl)}`;
  try {
    const p = chrome.tabs.update(tabId, { url: targetUrl });
    if (p && typeof p.catch === "function") p.catch(() => {});
  } catch (_) {}
}

function checkLauncherNavigationRedirect(tabId, urlStr) {
  if (!cachedFocusFilters || !core || !core.launcherDomFilter || !urlStr) return false;
  if (!cachedFocusFilters.launcherFilterEnabled) return false;
  const hasRules =
    (Array.isArray(cachedFocusFilters.launcherBlockedTags) && cachedFocusFilters.launcherBlockedTags.length > 0) ||
    (Array.isArray(cachedFocusFilters.launcherBlockedNames) && cachedFocusFilters.launcherBlockedNames.length > 0);
  if (!hasRules) return false;

  try {
    const parsed = new URL(urlStr);
    const host = (parsed.hostname || "").toLowerCase();
    const ldf = core.launcherDomFilter;
    if (!ldf.isLauncherStoreHost || !ldf.isLauncherStoreHost(host)) return false;

    ensureBackgroundTagMap();
    const info = ldf.extractPageGameInfo(null, urlStr, host);
    if (!info || !info.isSingleGamePage) return false;

    const localHit = ldf.matchLocalGame(info.title, info.siteTags, cachedFocusFilters);
    if (localHit) {
      redirectToLauncherBlockPage(
        tabId,
        urlStr,
        info.title || (info.siteTags && info.siteTags[0]) || host,
        localHit.reason
      );
      return true;
    }

    if (
      info.appId ||
      info.hasUrlTagHub ||
      (!info.isSearchQuery &&
        info.title &&
        !(ldf.isGenericStorefrontTitle && ldf.isGenericStorefrontTitle(info.title)))
    ) {
      const inflightKey = `${tabId}:${urlStr}`;
      if (launcherNavInflight.has(inflightKey)) return false;
      launcherNavInflight.add(inflightKey);
      fetch(`${CHRONOS_SERVER_URL}/api/launchers/resolve`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        keepalive: true,
        body: JSON.stringify({
          items: [
            {
              id: "nav",
              appId: info.appId,
              url: urlStr,
              title: info.title || "",
              siteTags: info.siteTags || [],
              siteTagIds: info.siteTagIds || [],
              isSingleGamePage: true,
              isSearchQuery: !!info.isSearchQuery,
            },
          ],
        }),
      })
        .then((r) => (r.ok ? r.json() : null))
        .then((resData) => {
          const hit = resData && Array.isArray(resData.results) ? resData.results[0] : null;
          if (hit && hit.blocked) {
            redirectToLauncherBlockPage(
              tabId,
              urlStr,
              hit.title || info.title || host,
              hit.reason || "Filtro de launcher ativo"
            );
          }
        })
        .catch(() => {})
        .finally(() => {
          setTimeout(() => launcherNavInflight.delete(inflightKey), 1500);
        });
    }
  } catch (_) {}
  return false;
}

function redirectIfFilteredRoute(tabId, urlStr) {
  if (!cachedFocusFilters || !core || !urlStr) return false;
  try {
    const parsed = new URL(urlStr);
    const target = core.getRedirectTarget(
      cachedFocusFilters,
      parsed.hostname,
      parsed.pathname,
      parsed.origin
    );
    if (target && target !== urlStr) {
      chrome.tabs.update(tabId, { url: target }).catch(() => {});
      return true;
    }
  } catch (_) {}
  return checkLauncherNavigationRedirect(tabId, urlStr);
}

function checkOpenTabsAgainstBlockedRules() {
  chrome.tabs.query({}, (tabs) => {
    if (!tabs || chrome.runtime.lastError) return;

    for (const tab of tabs) {
      if (!tab.url || !tab.id) continue;
      if (tab.url.includes("127.0.0.1:4545/blocked")) continue;
      if (maybeBlockProtectedBrowserPage(tab.id, tab.url)) continue;

      const matched = matchBlockedRule(tab.url, tab.title);
      if (matched) {
        redirectToBlockPage(tab.id, tab.url, matched);
      } else {
        redirectIfFilteredRoute(tab.id, tab.url);
      }
    }
  });
}

function isExtensionOrSettingsUrl(urlStr) {
  if (!urlStr) return false;
  const lower = urlStr.toLowerCase();
  return (
    lower.startsWith("chrome://extensions") ||
    lower.startsWith("chrome://settings") ||
    lower.startsWith("edge://extensions") ||
    lower.startsWith("about:addons") ||
    lower.startsWith("about:preferences")
  );
}

let inFlightStatusRefresh = null;

function refreshAntiCheatFromServer(timeoutMs = 350) {
  if (inFlightStatusRefresh) return inFlightStatusRefresh;
  inFlightStatusRefresh = (async () => {
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
      const resp = await fetch(`${CHRONOS_SERVER_URL}/api/status`, {
        signal: controller.signal,
      });
      clearTimeout(timeoutId);
      if (resp.ok) {
        const data = await resp.json();
        antiCheatActive = data.antiCheatActive === true;
        antiCheatMode =
          typeof data.antiCheatMode === "string"
            ? data.antiCheatMode
            : antiCheatActive
              ? "CHALLENGE"
              : "OFF";
        isConnected = true;
        chrome.storage.local.set({ antiCheatActive, antiCheatMode, isConnected: true });
      }
    } catch (_) {}
  })().finally(() => {
    inFlightStatusRefresh = null;
  });
  return inFlightStatusRefresh;
}

// Extension/settings pages are only tamper-locked while Anti-Cheat is actively enforced.
function maybeBlockProtectedBrowserPage(tabId, urlStr) {
  if (!antiCheatActive || !isExtensionOrSettingsUrl(urlStr)) return false;
  redirectToBlockPage(tabId, urlStr, {
    entityId: "anti_tamper",
    displayName: "Gerenciador de Extensões Protegido pelo Chronos",
  });
  return true;
}

async function ensureProtectedPageCheck(tabId, urlStr) {
  if (!isExtensionOrSettingsUrl(urlStr)) return false;
  await storageHydrated;
  await refreshAntiCheatFromServer(350);
  return maybeBlockProtectedBrowserPage(tabId, urlStr);
}

chrome.webNavigation.onBeforeNavigate.addListener((details) => {
  if (details.frameId !== 0) return;
  if (details.url.includes("127.0.0.1:4545/blocked")) return;

  if (isExtensionOrSettingsUrl(details.url)) {
    ensureProtectedPageCheck(details.tabId, details.url);
    return;
  }

  const matched = matchBlockedRule(details.url);
  if (matched) {
    redirectToBlockPage(details.tabId, details.url, matched);
    return;
  }

  redirectIfFilteredRoute(details.tabId, details.url);
});

if (chrome.webNavigation.onHistoryStateUpdated) {
  chrome.webNavigation.onHistoryStateUpdated.addListener((details) => {
    if (details.frameId !== 0) return;
    if (details.url.includes("127.0.0.1:4545/blocked")) return;

    syncWithChronos();
    const matched = matchBlockedRule(details.url);
    if (matched) {
      redirectToBlockPage(details.tabId, details.url, matched);
      return;
    }

    if (!redirectIfFilteredRoute(details.tabId, details.url)) {
      chrome.tabs
        .sendMessage(details.tabId, {
          type: "FOCUS_ROUTE_CHANGED",
          url: details.url,
        })
        .catch(() => {});
    }
    updateBadge();
  });
}

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.url && !changeInfo.url.includes("127.0.0.1:4545/blocked")) {
    if (isExtensionOrSettingsUrl(changeInfo.url)) {
      ensureProtectedPageCheck(tabId, changeInfo.url);
      updateBadge();
      return;
    }
    syncWithChronos();
    const matched = matchBlockedRule(changeInfo.url, tab.title);
    if (matched) {
      redirectToBlockPage(tabId, changeInfo.url, matched);
      return;
    }
    redirectIfFilteredRoute(tabId, changeInfo.url);
    syncCssToTab(tab);
  } else if (changeInfo.status === "loading" && tab && tab.url) {
    syncCssToTab(tab);
  }
  updateBadge();
});

chrome.tabs.onActivated.addListener(() => {
  syncWithChronos();
  updateBadge();
});

if (chrome.tabs.onRemoved) {
  chrome.tabs.onRemoved.addListener((tabId) => {
    injectedCssByTab.delete(tabId);
    fetch(`${CHRONOS_SERVER_URL}/api/tab_closed?tabId=${tabId}`).catch(() => {});
    setTimeout(syncWithChronos, 100);
  });
}

if (chrome.windows && chrome.windows.onRemoved) {
  chrome.windows.onRemoved.addListener((windowId) => {
    fetch(`${CHRONOS_SERVER_URL}/api/tab_closed?windowId=${windowId}`).catch(() => {});
    setTimeout(syncWithChronos, 100);
  });
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === "CHECK_URL") {
    if (msg.url && msg.url.startsWith("http") && !msg.url.includes("127.0.0.1:4545")) {
      fetch(
        `${CHRONOS_SERVER_URL}/api/check?url=${encodeURIComponent(
          msg.url
        )}&title=${encodeURIComponent(msg.title || "")}`
      ).catch(() => {});
    }
    storageHydrated.then(() => {
      const anyRule = matchAnyRule(msg.url, msg.title);
      const blockedRule = matchBlockedRule(msg.url, msg.title);
      sendResponse({
        blocked: !!blockedRule,
        rule: blockedRule || anyRule,
        matched: !!anyRule,
        focusFilters: cachedFocusFilters || DEFAULT_FOCUS_FILTERS,
        tagDisplayMap: cachedTagDisplayMap,
        primaryLanguage: cachedPrimaryLanguage,
        revision: filterRevision,
      });
    });
    return true;
  } else if (msg.type === "GET_STATUS") {
    storageHydrated.then(() => {
      sendResponse({
        isConnected,
        antiCheatActive,
        antiCheatMode,
        sites: cachedSites,
        focusFilters: cachedFocusFilters || DEFAULT_FOCUS_FILTERS,
        tagDisplayMap: cachedTagDisplayMap,
        primaryLanguage: cachedPrimaryLanguage,
        revision: filterRevision,
        serverUrl: CHRONOS_SERVER_URL,
      });
    });
    return true;
  } else if (msg.type === "GET_FOCUS_FILTERS") {
    storageHydrated.then(() => {
      if (cachedFocusFilters) {
        sendResponse({
          filters: cachedFocusFilters,
          tagDisplayMap: cachedTagDisplayMap,
          primaryLanguage: cachedPrimaryLanguage,
          antiCheatActive,
          antiCheatMode,
          revision: filterRevision,
        });
        return;
      }
      fetch(`${CHRONOS_SERVER_URL}/api/focus-filters`)
        .then((r) => r.json())
        .then((resData) => {
          if (resData && typeof resData.antiCheatActive === "boolean") {
            antiCheatActive = resData.antiCheatActive;
          }
          if (resData && typeof resData.antiCheatMode === "string" && resData.antiCheatMode) {
            antiCheatMode = resData.antiCheatMode;
          }
          if (resData && resData.focusFilters) {
            cachedFocusFilters = resData.focusFilters;
            if (resData.tagDisplayMap) cachedTagDisplayMap = resData.tagDisplayMap;
            if (resData.primaryLanguage) cachedPrimaryLanguage = resData.primaryLanguage;
            filterRevision += 1;
            chrome.storage.local.set({
              antiCheatActive,
              antiCheatMode,
              focusFilters: cachedFocusFilters,
              tagDisplayMap: cachedTagDisplayMap,
              primaryLanguage: cachedPrimaryLanguage,
              filterRevision,
            });
          }
          sendResponse({
            filters: cachedFocusFilters || DEFAULT_FOCUS_FILTERS,
            tagDisplayMap: cachedTagDisplayMap,
            primaryLanguage: cachedPrimaryLanguage,
            antiCheatActive,
            antiCheatMode,
            revision: filterRevision,
          });
        })
        .catch(() => {
          sendResponse({
            filters: cachedFocusFilters || DEFAULT_FOCUS_FILTERS,
            tagDisplayMap: cachedTagDisplayMap,
            primaryLanguage: cachedPrimaryLanguage,
            antiCheatActive,
            antiCheatMode,
            revision: filterRevision,
          });
        });
    });
    return true;
  } else if (msg.type === "SET_FOCUS_FILTERS") {
    fetch(`${CHRONOS_SERVER_URL}/api/focus-filters`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(msg.filters || {}),
    })
      .then(async (r) => {
        let resData = {};
        try {
          resData = await r.json();
        } catch (_) {}
        const ok = r.ok && resData && resData.success !== false;
        const acLocked = !!(resData && resData.antiCheatLocked) || r.status === 403;
        const prevAcActive = antiCheatActive;
        if (resData && typeof resData.antiCheatActive === "boolean") {
          antiCheatActive = resData.antiCheatActive;
        } else if (acLocked) {
          antiCheatActive = true;
        }
        if (resData && typeof resData.antiCheatMode === "string" && resData.antiCheatMode) {
          antiCheatMode = resData.antiCheatMode;
        }
        if (resData && resData.tagDisplayMap && typeof resData.tagDisplayMap === "object") {
          cachedTagDisplayMap = resData.tagDisplayMap;
        }
        if (resData && typeof resData.primaryLanguage === "string" && resData.primaryLanguage) {
          cachedPrimaryLanguage = resData.primaryLanguage;
        }
        if (resData && resData.focusFilters) {
          cachedFocusFilters = resData.focusFilters;
          filterRevision += 1;
          chrome.storage.local.set({
            antiCheatActive,
            antiCheatMode,
            focusFilters: cachedFocusFilters,
            tagDisplayMap: cachedTagDisplayMap,
            primaryLanguage: cachedPrimaryLanguage,
            filterRevision,
          });
          broadcastFocusFilters(cachedFocusFilters);
          broadcastStatePush();
        } else if (prevAcActive !== antiCheatActive) {
          chrome.storage.local.set({ antiCheatActive, antiCheatMode });
          broadcastFocusFilters(cachedFocusFilters || DEFAULT_FOCUS_FILTERS);
          broadcastStatePush();
        }
        sendResponse({
          success: ok,
          isConnected: true,
          antiCheatActive,
          antiCheatLocked: acLocked,
          message: (resData && (resData.message || resData.error)) || "",
          filters: cachedFocusFilters || DEFAULT_FOCUS_FILTERS,
          tagDisplayMap: cachedTagDisplayMap,
          primaryLanguage: cachedPrimaryLanguage,
          revision: filterRevision,
        });
      })
      .catch((err) => {
        sendResponse({ success: false, isConnected: false, error: err.toString() });
      });
    return true;
  } else if (msg.type === "RESOLVE_LAUNCHER_ITEMS") {
    fetch(`${CHRONOS_SERVER_URL}/api/launchers/resolve`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      keepalive: !!msg.keepalive,
      body: JSON.stringify({ items: Array.isArray(msg.items) ? msg.items : [] }),
    })
      .then((r) => (r.ok ? r.json() : { success: false, results: [] }))
      .then((resData) => sendResponse(resData || { success: false, results: [] }))
      .catch(() => sendResponse({ success: false, results: [] }));
    return true;
  } else if (msg.type === "GET_POPULAR_STEAM_TAGS") {
    const langParam = msg.lang ? `?lang=${encodeURIComponent(msg.lang)}` : "";
    fetch(`${CHRONOS_SERVER_URL}/api/launchers/tags${langParam}`)
      .then((r) => r.json())
      .then((resData) => sendResponse(resData || { tags: [] }))
      .catch(() => sendResponse({ tags: [] }));
    return true;
  } else if (msg.type === "SEARCH_STEAM_AUTOCOMPLETE") {
    const kind = msg.kind === "game" ? "game" : "tag";
    const q = encodeURIComponent(msg.query || "");
    const lang = msg.lang ? `&lang=${encodeURIComponent(msg.lang)}` : "";
    fetch(`${CHRONOS_SERVER_URL}/api/launchers/autocomplete?kind=${kind}&q=${q}${lang}`)
      .then((r) => r.json())
      .then((resData) => sendResponse(resData || { success: false, results: [] }))
      .catch(() => sendResponse({ success: false, results: [] }));
    return true;
  } else if (msg.type === "SET_PRIMARY_LANGUAGE") {
    fetch(`${CHRONOS_SERVER_URL}/api/language`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ primaryLanguage: msg.lang || "pt-BR" }),
    })
      .then((r) => r.json())
      .then(async (resData) => {
        if (resData && resData.primaryLanguage) {
          cachedPrimaryLanguage = resData.primaryLanguage;
        }
        await syncWithChronos();
        sendResponse({
          success: !!(resData && resData.success !== false),
          primaryLanguage: cachedPrimaryLanguage,
          tagDisplayMap: cachedTagDisplayMap,
        });
      })
      .catch((err) => sendResponse({ success: false, error: err.toString() }));
    return true;
  } else if (msg.type === "FORCE_SYNC") {
    syncWithChronos().then(() => {
      sendResponse({
        isConnected,
        antiCheatActive,
        antiCheatMode,
        sites: cachedSites,
        focusFilters: cachedFocusFilters,
        tagDisplayMap: cachedTagDisplayMap,
        primaryLanguage: cachedPrimaryLanguage,
      });
    });
    return true;
  }
  return true;
});

// Self-update: the policy-installed extension points at a local update.xml that Chrome
// only polls every few hours, so new Chronos builds would otherwise run stale code.
function checkForExtensionUpdate() {
  try {
    if (chrome.runtime && chrome.runtime.requestUpdateCheck) {
      chrome.runtime.requestUpdateCheck(() => void chrome.runtime.lastError);
    }
  } catch (_) {}
}
if (chrome.runtime && chrome.runtime.onUpdateAvailable) {
  chrome.runtime.onUpdateAvailable.addListener(() => {
    try {
      chrome.runtime.reload();
    } catch (_) {}
  });
}

chrome.alarms.create("chronos_sync", { periodInMinutes: 0.1 });
chrome.alarms.create("chronos_update_check", { delayInMinutes: 1, periodInMinutes: 10 });
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === "chronos_sync") {
    syncWithChronos();
  } else if (alarm.name === "chronos_update_check") {
    checkForExtensionUpdate();
  }
});
checkForExtensionUpdate();

setInterval(syncWithChronos, 1500);
setInterval(updateBadge, 1000);
syncWithChronos();
