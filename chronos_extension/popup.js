document.addEventListener("DOMContentLoaded", () => {
  const statusBadge = document.getElementById("conn-status");
  const container = document.getElementById("sites-container");
  const tabStatusPill = document.getElementById("tab-status-pill");
  const tabUrlText = document.getElementById("tab-url-text");
  const syncBtn = document.getElementById("sync-btn");
  const portLabel = document.getElementById("port-label");
  const toggleHudBtn = document.getElementById("toggle-hud-btn");
  let activeTabIdForHud = null;
  let activeHudHidden = false;
  let lastHudQueriedTabId = null;

  function renderHudToggle(available, hidden) {
    if (!toggleHudBtn) return;
    if (!available) {
      toggleHudBtn.hidden = true;
      return;
    }
    activeHudHidden = !!hidden;
    toggleHudBtn.hidden = false;
    toggleHudBtn.textContent = activeHudHidden
      ? "Mostrar pílula nesta aba"
      : "Esconder pílula nesta aba";
  }

  if (toggleHudBtn) {
    toggleHudBtn.addEventListener("click", () => {
      if (activeTabIdForHud == null) return;
      const nextHidden = !activeHudHidden;
      try {
        chrome.tabs.sendMessage(
          activeTabIdForHud,
          { type: "SET_HUD_HIDDEN", hidden: nextHidden },
          (res) => {
            if (chrome.runtime.lastError || !res) {
              renderHudToggle(false, false);
              return;
            }
            renderHudToggle(!!res.available, !!res.hidden);
          }
        );
      } catch (_) {}
    });
  }

  const fYtShorts = document.getElementById("f-yt-shorts");
  const fYtEdu = document.getElementById("f-yt-edu");
  const fYtSidebar = document.getElementById("f-yt-sidebar");
  const fYtComments = document.getElementById("f-yt-comments");
  const fYtShowOnly = document.getElementById("f-yt-show-only");
  const fYtTypesBox = document.getElementById("f-yt-types");
  const fYtImportWl = document.getElementById("f-yt-import-wl");
  // Selected YouTube content types for "Mostrar apenas" (ids like "educacional").
  let currentShowOnlyTypes = [];
  let ytTypeCatalog = [];
  let ytWhitelistTypes = [];

  function renderYtTypes() {
    if (!fYtTypesBox) return;
    fYtTypesBox.textContent = "";
    const known = ytTypeCatalog.length
      ? ytTypeCatalog
      : currentShowOnlyTypes.map((id) => ({ id, label: id }));
    for (const t of known) {
      const label = document.createElement("label");
      label.style.cssText = "display:flex;align-items:center;gap:3px;cursor:pointer;";
      const cb = document.createElement("input");
      cb.type = "checkbox";
      cb.checked = currentShowOnlyTypes.includes(t.id);
      cb.addEventListener("change", () => {
        currentShowOnlyTypes = cb.checked
          ? Array.from(new Set(currentShowOnlyTypes.concat([t.id])))
          : currentShowOnlyTypes.filter((x) => x !== t.id);
        if (!currentShowOnlyTypes.length && fYtShowOnly) fYtShowOnly.checked = false;
        sendFiltersUpdate();
      });
      label.appendChild(cb);
      label.appendChild(document.createTextNode(t.label));
      fYtTypesBox.appendChild(label);
    }
  }

  function loadYtTypes() {
    try {
      chrome.runtime.sendMessage({ type: "GET_YT_TYPES" }, (resp) => {
        if (chrome.runtime.lastError || !resp) return;
        ytTypeCatalog = Array.isArray(resp.types) ? resp.types : [];
        ytWhitelistTypes = Array.isArray(resp.whitelistTypes) ? resp.whitelistTypes : [];
        renderYtTypes();
      });
    } catch (_) {}
  }
  loadYtTypes();
  if (fYtImportWl) {
    fYtImportWl.addEventListener("click", () => {
      if (!ytWhitelistTypes.length) {
        fYtImportWl.textContent = "Nenhum tipo na Lista Branca";
        setTimeout(() => { fYtImportWl.textContent = "Importar da Lista Branca"; }, 2000);
        return;
      }
      currentShowOnlyTypes = Array.from(new Set(currentShowOnlyTypes.concat(ytWhitelistTypes)));
      renderYtTypes();
      sendFiltersUpdate();
    });
  }

  const fIgReels = document.getElementById("f-ig-reels");
  const fIgFeed = document.getElementById("f-ig-feed");
  const fIgComments = document.getElementById("f-ig-comments");

  const fTtFeed = document.getElementById("f-tt-feed");

  const fRdFeed = document.getElementById("f-rd-feed");
  const fRdComments = document.getElementById("f-rd-comments");

  const fTwFeed = document.getElementById("f-tw-feed");
  const fTwTrends = document.getElementById("f-tw-trends");
  const fRdNsfw = document.getElementById("f-rd-nsfw");
  const fTwSensitive = document.getElementById("f-tw-sensitive");

  const fLiFeed = document.getElementById("f-li-feed");

  const fGrayscale = document.getElementById("f-grayscale");
  const fNotifications = document.getElementById("f-notifications");
  const fHudAlpha = document.getElementById("f-hud-alpha");
  const fHudAlphaVal = document.getElementById("f-hud-alpha-val");
  const fHudScale = document.getElementById("f-hud-scale");
  const fHudScaleVal = document.getElementById("f-hud-scale-val");
  const fHudHideEye = document.getElementById("f-hud-hide-eye");

  const fLauncherEnabled = document.getElementById("f-launcher-enabled");
  const launcherAcWarning = document.getElementById("launcher-ac-warning");
  const fLauncherTagIn = document.getElementById("f-launcher-tag-in");
  const fLauncherTagAdd = document.getElementById("f-launcher-tag-add");
  const fLauncherTagAc = document.getElementById("f-launcher-tag-ac");
  const fLauncherTagChips = document.getElementById("f-launcher-tag-chips");
  const fSteamTagSuggestions = document.getElementById("f-steam-tag-suggestions");
  const fLauncherNameIn = document.getElementById("f-launcher-name-in");
  const fLauncherNameAdd = document.getElementById("f-launcher-name-add");
  const fLauncherNameAc = document.getElementById("f-launcher-name-ac");
  const fLauncherNameChips = document.getElementById("f-launcher-name-chips");
  const tabBtnFilters = document.getElementById("tab-btn-filters");
  const tabBtnSites = document.getElementById("tab-btn-sites");
  const pageFilters = document.getElementById("page-filters");
  const pageSites = document.getElementById("page-sites");
  const sitesCountBadge = document.getElementById("sites-count-badge");

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

  let isUpdatingFiltersUi = false;
  let localSites = [];
  let antiCheatActive = false;
  let lastSavedFilters = null;
  let currentBlockedTags = [];
  let currentBlockedNames = [];
  let popularSteamTags = [];
  let tagDisplayMap = {};
  let primaryLanguage = "pt-BR";

  function setPopupTab(tab) {
    const isSites = tab === "sites";
    if (tabBtnFilters) tabBtnFilters.classList.toggle("is-active", !isSites);
    if (tabBtnSites) tabBtnSites.classList.toggle("is-active", isSites);
    if (pageFilters) pageFilters.classList.toggle("is-hidden", isSites);
    if (pageSites) pageSites.classList.toggle("is-hidden", !isSites);
  }
  if (tabBtnFilters) tabBtnFilters.addEventListener("click", () => setPopupTab("filters"));
  if (tabBtnSites) tabBtnSites.addEventListener("click", () => setPopupTab("sites"));

  function foldTerm(s) {
    return String(s || "")
      .trim()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase();
  }

  function normalizeTermList(arr) {
    if (!Array.isArray(arr)) return [];
    const seen = new Set();
    const out = [];
    for (const raw of arr) {
      const clean = String(raw || "").trim();
      const folded = foldTerm(clean);
      if (!folded || seen.has(folded)) continue;
      seen.add(folded);
      out.push(clean);
    }
    return out;
  }

  function syncAcWarningUi(customMsg) {
    if (!launcherAcWarning) return;
    launcherAcWarning.classList.toggle("is-visible", antiCheatActive);
    launcherAcWarning.textContent =
      customMsg ||
      "🔒 Anti-Burla ativo: desative para remover tags/nomes ou desligar o filtro.";
  }

  function renderChipList(containerEl, list, onRemove, isTag = false) {
    if (!containerEl) return;
    containerEl.textContent = "";
    list.forEach((term) => {
      const chip = document.createElement("span");
      chip.className = "chip";
      const txt = document.createElement("span");
      const displayLabel = isTag && tagDisplayMap[term] ? tagDisplayMap[term] : term;
      txt.textContent =
        isTag && displayLabel.toLowerCase() !== term.toLowerCase()
          ? `${displayLabel} (${term})`
          : displayLabel;
      if (isTag && displayLabel.toLowerCase() !== term.toLowerCase()) {
        chip.title = `Tag canônica Steam API: ${term}`;
      }
      const rmBtn = document.createElement("button");
      rmBtn.type = "button";
      rmBtn.className = "chip-rm";
      rmBtn.textContent = antiCheatActive ? "🔒" : "×";
      rmBtn.title = antiCheatActive ? "Desative o Anti-Burla para remover" : `Remover ${displayLabel}`;
      rmBtn.addEventListener("click", () => {
        if (antiCheatActive) {
          syncAcWarningUi("🔒 Anti-Burla ativo: remoção de tag/nome bloqueada.");
          return;
        }
        onRemove(term);
      });
      chip.appendChild(txt);
      chip.appendChild(rmBtn);
      containerEl.appendChild(chip);
    });
  }

  function renderPopularTagSuggestions() {
    if (!fSteamTagSuggestions) return;
    fSteamTagSuggestions.textContent = "";
    const existing = new Set(currentBlockedTags.map(foldTerm));
    popularSteamTags
      .filter((item) => !existing.has(foldTerm(item.canonicalEn)))
      .slice(0, 8)
      .forEach((item) => {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "tag-suggest-btn";
        btn.textContent = `+ ${item.displayName}`;
        if (item.displayName.toLowerCase() !== item.canonicalEn.toLowerCase()) {
          btn.title = `Envia "${item.canonicalEn}" para a Steam API`;
        }
        btn.addEventListener("click", () => {
          if (item.canonicalEn && item.displayName) {
            tagDisplayMap[item.canonicalEn] = item.displayName;
          }
          currentBlockedTags = normalizeTermList([...currentBlockedTags, item.canonicalEn]);
          renderAllLauncherLists();
          sendFiltersUpdate();
        });
        fSteamTagSuggestions.appendChild(btn);
      });
  }

  function renderAllLauncherLists() {
    renderChipList(
      fLauncherTagChips,
      currentBlockedTags,
      (term) => {
        currentBlockedTags = currentBlockedTags.filter((t) => t !== term);
        renderAllLauncherLists();
        sendFiltersUpdate();
      },
      true
    );
    renderChipList(
      fLauncherNameChips,
      currentBlockedNames,
      (term) => {
        currentBlockedNames = currentBlockedNames.filter((t) => t !== term);
        renderAllLauncherLists();
        sendFiltersUpdate();
      },
      false
    );
    renderPopularTagSuggestions();
  }

  function updateFilterCheckboxes(filters) {
    if (!filters) return;
    isUpdatingFiltersUi = true;
    lastSavedFilters = Object.assign({}, filters);

    if (fYtShorts) fYtShorts.checked = !!filters.ytBlockShorts;
    if (fYtEdu) fYtEdu.checked = !!filters.ytEducationalMode;
    if (fYtSidebar) fYtSidebar.checked = !!filters.ytBlockSidebar;
    if (fYtComments) fYtComments.checked = !!filters.ytBlockComments;
    currentShowOnlyTypes = Array.isArray(filters.ytShowOnlyTypes) ? filters.ytShowOnlyTypes.slice() : [];
    if (fYtShowOnly) fYtShowOnly.checked = !!filters.ytShowOnlyEnabled;
    renderYtTypes();

    if (fIgReels) fIgReels.checked = !!filters.igBlockReels;
    if (fIgFeed) fIgFeed.checked = !!filters.igBlockFeed;
    if (fIgComments) fIgComments.checked = !!filters.igBlockComments;

    if (fTtFeed) fTtFeed.checked = !!filters.ttBlockFeed;

    if (fRdFeed) fRdFeed.checked = !!filters.rdBlockFeed;
    if (fRdComments) fRdComments.checked = !!filters.rdBlockComments;

    if (fTwFeed) fTwFeed.checked = !!filters.twBlockFeed;
    if (fTwTrends) fTwTrends.checked = !!filters.twBlockTrends;
    if (fRdNsfw) fRdNsfw.checked = !!filters.rdBlockNsfw;
    if (fTwSensitive) fTwSensitive.checked = !!filters.twBlockSensitive;

    if (fLiFeed) fLiFeed.checked = !!filters.liBlockFeed;

    if (fGrayscale) fGrayscale.checked = !!(filters.globalGrayscale || filters.grayscaleMode);
    if (fNotifications) {
      fNotifications.checked = !!(filters.globalBlockNotifications || filters.blockNotifications);
    }
    if (fHudAlpha) {
      const alphaNum = Number(filters.hudAlpha ?? filters.hud_alpha);
      const pct = Math.round(
        (Number.isFinite(alphaNum) ? Math.min(1.0, Math.max(0.15, alphaNum)) : 0.94) * 100
      );
      fHudAlpha.value = String(pct);
      if (fHudAlphaVal) fHudAlphaVal.textContent = `${pct}%`;
    }
    if (fHudScale) {
      const scaleNum = Number(filters.hudScale ?? filters.hud_scale);
      const sPct = Math.round(
        (Number.isFinite(scaleNum) ? Math.min(1.6, Math.max(0.7, scaleNum)) : 1.0) * 100
      );
      fHudScale.value = String(sPct);
      if (fHudScaleVal) fHudScaleVal.textContent = `${sPct}%`;
    }
    if (fHudHideEye) {
      const hideEye = filters.hudHideToEye ?? filters.hud_hide_to_eye;
      fHudHideEye.checked = hideEye === undefined ? true : !!hideEye;
    }

    const lnEn = filters.launcherFilterEnabled ?? filters.launcher_filter_enabled;
    if (fLauncherEnabled) fLauncherEnabled.checked = lnEn === undefined ? true : !!lnEn;
    currentBlockedTags = normalizeTermList(
      filters.launcherBlockedTags ?? filters.launcher_blocked_tags ?? []
    );
    currentBlockedNames = normalizeTermList(
      filters.launcherBlockedNames ?? filters.launcher_blocked_names ?? []
    );
    syncAcWarningUi();
    renderAllLauncherLists();

    isUpdatingFiltersUi = false;
  }

  function sendFiltersUpdate() {
    if (isUpdatingFiltersUi) return;
    if (fLauncherEnabled && !fLauncherEnabled.checked && antiCheatActive) {
      fLauncherEnabled.checked = true;
      syncAcWarningUi("🔒 Anti-Burla ativo: desative para desligar o filtro de launchers.");
      return;
    }
    const prevSnapshot = lastSavedFilters;
    const isGrayscale = fGrayscale ? fGrayscale.checked : false;
    const isNotif = fNotifications ? fNotifications.checked : false;
    const rawPct = fHudAlpha ? Number(fHudAlpha.value) : 94;
    const hudAlpha = Number.isFinite(rawPct) ? Math.min(1.0, Math.max(0.15, rawPct / 100)) : 0.94;
    const rawScalePct = fHudScale ? Number(fHudScale.value) : 100;
    const hudScale = Number.isFinite(rawScalePct)
      ? Math.min(1.6, Math.max(0.7, rawScalePct / 100))
      : 1.0;
    const hudHideToEye = fHudHideEye ? !!fHudHideEye.checked : true;
    const filters = {
      blockShorts: false,
      grayscaleMode: isGrayscale,
      educationalOnly: false,
      blockFeed: false,
      blockComments: false,
      blockNotifications: isNotif,

      ytBlockShorts: fYtShorts ? fYtShorts.checked : false,
      ytEducationalMode: fYtEdu ? fYtEdu.checked : false,
      ytBlockSidebar: fYtSidebar ? fYtSidebar.checked : false,
      ytBlockComments: fYtComments ? fYtComments.checked : false,
      ytShowOnlyEnabled: fYtShowOnly ? fYtShowOnly.checked && currentShowOnlyTypes.length > 0 : false,
      ytShowOnlyTypes: currentShowOnlyTypes.slice(),

      igBlockReels: fIgReels ? fIgReels.checked : false,
      igBlockFeed: fIgFeed ? fIgFeed.checked : false,
      igBlockComments: fIgComments ? fIgComments.checked : false,

      ttBlockFeed: fTtFeed ? fTtFeed.checked : false,

      rdBlockFeed: fRdFeed ? fRdFeed.checked : false,
      rdBlockComments: fRdComments ? fRdComments.checked : false,

      twBlockFeed: fTwFeed ? fTwFeed.checked : false,
      twBlockTrends: fTwTrends ? fTwTrends.checked : false,
      rdBlockNsfw: fRdNsfw ? fRdNsfw.checked : false,
      twBlockSensitive: fTwSensitive ? fTwSensitive.checked : false,

      liBlockFeed: fLiFeed ? fLiFeed.checked : false,

      globalGrayscale: isGrayscale,
      globalBlockNotifications: isNotif,

      hudAlpha,
      hudScale,
      hudHideToEye,

      launcherFilterEnabled: fLauncherEnabled ? !!fLauncherEnabled.checked : true,
      launcherBlockedTags: currentBlockedTags.slice(),
      launcherBlockedNames: currentBlockedNames.slice(),
    };
    chrome.runtime.sendMessage({ type: "SET_FOCUS_FILTERS", filters }, (resp) => {
      if (chrome.runtime.lastError || !resp) return;
      let acChanged = false;
      if (typeof resp.antiCheatActive === "boolean") {
        acChanged = antiCheatActive !== resp.antiCheatActive;
        antiCheatActive = resp.antiCheatActive;
      }
      if (resp.tagDisplayMap && typeof resp.tagDisplayMap === "object") {
        tagDisplayMap = Object.assign({}, tagDisplayMap, resp.tagDisplayMap);
      }
      if (typeof resp.primaryLanguage === "string" && resp.primaryLanguage) {
        primaryLanguage = resp.primaryLanguage;
      }
      if (!resp.success) {
        if (resp.antiCheatLocked) {
          antiCheatActive = true;
          syncAcWarningUi(resp.message || "🔒 Anti-Burla ativo: remoção bloqueada.");
        }
        updateFilterCheckboxes(resp.filters || prevSnapshot);
      } else if (resp.filters) {
        updateFilterCheckboxes(resp.filters);
      } else if (acChanged) {
        syncAcWarningUi();
        renderAllLauncherLists();
      }
    });
  }

  function bindTermEditor(inputEl, addBtnEl, dropdownEl, autocompleteKind, onAdd) {
    if (!inputEl || !addBtnEl) return;
    let debounceTimer = null;
    let searchSeq = 0;

    const clearDropdown = () => {
      if (!dropdownEl) return;
      dropdownEl.textContent = "";
      dropdownEl.hidden = true;
    };

    const submit = (overrideVal) => {
      const val = String(overrideVal !== undefined ? overrideVal : inputEl.value || "").trim();
      if (!val) return;
      inputEl.value = "";
      clearDropdown();
      onAdd(val);
    };

    const renderSuggestions = (items) => {
      if (!dropdownEl) return;
      dropdownEl.textContent = "";
      if (!Array.isArray(items) || items.length === 0) {
        dropdownEl.hidden = true;
        return;
      }
      items.slice(0, 8).forEach((item) => {
        const val = autocompleteKind === "game" ? item.title : item.canonicalEn;
        const label = autocompleteKind === "game" ? item.title : item.displayName || item.canonicalEn;
        const sub =
          autocompleteKind === "game"
            ? item.appId > 0
              ? `${item.source || "Steam"} #${item.appId}`
              : item.source || ""
            : label.toLowerCase() !== String(val || "").toLowerCase()
              ? val
              : "";
        if (!val) return;

        const optBtn = document.createElement("button");
        optBtn.type = "button";
        optBtn.className = "ac-opt";

        const left = document.createElement("span");
        left.className = "ac-opt-left";
        if (item.tinyImage) {
          const img = document.createElement("img");
          img.className = "ac-opt-thumb";
          img.src = item.tinyImage;
          img.alt = "";
          left.appendChild(img);
        }
        const tSpan = document.createElement("span");
        tSpan.className = "ac-opt-title";
        tSpan.textContent = label;
        left.appendChild(tSpan);
        optBtn.appendChild(left);

        if (sub) {
          const sSpan = document.createElement("span");
          sSpan.className = "ac-opt-sub";
          sSpan.textContent = sub;
          optBtn.appendChild(sSpan);
        }

        optBtn.addEventListener("click", () => {
          if (autocompleteKind === "tag" && val && label) {
            tagDisplayMap[val] = label;
          }
          submit(val);
        });
        dropdownEl.appendChild(optBtn);
      });
      dropdownEl.hidden = dropdownEl.childElementCount === 0;
    };

    inputEl.addEventListener("input", () => {
      if (!dropdownEl) return;
      if (debounceTimer) clearTimeout(debounceTimer);
      const q = String(inputEl.value || "").trim();
      const minLen = autocompleteKind === "game" ? 2 : 1;
      if (q.length < minLen) {
        clearDropdown();
        return;
      }
      debounceTimer = setTimeout(() => {
        const mySeq = ++searchSeq;
        try {
          chrome.runtime.sendMessage(
            {
              type: "SEARCH_STEAM_AUTOCOMPLETE",
              kind: autocompleteKind,
              query: q,
              lang: primaryLanguage,
            },
            (res) => {
              if (mySeq !== searchSeq || chrome.runtime.lastError || !res) {
                clearDropdown();
                return;
              }
              renderSuggestions(res.results || []);
            }
          );
        } catch (_) {
          clearDropdown();
        }
      }, 220);
    });

    addBtnEl.addEventListener("click", () => submit());
    inputEl.addEventListener("keydown", (ev) => {
      if (ev.key === "Enter") {
        ev.preventDefault();
        submit();
      } else if (ev.key === "Escape") {
        clearDropdown();
      }
    });
  }

  bindTermEditor(fLauncherTagIn, fLauncherTagAdd, fLauncherTagAc, "tag", (val) => {
    currentBlockedTags = normalizeTermList([...currentBlockedTags, val]);
    renderAllLauncherLists();
    sendFiltersUpdate();
  });
  bindTermEditor(fLauncherNameIn, fLauncherNameAdd, fLauncherNameAc, "game", (val) => {
    currentBlockedNames = normalizeTermList([...currentBlockedNames, val]);
    renderAllLauncherLists();
    sendFiltersUpdate();
  });

  if (fHudAlpha) {
    fHudAlpha.addEventListener("input", () => {
      if (fHudAlphaVal) fHudAlphaVal.textContent = `${fHudAlpha.value}%`;
    });
  }
  if (fHudScale) {
    fHudScale.addEventListener("input", () => {
      if (fHudScaleVal) fHudScaleVal.textContent = `${fHudScale.value}%`;
    });
  }

  [
    fYtShorts, fYtEdu, fYtSidebar, fYtComments, fYtShowOnly,
    fIgReels, fIgFeed, fIgComments,
    fTtFeed,
    fRdFeed, fRdComments,
    fTwFeed, fTwTrends, fRdNsfw, fTwSensitive,
    fLiFeed,
    fGrayscale, fNotifications,
    fHudAlpha, fHudScale, fHudHideEye,
    fLauncherEnabled,
  ].forEach((el) => {
    if (el) el.addEventListener("change", sendFiltersUpdate);
  });

  function loadPopularTags() {
    try {
      chrome.runtime.sendMessage(
        { type: "GET_POPULAR_STEAM_TAGS", lang: primaryLanguage },
        (res) => {
          if (chrome.runtime.lastError || !res) return;
          if (Array.isArray(res.tagItems) && res.tagItems.length > 0) {
            popularSteamTags = res.tagItems
              .map((t) => ({
                canonicalEn: String(t.canonicalEn || t.canonical_en || t.displayName || "").trim(),
                displayName: String(t.displayName || t.display_name || t.canonicalEn || "").trim(),
              }))
              .filter((t) => t.canonicalEn);
          } else if (Array.isArray(res.tags)) {
            popularSteamTags = res.tags
              .map((t) => (typeof t === "string" ? t : t && (t.displayName || t.name)))
              .filter(Boolean)
              .map((name) => ({ canonicalEn: name, displayName: name }));
          }
          renderPopularTagSuggestions();
        }
      );
    } catch (_) {}
  }
  loadPopularTags();

  try {
    if (chrome.storage && chrome.storage.local) {
      chrome.storage.local.get(["focusFilters", "tagDisplayMap", "primaryLanguage"], (res) => {
        if (res && res.tagDisplayMap && typeof res.tagDisplayMap === "object") {
          tagDisplayMap = Object.assign({}, tagDisplayMap, res.tagDisplayMap);
        }
        if (res && typeof res.primaryLanguage === "string" && res.primaryLanguage) {
          primaryLanguage = res.primaryLanguage;
        }
        if (res && res.focusFilters) {
          updateFilterCheckboxes(res.focusFilters);
        }
      });
    }
  } catch (_) {}

  function formatTime(seconds) {
    if (seconds === undefined || seconds === null) return "--:--";
    const sec = Math.max(0, parseInt(seconds, 10));
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    if (m >= 60) {
      const h = Math.floor(m / 60);
      return `${h}h ${m % 60}m`;
    }
    return `${m}m ${s < 10 ? "0" + s : s}s`;
  }

  function extractSitePatterns(site) {
    const out = new Set();
    const grp = parseGroupPatternData(site);
    if (grp.isGroup) {
      for (const s of grp.sites) {
        const c = String(s).trim().toLowerCase();
        if (c) out.add(c);
      }
      for (const app of grp.apps) {
        const appName = String(app.name || "").trim().toLowerCase();
        const appExec = String(app.exec || "").trim().toLowerCase();
        for (const key of Object.keys(KNOWN_APP_DOMAINS)) {
          if (appName.includes(key) || appExec.includes(key)) {
            for (const d of KNOWN_APP_DOMAINS[key]) out.add(d);
          }
        }
      }
      return Array.from(out);
    }
    const raw = (site.pattern || "").trim();
    const list = raw
      .split(",")
      .map((p) => p.trim().toLowerCase())
      .filter(Boolean);
    if (list.length === 0 && site.entityId) {
      list.push(site.entityId.toLowerCase());
    }
    return list;
  }

  function checkCurrentTab(sites) {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      if (!tabs || tabs.length === 0) return;
      const currentActiveTab = tabs[0];
      const url = currentActiveTab.url || "";

      if (!url.startsWith("http")) {
        tabStatusPill.innerText = "Guia Interna";
        tabStatusPill.style.color = "#8b949e";
        tabUrlText.innerText = url.substring(0, 40) || "Página em branco";
        activeTabIdForHud = null;
        renderHudToggle(false, false);
        return;
      }

      try {
        const parsed = new URL(url);
        tabUrlText.innerText = parsed.hostname;

        if (parsed.hostname === "127.0.0.1" || parsed.hostname === "localhost") {
          tabStatusPill.innerText = "Tela de Bloqueio";
          tabStatusPill.style.color = "#f85149";
          activeTabIdForHud = null;
          renderHudToggle(false, false);
          return;
        }

        if (currentActiveTab.id != null && currentActiveTab.id !== lastHudQueriedTabId) {
          lastHudQueriedTabId = currentActiveTab.id;
          activeTabIdForHud = currentActiveTab.id;
          try {
            chrome.tabs.sendMessage(currentActiveTab.id, { type: "GET_HUD_STATE" }, (res) => {
              if (chrome.runtime.lastError || !res || !res.available) {
                renderHudToggle(false, false);
                return;
              }
              renderHudToggle(true, !!res.hidden);
            });
          } catch (_) {
            renderHudToggle(false, false);
          }
        }

        let matched = null;
        for (const site of sites || []) {
          const patterns = extractSitePatterns(site);
          for (const pat of patterns) {
            const clean = pat.replace("https://", "").replace("http://", "").replace("www.", "");
            if (clean && (parsed.hostname.toLowerCase().includes(clean) || url.toLowerCase().includes(clean))) {
              matched = site;
              break;
            }
          }
          if (matched) break;
        }

        if (matched) {
          const isBlocked = matched.isBlocked || (matched.remainingSeconds !== undefined && matched.remainingSeconds <= 0);
          tabStatusPill.innerText = isBlocked ? "BLOQUEADO" : `Tempo restante: ${formatTime(matched.remainingSeconds)}`;
          tabStatusPill.style.color = isBlocked ? "#f85149" : "#3fb950";
        } else {
          tabStatusPill.innerText = "Não monitorado";
          tabStatusPill.style.color = "#8b949e";
        }
      } catch (_) {}
    });
  }

  function escapeHtml(raw) {
    return String(raw || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function parseGroupPatternData(site) {
    const out = { isGroup: false, sites: [], apps: [] };
    if (!site) return out;
    if (Array.isArray(site.groupSites) || Array.isArray(site.groupApps)) {
      out.sites = Array.isArray(site.groupSites) ? site.groupSites.filter(Boolean) : [];
      out.apps = Array.isArray(site.groupApps) ? site.groupApps : [];
      out.isGroup =
        out.sites.length > 0 ||
        out.apps.length > 0 ||
        String(site.pattern || "").trim().startsWith("{");
      if (out.isGroup) return out;
    }
    const raw = String(site.pattern || "").trim();
    if (raw.startsWith("{")) {
      try {
        const parsed = JSON.parse(raw);
        if (parsed && typeof parsed === "object") {
          out.isGroup = true;
          if (Array.isArray(parsed.sites)) {
            for (const s of parsed.sites) {
              const v = typeof s === "string" ? s.trim() : s && (s.domain || s.url || s.name);
              if (v) out.sites.push(String(v).trim());
            }
          }
          if (Array.isArray(parsed.apps)) {
            for (const a of parsed.apps) {
              if (typeof a === "string" && a.trim()) {
                out.apps.push({ name: a.trim(), exec: a.trim() });
              } else if (a && typeof a === "object" && (a.name || a.exec)) {
                out.apps.push({ name: a.name || a.exec, exec: a.exec || a.name });
              }
            }
          }
          return out;
        }
      } catch (_) {}
    }
    if (raw.includes(",")) {
      const parts = raw
        .split(",")
        .map((p) => p.trim())
        .filter(Boolean);
      if (parts.length > 1) {
        out.isGroup = true;
        out.sites = parts;
      }
    }
    return out;
  }

  function renderSites(sites, isConnected) {
    checkCurrentTab(sites);
    if (sitesCountBadge) {
      sitesCountBadge.textContent = String(Array.isArray(sites) ? sites.length : 0);
    }

    if (sites.length === 0) {
      container.innerHTML = `
        <div style="text-align: center; color: #8b949e; font-size: 12px; padding: 20px;">
          ${isConnected ? "Nenhum grupo de sites monitorado configurado." : "Abra o aplicativo Chronos para conectar o daemon."}
        </div>
      `;
      return;
    }

    const openGroupIds = new Set();
    container.querySelectorAll("details.site-dropdown[data-entity-id]").forEach((det) => {
      if (det.open) openGroupIds.add(det.getAttribute("data-entity-id"));
    });

    let html = "";
    for (const site of sites) {
      const entityId = String(site.entityId || "");
      const isBlocked = site.isBlocked || (site.remainingSeconds !== undefined && site.remainingSeconds <= 0);
      const statusText = isBlocked ? "BLOQUEADO" : formatTime(site.remainingSeconds);
      const statusClass = isBlocked ? "blocked" : "active";

      let typeBadge = "";
      if (site.targetType === "SITE_GROUP") {
        typeBadge = `<span style="font-size: 9px; background: rgba(56, 189, 248, 0.2); color: #38bdf8; padding: 1px 5px; border-radius: 4px; margin-left: 4px;">GRUPO DE SITES</span>`;
      } else if (site.targetType === "GROUP") {
        typeBadge = `<span style="font-size: 9px; background: rgba(163, 113, 247, 0.2); color: #d2a8ff; padding: 1px 5px; border-radius: 4px; margin-left: 4px;">SESSÃO DE APPS</span>`;
      } else if (site.targetType === "KEYWORD") {
        typeBadge = `<span style="font-size: 9px; background: rgba(251, 146, 60, 0.2); color: #fb923c; padding: 1px 5px; border-radius: 4px; margin-left: 4px;">PALAVRAS</span>`;
      }

      const grp = parseGroupPatternData(site);
      let subSummaryText = escapeHtml(site.pattern || entityId);
      let dropdownHtml = "";
      if (grp.isGroup) {
        const totalItems = grp.sites.length + grp.apps.length;
        subSummaryText =
          totalItems > 0
            ? `${grp.sites.length} site(s) • ${grp.apps.length} app(s) no grupo`
            : "Grupo configurado sem domínios";
        if (totalItems > 0) {
          const isOpen = openGroupIds.has(entityId) ? " open" : "";
          const siteChips = grp.sites
            .map((dom) => `<span class="site-dropdown-chip" title="${escapeHtml(dom)}">🌐 ${escapeHtml(dom)}</span>`)
            .join("");
          const appChips = grp.apps
            .map((a) => {
              const nm = a.name || a.exec || "";
              return `<span class="site-dropdown-chip" title="${escapeHtml(a.exec || nm)}">💻 ${escapeHtml(nm)}</span>`;
            })
            .join("");
          dropdownHtml = `
            <details class="site-dropdown" data-entity-id="${escapeHtml(entityId)}"${isOpen}>
              <summary class="site-dropdown-summary">Sites e itens do grupo (${totalItems})</summary>
              <div class="site-dropdown-items">${siteChips}${appChips}</div>
            </details>
          `;
        }
      }

      html += `
        <div class="site-item">
          <div class="site-top-row">
            <div class="site-info">
              <div class="site-name">${escapeHtml(site.displayName || entityId)} ${typeBadge}</div>
              <div class="site-pattern">${subSummaryText}</div>
            </div>
            <span class="site-status ${statusClass}">${statusText}</span>
          </div>
          ${dropdownHtml}
        </div>
      `;
    }

    container.innerHTML = html;
  }

  function applyStatusPayload(payload) {
    if (!payload || typeof payload !== "object") return;
    if (payload.tagDisplayMap && typeof payload.tagDisplayMap === "object") {
      tagDisplayMap = Object.assign({}, tagDisplayMap, payload.tagDisplayMap);
    }
    if (typeof payload.primaryLanguage === "string" && payload.primaryLanguage) {
      const langChanged = primaryLanguage !== payload.primaryLanguage;
      primaryLanguage = payload.primaryLanguage;
      if (langChanged) loadPopularTags();
    }
    if (typeof payload.antiCheatActive === "boolean") {
      const acChanged = antiCheatActive !== payload.antiCheatActive;
      antiCheatActive = payload.antiCheatActive;
      if (acChanged) {
        syncAcWarningUi();
        renderAllLauncherLists();
      }
    }
    if (payload.focusFilters) {
      updateFilterCheckboxes(payload.focusFilters);
    }
    if (Array.isArray(payload.sites)) {
      localSites = payload.sites;
    }
    const isConnected = !!payload.isConnected;
    if (isConnected) {
      statusBadge.innerText = "Conectado";
      statusBadge.className = "badge badge-online";
    } else {
      statusBadge.innerText = "Desconectado";
      statusBadge.className = "badge badge-offline";
    }
    renderSites(localSites, isConnected);
  }

  async function fetchStatus() {
    chrome.runtime.sendMessage({ type: "GET_STATUS" }, async (response) => {
      if (globalThis.ChronosI18n) {
        globalThis.ChronosI18n.setLang((response && response.primaryLanguage) || "pt-BR");
        globalThis.ChronosI18n.observe(document.body);
      }
      let isConnected = response && response.isConnected;
      let sites = response && response.sites ? response.sites : [];
      if (response) {
        if (response.tagDisplayMap && typeof response.tagDisplayMap === "object") {
          tagDisplayMap = Object.assign({}, tagDisplayMap, response.tagDisplayMap);
        }
        if (typeof response.primaryLanguage === "string" && response.primaryLanguage) {
          const langChanged = primaryLanguage !== response.primaryLanguage;
          primaryLanguage = response.primaryLanguage;
          if (langChanged) loadPopularTags();
        }
      }
      if (response && typeof response.antiCheatActive === "boolean") {
        const acChanged = antiCheatActive !== response.antiCheatActive;
        antiCheatActive = response.antiCheatActive;
        if (acChanged) {
          syncAcWarningUi();
          renderAllLauncherLists();
        }
      }
      if (response && response.focusFilters) {
        updateFilterCheckboxes(response.focusFilters);
      }

      if (!isConnected || sites.length === 0) {
        try {
          const res = await fetch("http://127.0.0.1:4545/api/status");
          if (res.ok) {
            const data = await res.json();
            isConnected = true;
            sites = data.sites || [];
            if (data.tagDisplayMap && typeof data.tagDisplayMap === "object") {
              tagDisplayMap = Object.assign({}, tagDisplayMap, data.tagDisplayMap);
            }
            if (typeof data.primaryLanguage === "string" && data.primaryLanguage) {
              primaryLanguage = data.primaryLanguage;
            }
            if (typeof data.antiCheatActive === "boolean") {
              antiCheatActive = data.antiCheatActive;
            }
            if (data.port) portLabel.innerText = `Daemon :${data.port}`;
            if (data.focusFilters) {
              updateFilterCheckboxes(data.focusFilters);
            } else {
              syncAcWarningUi();
              renderAllLauncherLists();
            }
          }
        } catch (_) {}
      }

      localSites = sites;

      if (isConnected) {
        statusBadge.innerText = "Conectado";
        statusBadge.className = "badge badge-online";
      } else {
        statusBadge.innerText = "Desconectado";
        statusBadge.className = "badge badge-offline";
      }

      renderSites(localSites, isConnected);
    });
  }

  try {
    if (chrome.runtime && chrome.runtime.onMessage) {
      chrome.runtime.onMessage.addListener((msg) => {
        if (msg && msg.type === "CHRONOS_STATE_PUSH") {
          applyStatusPayload(msg);
        }
      });
    }
  } catch (_) {}

  fetchStatus();
  const syncInterval = setInterval(fetchStatus, 1500);

  syncBtn.addEventListener("click", () => {
    statusBadge.innerText = "Sincronizando...";
    chrome.runtime.sendMessage({ type: "FORCE_SYNC" }, () => {
      fetchStatus();
    });
  });

  window.addEventListener("unload", () => {
    clearInterval(syncInterval);
  });
});
