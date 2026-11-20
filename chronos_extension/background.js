// Chronos Focus Engine - Background Service Worker (Chromium MV3, v1.1.0)
importScripts("focus_filters_core.js");

const CHRONOS_SERVER_URL = "http://127.0.0.1:4545";
const core = globalThis.ChronosFocusCore;

const DEFAULT_FOCUS_FILTERS = {
  ytBlockShorts: true,
  ytEducationalMode: false,
  ytBlockSidebar: false,
  ytBlockComments: false,
  ytShowOnlyEnabled: false,
  ytShowOnlyTypes: [],
  igBlockReels: true,
  igBlockFeed: false,
  igBlockComments: false,
  ttBlockFeed: true,
  rdBlockFeed: false,
  rdBlockComments: false,
  twBlockFeed: false,
  twBlockTrends: false,
  twBlockSensitive: false,
  rdBlockNsfw: false,
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
let cachedAdultFilter = null;
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
      if (data.adultFilter !== undefined) cachedAdultFilter = data.adultFilter;
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

let cachedReporterId = null;
function getReporterId() {
  if (cachedReporterId) return Promise.resolve(cachedReporterId);
  return new Promise((resolve) => {
    try {
      chrome.storage.local.get(["chronos_reporter_id"], (res) => {
        let id = res && res.chronos_reporter_id;
        if (!id) {
          id = Math.random().toString(36).slice(2) + Date.now().toString(36);
          chrome.storage.local.set({ chronos_reporter_id: id });
        }
        cachedReporterId = id;
        resolve(id);
      });
    } catch (_) {
      cachedReporterId = cachedReporterId || "unknown";
      resolve(cachedReporterId);
    }
  });
}

// Which browser this extension runs in (the app opens the incognito permission page
// only where it is missing).
function detectBrowserName() {
  try {
    if (typeof browser !== "undefined" && browser.runtime && browser.runtime.getBrowserInfo) return "firefox";
    if (navigator.brave) return "brave";
    const ua = navigator.userAgent || "";
    if (/Edg\//.test(ua)) return "edge";
    if (/OPR\//.test(ua)) return "opera";
    if (/Vivaldi/.test(ua)) return "vivaldi";
    const brands = (navigator.userAgentData && navigator.userAgentData.brands) || [];
    if (brands.some((b) => /Google Chrome/.test(b.brand))) return "chrome";
    if (brands.some((b) => /Chromium/.test(b.brand))) return "chromium";
    if (/Firefox\//.test(ua)) return "firefox";
  } catch (_) {}
  return "chromium";
}

async function isIncognitoAllowed() {
  try {
    const api = typeof browser !== "undefined" && browser.extension ? browser.extension : chrome.extension;
    if (!api || typeof api.isAllowedIncognitoAccess !== "function") return null;
    const res = api.isAllowedIncognitoAccess();
    if (res && typeof res.then === "function") return !!(await res);
    return await new Promise((resolve) => api.isAllowedIncognitoAccess((v) => resolve(!!v)));
  } catch (_) {
    return null;
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
    // Identifies this browser so another browser's "nothing playing" report cannot erase
    // the tab playing audio here.
    qs.set("reporter", await getReporterId());
    // Incognito stays available only while this extension may run there (Chronos
    // re-blocks incognito when the permission is turned off).
    const incognitoAllowed = await isIncognitoAllowed();
    if (incognitoAllowed !== null) qs.set("incognito", incognitoAllowed ? "1" : "0");
    // Browser + installed version: the app shows the real version per browser.
    qs.set("browser", detectBrowserName());
    qs.set("ver", chrome.runtime.getManifest().version);
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
      if (data.adultFilter !== undefined) cachedAdultFilter = data.adultFilter;
      maybeUpdateExtension(data.extensionUpdate);
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

function maybeBlockProtectedBrowserPage(tabId, urlStr) {
  // Extension/settings pages are no longer blocked (not even with anti-cheat on): the
  // policy-installed extension cannot be removed, and turning its incognito access off
  // re-locks incognito. Kept as a hook (tests check it exists).
  void tabId;
  void urlStr;
  void antiCheatActive;
  return false;
}

async function ensureProtectedPageCheck(tabId, urlStr) {
  if (!isExtensionOrSettingsUrl(urlStr)) return false;
  await storageHydrated;
  await refreshAntiCheatFromServer(350);
  return maybeBlockProtectedBrowserPage(tabId, urlStr);
}

// Adult filter + SafeSearch are decided by the Chronos daemon (`/api/check`), so a
// change in the app applies on the next navigation without waiting for browser policies.
const serverNavCache = new Map();

function applyServerVerdict(tabId, urlStr, data) {
  if (!data || typeof tabId !== "number" || tabId < 0) return false;
  if (data.blocked && data.targetType === "ADULT") {
    let host = "";
    try {
      host = new URL(urlStr).hostname;
    } catch (_) {}
    const targetUrl =
      `${CHRONOS_SERVER_URL}/blocked?entity=adult_filter` +
      `&site=${encodeURIComponent(host || "Site")}` +
      `&reason=${encodeURIComponent(data.reason || "Conte\u00fado adulto bloqueado")}` +
      `&url=${encodeURIComponent(urlStr)}`;
    try {
      const p = chrome.tabs.update(tabId, { url: targetUrl });
      if (p && typeof p.catch === "function") p.catch(() => {});
    } catch (_) {}
    return true;
  }
  if (typeof data.safeSearchRedirect === "string" && data.safeSearchRedirect && data.safeSearchRedirect !== urlStr) {
    try {
      const p = chrome.tabs.update(tabId, { url: data.safeSearchRedirect });
      if (p && typeof p.catch === "function") p.catch(() => {});
    } catch (_) {}
    return true;
  }
  return false;
}

function checkServerNavigation(tabId, urlStr) {
  if (!urlStr || !/^https?:/i.test(urlStr) || urlStr.includes("127.0.0.1:4545")) return;
  const key = `${tabId}|${urlStr}`;
  const now = Date.now();
  const last = serverNavCache.get(key);
  if (last && now - last < 2000) return;
  serverNavCache.set(key, now);
  if (serverNavCache.size > 200) {
    for (const [k, t] of serverNavCache) if (now - t > 2000) serverNavCache.delete(k);
  }
  fetch(`${CHRONOS_SERVER_URL}/api/check?url=${encodeURIComponent(urlStr)}&title=&focused=0`)
    .then((r) => (r.ok ? r.json() : null))
    .then((data) => applyServerVerdict(tabId, urlStr, data))
    .catch(() => {});
}

chrome.webNavigation.onBeforeNavigate.addListener((details) => {
  if (details.frameId !== 0) return;
  if (details.url.includes("127.0.0.1:4545/blocked")) return;

  if (isExtensionOrSettingsUrl(details.url)) {
    ensureProtectedPageCheck(details.tabId, details.url);
    return;
  }

  checkServerNavigation(details.tabId, details.url);
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
    checkServerNavigation(details.tabId, details.url);
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
    checkServerNavigation(tabId, changeInfo.url);
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

// ---------------------------------------------------------------------------
// Local image AI: queue (2 at a time), cache by URL, 8 s timeout. Chrome runs the
// model in an offscreen document; Firefox (MV2) loads it into this background page.
const nsfwCache = new Map();
const NSFW_CACHE_MAX = 3000;
const nsfwQueue = [];
let nsfwActive = 0;
let offscreenCreating = null;
let firefoxClassifierLoading = null;

async function ensureOffscreenClassifier() {
  if (chrome.offscreen.hasDocument && (await chrome.offscreen.hasDocument())) return;
  if (!offscreenCreating) {
    offscreenCreating = chrome.offscreen
      .createDocument({
        url: "classifier.html",
        reasons: ["BLOBS", "LOCAL_STORAGE", "WORKERS"],
        justification: "Classificar imagens localmente para o filtro de conteúdo adulto.",
      })
      .catch((e) => {
        if (!String(e && e.message).includes("single offscreen")) throw e;
      })
      .finally(() => {
        offscreenCreating = null;
      });
  }
  await offscreenCreating;
}

function loadScriptInBackground(src) {
  return new Promise((resolve, reject) => {
    const el = document.createElement("script");
    el.src = src;
    el.onload = resolve;
    el.onerror = reject;
    document.head.appendChild(el);
  });
}

async function ensureFirefoxClassifier() {
  if (globalThis.ChronosNsfwClassifier) return;
  if (!firefoxClassifierLoading) {
    firefoxClassifierLoading = (async () => {
      await loadScriptInBackground("vendor/tf.min.js");
      await loadScriptInBackground("nsfw_classifier.js");
    })().catch((e) => {
      firefoxClassifierLoading = null;
      throw e;
    });
  }
  await firefoxClassifierLoading;
}

async function classifyImageRaw(url) {
  if (chrome.offscreen && chrome.offscreen.createDocument) {
    await ensureOffscreenClassifier();
    return chrome.runtime.sendMessage({ type: "NSFW_CLASSIFY_OFFSCREEN", url });
  }
  await ensureFirefoxClassifier();
  try {
    return { ok: true, probs: await globalThis.ChronosNsfwClassifier.classifyUrl(url) };
  } catch (e) {
    return { ok: false, error: String((e && e.message) || e) };
  }
}

// Diagnostics for the image AI (journal of the Chronos daemon), at most every 20 s.
const nsfwStats = { requests: 0, classified: 0, nsfw: 0, errors: 0, lastError: "", lastProbs: null };
let nsfwDiagAt = 0;
function nsfwDiag(force) {
  const now = Date.now();
  if (!force && now - nsfwDiagAt < 20000) return;
  nsfwDiagAt = now;
  getReporterId()
    .then((rep) =>
      fetch(
        `${CHRONOS_SERVER_URL}/api/ext/diag?reporter=${encodeURIComponent(rep)}&msg=${encodeURIComponent(
          "image-ai " + (chrome.offscreen ? "chrome" : "firefox") + " v" + chrome.runtime.getManifest().version + " " + JSON.stringify(nsfwStats)
        )}`
      )
    )
    .catch(() => {});
}

function classifyImageWithTimeout(url) {
  return Promise.race([
    classifyImageRaw(url)
      .then((r) => r || { ok: false, error: "sem resposta do classificador" })
      .catch((e) => ({ ok: false, error: "raw: " + String((e && e.message) || e) })),
    new Promise((resolve) => setTimeout(() => resolve({ ok: false, timeout: true }), 8000)),
  ]);
}

function pumpNsfwQueue() {
  while (nsfwActive < 2 && nsfwQueue.length) {
    const job = nsfwQueue.shift();
    nsfwActive += 1;
    classifyImageWithTimeout(job.url)
      .then(job.resolve)
      .finally(() => {
        nsfwActive -= 1;
        pumpNsfwQueue();
      });
  }
}

function classifyImageCached(url) {
  if (!url || !/^(https?:|data:image\/)/i.test(url)) return Promise.resolve({ nsfw: false, skipped: true });
  if (nsfwCache.has(url)) return Promise.resolve(nsfwCache.get(url));
  return new Promise((resolve) => {
    nsfwQueue.push({ url, resolve });
    pumpNsfwQueue();
  }).then((res) => {
    nsfwStats.requests += 1;
    if (res && res.ok) {
      nsfwStats.classified += 1;
      nsfwStats.lastProbs = res.probs;
    } else {
      nsfwStats.errors += 1;
      nsfwStats.lastError = String((res && (res.error || (res.timeout ? "timeout" : ""))) || "no response").slice(0, 200);
    }
    const verdict =
      res && res.ok
        ? { nsfw: core.isNsfwVerdict(res.probs), probs: res.probs }
        : { nsfw: false, skipped: true };
    if (verdict.nsfw) nsfwStats.nsfw += 1;
    nsfwDiag(nsfwStats.requests === 1 || nsfwStats.errors === 1);
    if (res && res.ok) {
      nsfwCache.set(url, verdict);
      if (nsfwCache.size > NSFW_CACHE_MAX) nsfwCache.delete(nsfwCache.keys().next().value);
    }
    return verdict;
  });
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === "BLOCK_ADULT_PAGE") {
    const tabId = sender && sender.tab ? sender.tab.id : -1;
    if (msg.url && /^https?:/i.test(msg.url)) {
      fetch(
        `${CHRONOS_SERVER_URL}/api/adult/log?url=${encodeURIComponent(msg.url)}&kind=${encodeURIComponent(msg.kind || "")}`
      ).catch(() => {});
      applyServerVerdict(tabId, msg.url, { blocked: true, targetType: "ADULT", reason: msg.reason || "" });
    }
    return false;
  }
  if (msg.type === "IMAGE_AI_PAGE_STATE") {
    nsfwStats.page = msg.state;
    nsfwDiag(false);
    return false;
  }
  if (msg.type === "CLASSIFY_IMAGE") {
    classifyImageCached(msg.url).then(sendResponse);
    return true;
  }
  if (msg.type === "CHECK_URL") {
    if (msg.url && msg.url.startsWith("http") && !msg.url.includes("127.0.0.1:4545")) {
      const senderTabId = sender && sender.tab ? sender.tab.id : -1;
      fetch(
        `${CHRONOS_SERVER_URL}/api/check?url=${encodeURIComponent(
          msg.url
        )}&title=${encodeURIComponent(msg.title || "")}&focused=${msg.focused === false ? 0 : 1}`
      )
        .then((r) => (r.ok ? r.json() : null))
        .then((data) => applyServerVerdict(senderTabId, msg.url, data))
        .catch(() => {});
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
        adultFilter: cachedAdultFilter,
      });
    });
    return true;
  } else if (msg.type === "GET_STATUS") {
    storageHydrated.then(() => {
      sendResponse({
        isConnected,
        primaryLanguage: cachedPrimaryLanguage,
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
  } else if (msg.type === "GET_YT_TYPES") {
    fetch(`${CHRONOS_SERVER_URL}/api/youtube/types`)
      .then((r) => (r.ok ? r.json() : { success: false, types: [], whitelistTypes: [] }))
      .then((resData) => sendResponse(resData))
      .catch(() => sendResponse({ success: false, types: [], whitelistTypes: [] }));
    return true;
  } else if (msg.type === "CLASSIFY_YT_VIDEOS") {
    fetch(`${CHRONOS_SERVER_URL}/api/youtube/classify`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
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

function compareDottedVersions(a, b) {
  const pa = String(a || "").split(".").map((n) => parseInt(n, 10) || 0);
  const pb = String(b || "").split(".").map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] || 0) - (pb[i] || 0);
    if (d !== 0) return d > 0 ? 1 : -1;
  }
  return 0;
}

// Self-update. Chrome throttles runtime.requestUpdateCheck with a growing backoff every
// time it finds nothing, so blind periodic checks made real updates wait for hours.
// Now we only ask when Chronos announces a newer version (or "update now" is pressed),
// at most every 30 s (persisted across service-worker restarts), and wait 1 min after
// a "throttled" answer. Chrome's own polling is also shortened by the app via
// --extensions-update-frequency in the browser flags file.
let lastExtUpdateNonce = null;
const EXT_UPDATE_MIN_INTERVAL_MS = 30 * 1000;
const EXT_UPDATE_THROTTLED_RETRY_MS = 60 * 1000;

function extDiag(msg) {
  getReporterId()
    .then((rep) =>
      fetch(`${CHRONOS_SERVER_URL}/api/ext/diag?reporter=${encodeURIComponent(rep)}&msg=${encodeURIComponent(msg)}`)
    )
    .catch(() => {});
}

async function maybeUpdateExtension(info) {
  if (!info || typeof info !== "object") return;
  const nonce = String(info.requestNonce || "");
  const forced = lastExtUpdateNonce !== null && nonce && nonce !== lastExtUpdateNonce;
  lastExtUpdateNonce = nonce;
  const current = chrome.runtime.getManifest().version;
  const newer = info.latestVersion && compareDottedVersions(info.latestVersion, current) > 0;
  if (!forced && !(newer && info.autoUpdate !== false)) return;
  let st = {};
  try {
    st = await chrome.storage.local.get(["extUpdateLastAskMs", "extUpdateRetryAtMs"]);
  } catch (_) {}
  const now = Date.now();
  if (!forced && now - (st.extUpdateLastAskMs || 0) < EXT_UPDATE_MIN_INTERVAL_MS) return;
  if (!forced && now < (st.extUpdateRetryAtMs || 0)) return;
  try {
    await chrome.storage.local.set({ extUpdateLastAskMs: now });
  } catch (_) {}
  checkForExtensionUpdate(info.latestVersion || "");
}

function checkForExtensionUpdate(target) {
  if (!chrome.runtime || !chrome.runtime.requestUpdateCheck) return;
  try {
    chrome.runtime.requestUpdateCheck((result, details) => {
      const err = chrome.runtime.lastError;
      const status = (result && typeof result === "object" ? result.status : result) || (err ? "error" : "unknown");
      if (status === "throttled") {
        chrome.storage.local.set({ extUpdateRetryAtMs: Date.now() + EXT_UPDATE_THROTTLED_RETRY_MS }).catch(() => {});
      }
      extDiag(
        `update-check v${chrome.runtime.getManifest().version} -> ${target}: ${status}` +
          (err ? ` (${err.message})` : "") +
          (details && details.version ? ` found ${details.version}` : "")
      );
    });
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
if (chrome.alarms.clear) chrome.alarms.clear("chronos_update_check");
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === "chronos_sync") {
    syncWithChronos();
  }
});

setInterval(syncWithChronos, 1500);
setInterval(updateBadge, 1000);
syncWithChronos();
