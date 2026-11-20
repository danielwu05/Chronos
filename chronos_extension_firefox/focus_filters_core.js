// Chronos Focus Engine - Nucleo Compartilhado de Filtros HTML/CSS (v1.1.0)
(function (globalScope) {
  function hasOwn(obj, key) {
    return !!obj && Object.prototype.hasOwnProperty.call(obj, key) && obj[key] !== undefined;
  }

  function normalizeFilters(raw) {
    const f = raw || {};
    const ytBlockShorts = hasOwn(f, "ytBlockShorts")
      ? !!f.ytBlockShorts
      : hasOwn(f, "yt_block_shorts")
        ? !!f.yt_block_shorts
        : false;
    const ytEducationalMode = hasOwn(f, "ytEducationalMode")
      ? !!f.ytEducationalMode
      : hasOwn(f, "yt_educational_mode")
        ? !!f.yt_educational_mode
        : false;
    const ytBlockSidebar = hasOwn(f, "ytBlockSidebar")
      ? !!f.ytBlockSidebar
      : hasOwn(f, "yt_block_sidebar")
        ? !!f.yt_block_sidebar
        : false;
    const ytBlockComments = hasOwn(f, "ytBlockComments")
      ? !!f.ytBlockComments
      : hasOwn(f, "yt_block_comments")
        ? !!f.yt_block_comments
        : false;

    const igBlockReels = hasOwn(f, "igBlockReels")
      ? !!f.igBlockReels
      : hasOwn(f, "ig_block_reels")
        ? !!f.ig_block_reels
        : false;
    const igBlockFeed = hasOwn(f, "igBlockFeed")
      ? !!f.igBlockFeed
      : hasOwn(f, "ig_block_feed")
        ? !!f.ig_block_feed
        : false;
    const igBlockComments = hasOwn(f, "igBlockComments")
      ? !!f.igBlockComments
      : hasOwn(f, "ig_block_comments")
        ? !!f.ig_block_comments
        : false;

    const ttBlockFeed = hasOwn(f, "ttBlockFeed")
      ? !!f.ttBlockFeed
      : hasOwn(f, "tt_block_feed")
        ? !!f.tt_block_feed
        : false;

    const rdBlockFeed = hasOwn(f, "rdBlockFeed")
      ? !!f.rdBlockFeed
      : hasOwn(f, "rd_block_feed")
        ? !!f.rd_block_feed
        : false;
    const rdBlockComments = hasOwn(f, "rdBlockComments")
      ? !!f.rdBlockComments
      : hasOwn(f, "rd_block_comments")
        ? !!f.rd_block_comments
        : false;

    const rdBlockNsfw = hasOwn(f, "rdBlockNsfw")
      ? !!f.rdBlockNsfw
      : hasOwn(f, "rd_block_nsfw")
        ? !!f.rd_block_nsfw
        : false;
    const twBlockSensitive = hasOwn(f, "twBlockSensitive")
      ? !!f.twBlockSensitive
      : hasOwn(f, "tw_block_sensitive")
        ? !!f.tw_block_sensitive
        : false;

    const twBlockFeed = hasOwn(f, "twBlockFeed")
      ? !!f.twBlockFeed
      : hasOwn(f, "tw_block_feed")
        ? !!f.tw_block_feed
        : false;
    const twBlockTrends = hasOwn(f, "twBlockTrends")
      ? !!f.twBlockTrends
      : hasOwn(f, "tw_block_trends")
        ? !!f.tw_block_trends
        : false;

    const liBlockFeed = hasOwn(f, "liBlockFeed")
      ? !!f.liBlockFeed
      : hasOwn(f, "li_block_feed")
        ? !!f.li_block_feed
        : false;

    const globalGrayscale = hasOwn(f, "globalGrayscale")
      ? !!f.globalGrayscale
      : hasOwn(f, "global_grayscale")
        ? !!f.global_grayscale
        : !!f.grayscaleMode || !!f.grayscale_mode;

    const globalBlockNotifications = hasOwn(f, "globalBlockNotifications")
      ? !!f.globalBlockNotifications
      : hasOwn(f, "global_block_notifications")
        ? !!f.global_block_notifications
        : !!f.blockNotifications || !!f.block_notifications;

    const rawAlpha = hasOwn(f, "hudAlpha")
      ? Number(f.hudAlpha)
      : hasOwn(f, "hud_alpha")
        ? Number(f.hud_alpha)
        : 0.94;
    const hudAlpha = Number.isFinite(rawAlpha) ? Math.min(1.0, Math.max(0.15, rawAlpha)) : 0.94;

    const hudHideToEye = hasOwn(f, "hudHideToEye")
      ? !!f.hudHideToEye
      : hasOwn(f, "hud_hide_to_eye")
        ? !!f.hud_hide_to_eye
        : true;

    const rawScale = hasOwn(f, "hudScale")
      ? Number(f.hudScale)
      : hasOwn(f, "hud_scale")
        ? Number(f.hud_scale)
        : 1.0;
    const hudScale = Number.isFinite(rawScale) ? Math.min(1.6, Math.max(0.7, rawScale)) : 1.0;

    const launcherFilterEnabled = hasOwn(f, "launcherFilterEnabled")
      ? !!f.launcherFilterEnabled
      : hasOwn(f, "launcher_filter_enabled")
        ? !!f.launcher_filter_enabled
        : true;

    const rawTags = hasOwn(f, "launcherBlockedTags")
      ? f.launcherBlockedTags
      : hasOwn(f, "launcher_blocked_tags")
        ? f.launcher_blocked_tags
        : [];
    const launcherBlockedTags = normalizeTermList(rawTags);

    const rawNames = hasOwn(f, "launcherBlockedNames")
      ? f.launcherBlockedNames
      : hasOwn(f, "launcher_blocked_names")
        ? f.launcher_blocked_names
        : [];
    const launcherBlockedNames = normalizeTermList(rawNames);

    const rawShowOnly = hasOwn(f, "ytShowOnlyTypes")
      ? f.ytShowOnlyTypes
      : hasOwn(f, "yt_show_only_types")
        ? f.yt_show_only_types
        : [];
    const ytShowOnlyTypes = normalizeTermList(rawShowOnly).map((t) => t.toLowerCase());
    const ytShowOnlyEnabled =
      ytShowOnlyTypes.length > 0 &&
      (hasOwn(f, "ytShowOnlyEnabled") ? !!f.ytShowOnlyEnabled : !!f.yt_show_only_enabled);

    return {
      ytBlockShorts,
      ytEducationalMode,
      ytBlockSidebar,
      ytBlockComments,
      ytShowOnlyEnabled,
      ytShowOnlyTypes,
      igBlockReels,
      igBlockFeed,
      igBlockComments,
      ttBlockFeed,
      rdBlockFeed,
      rdBlockComments,
      rdBlockNsfw,
      twBlockFeed,
      twBlockTrends,
      twBlockSensitive,
      liBlockFeed,
      globalGrayscale,
      globalBlockNotifications,
      hudAlpha,
      hudHideToEye,
      hudScale,
      launcherFilterEnabled,
      launcherBlockedTags,
      launcherBlockedNames,
    };
  }

  function foldMatchText(input) {
    return String(input || "")
      .replace(/[\u00ae\u2122\u00a9]/g, "")
      .trim()
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "");
  }

  function stripTrademarkSymbols(input) {
    return String(input || "")
      .replace(/[\u00ae\u2122\u00a9]/g, "")
      .replace(/\s+/g, " ")
      .trim();
  }

  function compactAlnum(input) {
    return foldMatchText(input).replace(/[^a-z0-9]/g, "");
  }

  function normalizeTermList(arr) {
    if (!Array.isArray(arr)) return [];
    const out = [];
    const seen = new Set();
    for (const item of arr) {
      const clean = String(item || "").trim();
      if (!clean) continue;
      const key = foldMatchText(clean);
      if (!seen.has(key)) {
        seen.add(key);
        out.push(clean);
      }
    }
    return out;
  }

  function buildFocusCss(rawFilters, hostInput, pathInput) {
    const filters = normalizeFilters(rawFilters);
    const host = String(hostInput || "").toLowerCase();
    const path = String(pathInput || "/").toLowerCase();
    let css = "";

    // 1. Grayscale Global Detox (apenas no root :root e fullscreen, sem quebrar position:fixed)
    if (filters.globalGrayscale) {
      css += `
:root.chronos-grayscale {
  filter: grayscale(100%) !important;
  -webkit-filter: grayscale(100%) !important;
}
html.chronos-grayscale :fullscreen,
html.chronos-grayscale video {
  filter: grayscale(100%) !important;
  -webkit-filter: grayscale(100%) !important;
}
`;
    }

    // 2. YouTube (seletores 2026 sem falsos positivos em títulos comuns ou News)
    if (host.includes("youtube.com") || host.includes("youtu.be")) {
      if (filters.ytBlockShorts) {
        css += `
ytd-reel-shelf-renderer,
ytd-rich-shelf-renderer[is-shorts],
ytd-rich-section-renderer:has(ytd-rich-shelf-renderer[is-shorts]),
ytd-rich-section-renderer:has(grid-shelf-view-model ytm-shorts-lockup-view-model, grid-shelf-view-model ytm-shorts-lockup-view-model-v2),
grid-shelf-view-model:has(ytm-shorts-lockup-view-model, ytm-shorts-lockup-view-model-v2),
ytm-shorts-lockup-view-model,
ytm-shorts-lockup-view-model-v2,
ytd-reel-item-renderer,
ytd-rich-item-renderer:has(a[href*="/shorts/"]),
ytd-video-renderer:has(a[href*="/shorts/"]),
ytd-grid-video-renderer:has(a[href*="/shorts/"]),
ytd-compact-video-renderer:has(a[href*="/shorts/"]),
ytd-guide-entry-renderer:has(a[href^="/shorts"]),
ytd-mini-guide-entry-renderer:has(a[href^="/shorts"]),
ytd-guide-entry-renderer:has(a[title="Shorts"]),
ytd-mini-guide-entry-renderer[aria-label="Shorts"],
yt-tab-shape[tab-title="Shorts"],
tp-yt-paper-tab:has([aria-label="Shorts"]),
yt-chip-cloud-chip-renderer:has([title="Shorts"]),
ytd-shorts,
#shorts-container,
a[href^="/shorts"] {
  display: none !important;
}
`;
      }

      if (filters.ytShowOnlyEnabled) {
        // "Mostrar apenas": feed/related cards start hidden and are revealed one by one
        // (data-chronos-yt-ok="1") once their video type is known to be allowed.
        css += `
ytd-browse[page-subtype="home"] ytd-rich-item-renderer:not([data-chronos-yt-ok="1"]),
ytd-browse[page-subtype="subscriptions"] ytd-rich-item-renderer:not([data-chronos-yt-ok="1"]),
ytd-browse[page-subtype="home"] ytd-rich-section-renderer,
ytd-watch-next-secondary-results-renderer ytd-compact-video-renderer:not([data-chronos-yt-ok="1"]),
ytd-watch-next-secondary-results-renderer yt-lockup-view-model:not([data-chronos-yt-ok="1"]),
ytd-watch-next-secondary-results-renderer ytd-reel-shelf-renderer,
.ytp-endscreen-content,
.ytp-ce-element,
.ytp-videowall-still {
  display: none !important;
}
`;
      }

      if (filters.ytEducationalMode) {
        css += `
html[data-chronos-yt-home="1"] ytd-browse[page-subtype="home"] #primary,
html[data-chronos-yt-home="1"] ytd-browse[page-subtype="home"] ytd-rich-grid-renderer,
html[data-chronos-yt-home="1"] ytd-browse[page-subtype="home"] #contents,
html[data-chronos-yt-home="1"] ytd-page-manager > ytd-browse[page-subtype="home"],
ytd-browse[page-subtype="home"] ytd-rich-grid-renderer,
.ytp-endscreen-content,
.ytp-ce-element,
.ytp-videowall-still {
  display: none !important;
}
`;
      }

      if (filters.ytBlockSidebar) {
        css += `
#secondary,
#secondary-inner #related,
#related,
ytd-watch-flexy #secondary,
ytd-watch-next-secondary-results-renderer,
#chat,
ytd-live-chat-frame {
  display: none !important;
}
`;
      }

      if (filters.ytBlockComments) {
        css += `
#comments,
ytd-comments,
ytd-item-section-renderer:has(#comments, ytd-comments),
ytd-comments-header-renderer {
  display: none !important;
}
`;
      }
    }

    // 3. Instagram (Reels, Feed Principal, Explore e Comentários)
    if (host.includes("instagram.com")) {
      if (filters.igBlockReels) {
        css += `
a[href^="/reels"],
a[href*="/reels/"],
div:has(> a[href*="/reels/"]),
svg[aria-label*="Reels" i],
a[role="link"]:has(svg[aria-label*="Reels" i]),
article:has(a[href*="/reels/"]) {
  display: none !important;
}
`;
      }

      if (filters.igBlockFeed) {
        css += `
html[data-chronos-path="/"] main[role="main"] article,
html[data-chronos-path="/"] div[role="feed"],
main[role="main"] > section > div > div:has(article),
main[role="main"] div[role="feed"],
html[data-chronos-path^="/explore"] main[role="main"],
a[href^="/explore"] {
  display: none !important;
}
`;
      }

      if (filters.igBlockComments) {
        css += `
ul._a9ym,
ul[class*="comments"],
section:has(> ul[class*="comments"]),
form:has(textarea[placeholder*="coment" i], textarea[placeholder*="comment" i]),
div[role="dialog"]:has(article) ul._a9ym {
  display: none !important;
}
`;
      }
    }

    // 4. TikTok
    if (host.includes("tiktok.com") && filters.ttBlockFeed) {
      css += `
[data-e2e="recommend-list-item-container"],
[data-e2e="feed-container"],
[data-e2e="recommend-list-container"],
div[class*="DivItemContainer"],
main div[data-e2e*="video-feed"] {
  display: none !important;
}
`;
    }

    // 5. Reddit
    if (host.includes("reddit.com")) {
      if (filters.rdBlockNsfw) {
        // NSFW (+18) posts in feeds, search and old reddit (blurred cards included).
        css += `
shreddit-post[nsfw],
article:has(shreddit-post[nsfw]),
shreddit-blurred-container[reason="nsfw"],
.thing.over18,
[data-chronos-nsfw="1"] {
  display: none !important;
}
`;
      }
      if (filters.rdBlockFeed) {
        css += `
shreddit-feed,
.ListingLayout-outerContainer main,
[data-testid="post-container"],
#subgrid-container,
html:not([data-chronos-rd-post="1"]) shreddit-post,
[data-testid="frontpage-sidebar"] {
  display: none !important;
}
`;
      }

      if (filters.rdBlockComments) {
        css += `
#comment-tree,
shreddit-comment-tree,
.commentarea,
shreddit-comment,
comment-body-header {
  display: none !important;
}
`;
      }
    }

    // 6. Twitter / X
    if (host.includes("twitter.com") || host.includes("x.com")) {
      if (filters.twBlockSensitive) {
        css += `
[data-chronos-nsfw="1"] {
  display: none !important;
}
`;
      }
      if (filters.twBlockFeed) {
        css += `
[data-testid="primaryColumn"] section[aria-label*="Timeline" i],
[data-testid="primaryColumn"] section[aria-label*="Linha do tempo" i],
html[data-chronos-path="/home"] [data-testid="primaryColumn"] section[role="region"] {
  display: none !important;
}
`;
      }

      if (filters.twBlockTrends) {
        css += `
[aria-label="Timeline: Trending now"],
[aria-label="Timeline: Explore"],
[data-testid="sidebarColumn"] [data-testid="trend"],
[data-testid="sidebarColumn"] section,
[aria-label*="Tendências" i],
[aria-label*="Assuntos do Momento" i],
[aria-label*="What’s happening" i],
[aria-label*="O que está acontecendo" i] {
  display: none !important;
}
`;
      }
    }

    // 7. LinkedIn
    if (host.includes("linkedin.com") && filters.liBlockFeed) {
      css += `
.feed-shared-update-v2,
main.scaffold-layout__main .scaffold-finite-scroll,
main[role="main"] .feed-shared-update-v2,
main[role="main"] [data-finite-scroll-hotkey-context="FEED"],
html[data-chronos-path^="/feed"] main.scaffold-layout__main {
  display: none !important;
}
`;
    }

    // 8. Notificações e Badges (estritamente escopados — sem matar badges genéricos na web)
    if (filters.globalBlockNotifications) {
      css += `
ytd-notification-topbar-button-renderer,
.ytd-notification-topbar-button-renderer .yt-spec-icon-badge-shape__badge,
a[data-testid="AppTabBar_Notifications_Link"] div[aria-label*="unread" i],
a[data-testid="AppTabBar_Notifications_Link"] [aria-live],
#notifications-nav-item .notification-badge,
a[href*="/notifications"] .notification-badge,
#header-notifications-button-badge,
faceplate-tracker[noun="notifications"] .badge-count,
.notification-badge {
  display: none !important;
}
`;
    }

    return css;
  }

  function getRedirectTarget(rawFilters, hostInput, pathInput, originInput) {
    const filters = normalizeFilters(rawFilters);
    const host = String(hostInput || "").toLowerCase();
    const path = String(pathInput || "/").toLowerCase();
    const origin = String(originInput || "").replace(/\/+$/, "");
    if (!origin) return null;

    if (host.includes("youtube.com") && filters.ytBlockShorts && path.startsWith("/shorts")) {
      return `${origin}/`;
    }
    if (host.includes("instagram.com")) {
      if (filters.igBlockReels && path.startsWith("/reels")) {
        return `${origin}/`;
      }
      if (filters.igBlockFeed && path.startsWith("/explore")) {
        return `${origin}/`;
      }
    }
    return null;
  }

  function syncHtmlAttributes(rawFilters, hostInput, pathInput, rootEl) {
    if (!rootEl) return;
    const filters = normalizeFilters(rawFilters);
    const host = String(hostInput || "").toLowerCase();
    const path = String(pathInput || "/").toLowerCase();

    if (filters.globalGrayscale) {
      rootEl.classList.add("chronos-grayscale");
    } else {
      rootEl.classList.remove("chronos-grayscale");
    }

    rootEl.setAttribute("data-chronos-host", host);
    rootEl.setAttribute("data-chronos-path", path || "/");

    if (host.includes("youtube.com") && filters.ytEducationalMode && (path === "/" || path === "")) {
      rootEl.setAttribute("data-chronos-yt-home", "1");
    } else {
      rootEl.removeAttribute("data-chronos-yt-home");
    }

    if (host.includes("reddit.com") && path.includes("/comments/")) {
      rootEl.setAttribute("data-chronos-rd-post", "1");
    } else {
      rootEl.removeAttribute("data-chronos-rd-post");
    }
  }

  // Generic Launcher Store & Community DOM Filter (Steam, Epic, GOG, Itch)
  const LAUNCHER_STORE_HOSTS = [
    "store.steampowered.com",
    "steamcommunity.com",
    "store.epicgames.com",
    "gog.com",
    "itch.io",
    "lutris.net",
  ];

  function isLauncherStoreHost(hostInput) {
    const h = String(hostInput || "").trim().toLowerCase();
    return LAUNCHER_STORE_HOSTS.some((d) => h === d || h.endsWith("." + d));
  }

  const GENERIC_STOREFRONT_TITLES = new Set([
    "",
    "steam",
    "steam search",
    "busca steam",
    "resultados da busca",
    "search",
    "welcome to steam",
    "bem-vindo ao steam",
    "bem vindo ao steam",
    "sign in",
    "iniciar sessao",
    "login",
    "age verification",
    "verificacao de idade",
    "epic games",
    "epic games store",
    "gog",
    "gog.com",
    "gog com",
    "itch",
    "itch.io",
    "itch io",
    "lutris",
    "lutris.net",
    "games",
    "games - lutris",
    "top games",
    "browse games",
    "browse",
    "store",
    "home",
    "explore",
  ]);

  function isGenericStorefrontTitle(title) {
    const norm = foldMatchText(title);
    return (
      GENERIC_STOREFRONT_TITLES.has(norm) ||
      norm.startsWith("top free ") ||
      norm.startsWith("top paid ") ||
      norm.startsWith("top games ") ||
      norm.endsWith(" on itch.io") ||
      norm.endsWith(" on itch io") ||
      norm.endsWith(" - lutris")
    );
  }

  const STEAM_FALLBACK_TAG_MAP = {
    6650: ["Nudity", "Nudez"],
    9130: ["Hentai"],
    12095: ["Sexual Content", "Conteúdo Sexual"],
    40500: ["Sexual Themes"],
    24904: ["NSFW", "Conteúdo Adulto"],
    5611: ["Hentai", "NSFW", "Conteúdo Adulto"],
    4085: ["Anime"],
    113: ["Free to Play", "Gratuito para Jogar"],
    19: ["Action", "Ação"],
    21: ["Adventure", "Aventura"],
    122: ["RPG"],
    9: ["Strategy", "Estratégia"],
    597: ["Casual"],
    599: ["Simulation", "Simulação"],
    492: ["Indie"],
    1663: ["FPS"],
    3859: ["Multiplayer", "Multijogador"],
    1775: ["PvP"],
    4182: ["Singleplayer", "Um Jogador"],
    1716: ["Roguelike"],
    29482: ["Souls-like", "Soulslike"],
    1662: ["Survival", "Sobrevivência"],
    4345: ["Gore", "Violência Extrema"],
    4667: ["Violent", "Violento"],
  };

  let dynamicSteamTagMap = {};

  function decodeUriSafe(str) {
    try {
      return decodeURIComponent(String(str || "").replace(/\+/g, " "));
    } catch (_) {
      return String(str || "");
    }
  }

  function extractSteamAppIdFromUrl(urlStr) {
    const raw = String(urlStr || "");
    for (const candidate of [raw, raw.includes("%") ? decodeUriSafe(raw) : raw]) {
      const mPath = candidate.match(/(?:^|\/|[=?&])app\/(\d+)/i);
      if (mPath) return parseInt(mPath[1], 10);
      const mParam = candidate.match(/[?&]appid=(\d+)/i);
      if (mParam) return parseInt(mParam[1], 10);
    }
    return null;
  }

  function isUmbrellaAdultTag(norm) {
    return (
      norm === "nsfw" ||
      norm === "conteudo adulto" ||
      norm === "adult only" ||
      norm === "adulto" ||
      norm === "adult" ||
      norm === "18+"
    );
  }

  function isExplicitAdultCandidate(norm) {
    return (
      norm === "hentai" ||
      norm === "nsfw" ||
      norm === "sexual content" ||
      norm === "conteudo sexual" ||
      norm === "nudity" ||
      norm === "nudez" ||
      norm === "sexual themes" ||
      norm === "conteudo adulto" ||
      norm === "adult only" ||
      norm === "erotic" ||
      norm === "eroge"
    );
  }

  function expandKnownTagIds(tagIds, descIds) {
    const out = [];
    const seen = new Set();
    const pushTerm = (t) => {
      const s = String(t || "").trim();
      if (s && !seen.has(s)) {
        seen.add(s);
        out.push(s);
      }
    };
    const tArr = Array.isArray(tagIds) ? tagIds : [];
    const dArr = Array.isArray(descIds) ? descIds : [];
    let hasAdult = dArr.some((d) => d === 3 || d === 4);
    for (const rawId of tArr) {
      const id = Number(rawId);
      if (!Number.isFinite(id) || id <= 0) continue;
      if (id === 6650 || id === 9130 || id === 12095 || id === 40500 || id === 24904 || id === 5611) {
        hasAdult = true;
      }
      const dyn = dynamicSteamTagMap[String(id)];
      if (Array.isArray(dyn)) dyn.forEach(pushTerm);
      const fb = STEAM_FALLBACK_TAG_MAP[id];
      if (Array.isArray(fb)) fb.forEach(pushTerm);
    }
    if (dArr.includes(2)) {
      pushTerm("Violência Extrema");
      pushTerm("Gore");
    }
    if (dArr.includes(3) || dArr.includes(4)) {
      pushTerm("Sexual Content");
      pushTerm("Conteúdo Sexual");
      pushTerm("Nudity");
      pushTerm("Nudez");
    }
    if (hasAdult) {
      pushTerm("NSFW");
      pushTerm("Conteúdo Adulto");
      pushTerm("Adult Only");
    }
    return out;
  }

  function tagMatches(blockedTag, candidate) {
    const bNorm = foldMatchText(blockedTag);
    const cNorm = foldMatchText(candidate);
    if (!bNorm || !cNorm) return false;
    if (bNorm === cNorm) return true;
    if (isUmbrellaAdultTag(bNorm) && isExplicitAdultCandidate(cNorm)) return true;
    const bCompact = compactAlnum(blockedTag);
    const cCompact = compactAlnum(candidate);
    if (bCompact.length >= 3 && bCompact === cCompact) return true;
    return bNorm.length >= 4 && cNorm.includes(bNorm);
  }

  function matchLocalGame(title, siteTags, filters) {
    if (!filters || !filters.launcherFilterEnabled) return null;
    const tNorm = foldMatchText(title);
    const tCompact = compactAlnum(title);
    for (const bn of filters.launcherBlockedNames || []) {
      const bNorm = foldMatchText(bn);
      const bCompact = compactAlnum(bn);
      if (!bNorm) continue;
      if (
        (tNorm && tNorm.includes(bNorm)) ||
        (bCompact.length >= 3 && tCompact.includes(bCompact))
      ) {
        return {
          matchType: "NOME",
          matchedTerm: bn,
          reason: `Bloqueado pelo filtro de nome "${bn}"`,
        };
      }
    }
    const tagsArr = Array.isArray(siteTags) ? siteTags : [];
    for (const bt of filters.launcherBlockedTags || []) {
      if (tagsArr.some((cand) => tagMatches(bt, cand))) {
        return {
          matchType: "TAG",
          matchedTerm: bt,
          reason: `Bloqueado pela tag "${bt}"`,
        };
      }
    }
    return null;
  }

  const ITCH_AUX_SEGMENTS = new Set([
    "devlog",
    "download",
    "data.json",
    "presskit",
    "rate",
    "comments",
    "community",
    "posts",
    "files",
  ]);

  const LUTRIS_NON_GAME_SEGMENTS = new Set([
    "genre",
    "platform",
    "tags",
    "tag",
    "category",
    "search",
    "year",
    "company",
    "series",
  ]);

  function normalizeExtractedStoreTag(raw) {
    let s = stripTrademarkSymbols(String(raw || "").replace(/,$/, ""));
    if (!s || s === "+") return "";
    s = s.replace(/^gamegenre\//i, "").replace(/^genre-/i, "").replace(/^tag-/i, "").trim();
    if (/^rougelike$/i.test(s)) return "Roguelike";
    return s;
  }

  function humanizeUrlSlug(rawSlug) {
    const clean = stripTrademarkSymbols(
      decodeUriSafe(String(rawSlug || ""))
        .replace(/\.[a-z0-9]{2,5}$/i, "")
        .replace(/[_-]+/g, " ")
    );
    return clean && !isGenericStorefrontTitle(clean) ? clean : "";
  }

  function extractSlugTitleFromUrl(parsedUrl, hostLower) {
    if (!parsedUrl || !parsedUrl.pathname) return "";
    const segs = parsedUrl.pathname.split("/").filter(Boolean);
    if (hostLower.includes("epicgames.com")) {
      const pIdx = segs.findIndex((s) => s.toLowerCase() === "p" || s.toLowerCase() === "product");
      if (pIdx >= 0 && segs[pIdx + 1]) return humanizeUrlSlug(segs[pIdx + 1]);
    }
    if (hostLower.includes("gog.com")) {
      const gIdx = segs.findIndex((s) => s.toLowerCase() === "game");
      if (gIdx >= 0 && segs[gIdx + 1]) return humanizeUrlSlug(segs[gIdx + 1]);
    }
    if (hostLower.includes("lutris.net")) {
      const gIdx = segs.findIndex((s) => s.toLowerCase() === "games");
      const next = gIdx >= 0 ? (segs[gIdx + 1] || "") : "";
      if (next && !LUTRIS_NON_GAME_SEGMENTS.has(next.toLowerCase())) {
        return humanizeUrlSlug(next);
      }
    }
    if (hostLower.endsWith(".itch.io") && hostLower !== "itch.io") {
      const first = segs[0] || "";
      if (first && !ITCH_AUX_SEGMENTS.has(first.toLowerCase())) {
        return humanizeUrlSlug(first);
      }
    }
    return "";
  }

  function parseJsonLdTags(doc, pushTag) {
    if (!doc || !doc.querySelectorAll) return;
    const nodes = doc.querySelectorAll('script[type="application/ld+json"]');
    for (const node of nodes) {
      const raw = (node && node.textContent) || "";
      if (!raw || (!raw.includes("genre") && !raw.includes("keywords"))) continue;
      let parsed;
      try {
        parsed = JSON.parse(raw);
      } catch (_) {
        continue;
      }
      const stack = Array.isArray(parsed) ? parsed.slice() : [parsed];
      while (stack.length > 0) {
        const obj = stack.shift();
        if (!obj || typeof obj !== "object") continue;
        for (const field of ["genre", "keywords"]) {
          const val = obj[field];
          if (typeof val === "string") {
            val.split(/[,;]/).forEach((p) => pushTag(p));
          } else if (Array.isArray(val)) {
            val.forEach((v) => {
              if (typeof v === "string") pushTag(v);
            });
          }
        }
        if (Array.isArray(obj["@graph"])) {
          stack.push(...obj["@graph"]);
        }
      }
    }
  }

  function extractPageGameInfo(doc, urlStr, host) {
    const cleanUrl = String(urlStr || "");
    const lowerUrl = cleanUrl.toLowerCase();
    const cleanHost = String(host || "").toLowerCase();
    let appId = extractSteamAppIdFromUrl(cleanUrl);
    let title = "";
    const siteTags = [];
    const siteTagIds = [];
    const pushTag = (raw) => {
      const s = normalizeExtractedStoreTag(raw);
      if (s && !siteTags.includes(s) && siteTags.length < 40) {
        siteTags.push(s);
      }
    };

    let parsedUrl = null;
    try {
      parsedUrl = new URL(cleanUrl);
    } catch (_) {}

    let slugTitle = "";
    let isLutrisSingleGame = false;
    let isItchSubdomainGame = false;

    // Extract tag hub / category / genre / query tags directly from URL
    if (parsedUrl) {
      const segs = parsedUrl.pathname.split("/").filter(Boolean);
      const tIdx = segs.findIndex((s) => /^tags?$/i.test(s));
      if (tIdx >= 0) {
        const rawSlug = segs[tIdx + 2] || segs[tIdx + 1] || "";
        const tagText = decodeUriSafe(rawSlug).replace(/_/g, " ").trim();
        if (tagText.length > 2) pushTag(tagText);
      }
      const cIdx = segs.findIndex((s) => /^category$/i.test(s));
      if (cIdx >= 0 && segs[cIdx + 1]) {
        pushTag(decodeUriSafe(segs[cIdx + 1]).replace(/[_-]+/g, " ").trim());
      }
      const lutrisGIdx = cleanHost.includes("lutris.net")
        ? segs.findIndex((s) => s.toLowerCase() === "games")
        : -1;
      if (lutrisGIdx >= 0 && segs[lutrisGIdx + 1]) {
        const sub = segs[lutrisGIdx + 1].toLowerCase();
        if (sub === "genre" && segs[lutrisGIdx + 2]) {
          const gSlug = decodeUriSafe(segs[lutrisGIdx + 2]).trim();
          if (gSlug && !/^\d+$/.test(gSlug)) {
            pushTag(gSlug.replace(/[_-]+/g, " ").trim());
          }
        } else if (!LUTRIS_NON_GAME_SEGMENTS.has(sub)) {
          isLutrisSingleGame = true;
        }
      }
      if (cleanHost.endsWith(".itch.io") && cleanHost !== "itch.io") {
        const firstSeg = (segs[0] || "").toLowerCase();
        if (firstSeg && !ITCH_AUX_SEGMENTS.has(firstSeg)) {
          isItchSubdomainGame = true;
        }
      }
      for (const seg of segs) {
        const segLower = seg.toLowerCase();
        if (segLower.startsWith("tag-") && seg.length > 4) {
          pushTag(decodeUriSafe(seg.slice(4)).replace(/-/g, " ").trim());
        } else if (segLower.startsWith("genre-") && seg.length > 6) {
          pushTag(decodeUriSafe(seg.slice(6)).replace(/-/g, " ").trim());
        }
      }
      const qsParams = ["tags", "tag", "genres", "genre", "category"];
      for (const paramName of qsParams) {
        const qsVal = parsedUrl.searchParams.get(paramName) || "";
        if (!qsVal) continue;
        for (const part of qsVal.split(/[,;|]/)) {
          const p = part.trim();
          if (/^\d+$/.test(p)) {
            siteTagIds.push(parseInt(p, 10));
          } else if (p) {
            pushTag(decodeUriSafe(p).replace(/[_-]+/g, " ").trim());
          }
        }
      }
      if (!title && appId && parsedUrl.searchParams.get("redir")) {
        const redirDecoded = decodeUriSafe(parsedUrl.searchParams.get("redir"));
        const redirMatch = redirDecoded.match(/(?:^|\/)app\/\d+\/([^/?#]+)/i);
        if (redirMatch && redirMatch[1]) {
          const redirSlugTitle = redirMatch[1].replace(/[_-]+/g, " ").trim();
          if (!isGenericStorefrontTitle(redirSlugTitle)) title = redirSlugTitle;
        }
      }
      slugTitle = extractSlugTitleFromUrl(parsedUrl, cleanHost);
    }

    expandKnownTagIds(siteTagIds, []).forEach(pushTag);

    const qTermRaw = parsedUrl
      ? parsedUrl.searchParams.get("term") ||
        parsedUrl.searchParams.get("q") ||
        parsedUrl.searchParams.get("query") ||
        parsedUrl.searchParams.get("searchtext") ||
        ""
      : "";
    const qTerm = qTermRaw.trim();
    const isSearchQuery = !!qTerm;

    const isCommunitySubPage =
      lowerUrl.includes("/app/") ||
      lowerUrl.includes("/sharedfiles/") ||
      lowerUrl.includes("/workshop/") ||
      lowerUrl.includes("/discussions/") ||
      lowerUrl.includes("/guides/") ||
      lowerUrl.includes("/images/") ||
      lowerUrl.includes("/p/") ||
      lowerUrl.includes("/game/") ||
      isLutrisSingleGame ||
      isItchSubdomainGame;

    const hasUrlTagHub =
      (siteTags.length > 0 || siteTagIds.length > 0) &&
      (lowerUrl.includes("/tags/") ||
        lowerUrl.includes("/tag/") ||
        lowerUrl.includes("/category/") ||
        lowerUrl.includes("/games/genre/") ||
        /[?&](?:tags?|genres?|category)=/i.test(cleanUrl) ||
        /\/(?:tag|genre)-/i.test(lowerUrl));

    if (!doc) {
      if (isSearchQuery) {
        pushTag(qTerm);
        if (!title) title = qTerm;
      } else if (!title && slugTitle) {
        title = slugTitle;
      }
      return {
        isSingleGamePage: !!(appId || isCommunitySubPage || hasUrlTagHub || isSearchQuery),
        isSearchQuery,
        hasUrlTagHub,
        appId,
        title,
        siteTags,
        siteTagIds,
      };
    }

    // 1. Breadcrumbs or canonical links (catches /sharedfiles/filedetails guides & artworks)
    if (!appId && doc.querySelectorAll) {
      const linkEls = doc.querySelectorAll(
        'link[rel="canonical"], meta[property="og:url"], .breadcrumbs a[href*="/app/"], .apphub_OtherSiteInfo a[href*="/app/"], a.apphub_AppIcon[href*="/app/"], .game-info a.external-link[href*="store.steampowered.com/app/"]'
      );
      for (const el of linkEls) {
        const href = el.getAttribute ? el.getAttribute("href") || el.getAttribute("content") || "" : "";
        const found = extractSteamAppIdFromUrl(href);
        if (found) {
          appId = found;
          break;
        }
      }
    }

    // 2. Game title selectors (skip generic store/search/login titles!)
    const titleSelectors = [
      "#appHubAppName",
      ".apphub_AppName",
      ".workshopItemTitle",
      ".productcard-basics__title",
      ".game_header .game_title",
      ".game_title h1",
      ".product-title",
      '[data-testid="pdp-title"]',
      '[data-component="PDPTitle"]',
      "h1",
    ];
    if (!isSearchQuery) {
      for (const sel of titleSelectors) {
        const el = doc.querySelector ? doc.querySelector(sel) : null;
        const txt = stripTrademarkSymbols(el && el.textContent ? el.textContent : "");
        if (txt && !isGenericStorefrontTitle(txt)) {
          title = txt;
          break;
        }
      }
      if (!title && doc.title) {
        let cleanedTitle = String(doc.title)
          .replace(/^Comunidade Steam :: (?:Guias :: |Discuss[õo]es :: |Artwork :: |Capturas de tela :: )?/i, "")
          .replace(/^Steam Community :: (?:Guides :: |Discussions :: |Artwork :: |Screenshots :: )?/i, "")
          .replace(/\s*\|\s*(?:Baixe e compre hoje|Download and Buy Today)\s*-\s*Epic Games Store$/i, "")
          .replace(/\s+(?:na Steam|on Steam|on GOG\.com)$/i, "")
          .replace(/\s*[-|•]\s*(?:Steam|Epic Games Store|GOG\.com|itch\.io|Lutris)$/i, "")
          .trim();
        if (cleanHost.endsWith("itch.io")) {
          cleanedTitle = cleanedTitle.replace(/\s+by\s+[^-|]+$/i, "").trim();
        }
        cleanedTitle = stripTrademarkSymbols(cleanedTitle);
        if (!isGenericStorefrontTitle(cleanedTitle)) {
          title = cleanedTitle;
        }
      }
      if (!title && slugTitle) {
        title = slugTitle;
      }
    }

    // Explicit search term may match a blocked game name OR a blocked tag name
    if (qTerm && !isGenericStorefrontTitle(qTerm)) {
      pushTag(qTerm);
      if (!title) title = qTerm;
    }

    // 3. Visible tags / genres in DOM across Steam, GOG, Lutris, and Itch.io
    if (doc.querySelectorAll) {
      const tagEls = doc.querySelectorAll(
        "a.app_tag, .popular_tags a, .game_details a[href*='tags='], .workshopTags a, a[href*='genres='], .genres__item, .game-details a[href*='/games/genre/'], .game-info a[href*='/games/genre/'], .game_info_panel_widget a[href*='/games/tag-'], .game_info_panel_widget a[href*='/games/genre-'], .tags a[href*='/games/tag-']"
      );
      for (const t of tagEls) {
        const txt = (t.textContent || "").trim();
        if (txt && txt !== "+") pushTag(txt);
      }
      doc.querySelectorAll(".game-info li, .game-details li, .game-details .small-text").forEach((li) => {
        const raw = (li.textContent || "").replace(/\s+/g, " ").trim();
        const m = raw.match(/^(?:Genres?|G[êe]neros?)\s*:\s*(.+)$/i);
        if (m && m[1]) {
          m[1].split(/[,;]/).forEach(pushTag);
        }
      });
      doc.querySelectorAll(".game_info_panel_widget tr").forEach((tr) => {
        const cells = tr.querySelectorAll ? tr.querySelectorAll("td, th") : [];
        if (cells.length >= 2) {
          const label = foldMatchText(cells[0].textContent || "");
          if (label === "genre" || label === "genres" || label === "genero" || label === "generos" || label === "tags") {
            const valLinks = cells[1].querySelectorAll ? cells[1].querySelectorAll("a") : [];
            if (valLinks.length > 0) {
              valLinks.forEach((a) => pushTag(a.textContent || ""));
            } else {
              String(cells[1].textContent || "").split(/[,;]/).forEach(pushTag);
            }
          }
        }
      });
      if (cleanHost.endsWith("itch.io")) {
        parseJsonLdTags(doc, pushTag);
      }
    }

    const isSingleGamePage = !!(appId || isCommunitySubPage || hasUrlTagHub || isSearchQuery);
    return {
      isSingleGamePage,
      isSearchQuery,
      hasUrlTagHub,
      appId,
      title,
      siteTags,
      siteTagIds,
    };
  }

  function createLauncherDomFilter() {
    let lastFilterSig = "";
    let lastUrlStr = "";
    const resolvedCache = new Map(); // cacheKey -> { title, tags, blocked, reason }
    const inflightKeys = new Set();
    let blockedNavTriggered = false;
    let scanTimer = null;

    function filterSignature(filters) {
      return JSON.stringify([
        !!filters.launcherFilterEnabled,
        filters.launcherBlockedTags || [],
        filters.launcherBlockedNames || [],
      ]);
    }

    function hideCard(el) {
      if (!el || !el.style) return;
      el.setAttribute("data-chronos-launcher-hidden", "1");
      el.style.setProperty("display", "none", "important");
    }

    function restoreAllHidden(doc) {
      if (!doc || !doc.querySelectorAll) return;
      doc.querySelectorAll('[data-chronos-launcher-hidden="1"]').forEach((el) => {
        el.removeAttribute("data-chronos-launcher-hidden");
        if (el.style) el.style.removeProperty("display");
      });
    }

    function parseIdArrayAttr(el, attrName) {
      if (!el || !el.getAttribute) return [];
      const raw = String(el.getAttribute(attrName) || "").trim();
      if (!raw) return [];
      if (raw.startsWith("[")) {
        try {
          const arr = JSON.parse(raw);
          if (Array.isArray(arr)) {
            return arr.map((x) => parseInt(x, 10)).filter((n) => Number.isFinite(n) && n > 0);
          }
        } catch (_) {}
      }
      return raw
        .split(/[\s,;]+/)
        .map((p) => (/^\d+$/.test(p) ? parseInt(p, 10) : 0))
        .filter((n) => n > 0);
    }

    function countDistinctGameLinks(container) {
      if (!container || !container.querySelectorAll) return 0;
      const seenKeys = new Set();
      let links;
      try {
        links = container.querySelectorAll(
          'a[href*="/app/"], [data-ds-appid], a[href*="/p/"], a[href*="/game/"], a[href*="/games/"], .game_cell a.title'
        );
      } catch (_) {
        return 0;
      }
      for (const n of links) {
        const href = (n.getAttribute && n.getAttribute("href")) || "";
        const id = extractSteamAppIdFromUrl(href) || parseIdArrayAttr(n, "data-ds-appid")[0];
        if (id) {
          seenKeys.add(`app:${id}`);
        } else if (href && !/\/games\/(?:genre|platform|tag)/i.test(href)) {
          seenKeys.add(`href:${href.split(/[?#]/)[0]}`);
        }
        if (seenKeys.size > 1) return seenKeys.size;
      }
      return seenKeys.size;
    }

    function resolveCardContainer(el, host) {
      if (!el || el.tagName !== "A" || typeof el.closest !== "function") return el;
      if (el.closest("header, nav, footer, #global_header, .supernav_container, .breadcrumbs, .store_nav")) {
        return null;
      }
      const explicit = el.closest(
        '[data-ds-appid], .search_result_row, .tab_item, .store_capsule, .home_area_spotlight, .sale_item, .apphub_Card, .workshopItem, [data-component="OfferCard"], [data-testid="offer-card"], product-tile, .product-tile:not(a), .game-preview, .game_cell, article'
      );
      if (explicit) return explicit;
      let best = el;
      let cur = el.parentElement;
      for (let depth = 0; depth < 4 && cur && cur.tagName; depth++) {
        const tag = cur.tagName.toUpperCase();
        if (tag === "BODY" || tag === "MAIN" || tag === "SECTION" || tag === "HEADER" || tag === "NAV" || tag === "FOOTER") {
          break;
        }
        if (countDistinctGameLinks(cur) > 1) break;
        const cls = String(cur.className || "").toLowerCase();
        if (
          tag === "LI" ||
          cls.includes("capsule") ||
          cls.includes("widget") ||
          cls.includes("card") ||
          cls.includes("item") ||
          cls.includes("tile") ||
          cls.includes("spotlight") ||
          cls.includes("impression") ||
          cls.includes("offer")
        ) {
          best = cur;
        }
        cur = cur.parentElement;
      }
      return best;
    }

    function cleanStoreCardTitle(rawText) {
      let txt = stripTrademarkSymbols(String(rawText || "").replace(/\s+/g, " "));
      if (!txt) return "";
      txt = txt
        .replace(/^(?:Jogo Base|Base Game|Complemento|Add-On|Edi[çc][ãa]o|Edition|Novo|New|Em breve|Coming Soon)\s*[,|•:\-]?\s*/i, "")
        .replace(/\s*[,|•]\s*(?:R\$|\$|€|£|Gr[áa]tis|Free|-\d+%).*$/i, "")
        .replace(/\s+(?:-\d+%\s*)?(?:R\$|\$|€|£)\s*\d[\d.,]*(?:\s*(?:R\$|\$|€|£)\s*\d[\d.,]*)*$/i, "")
        .replace(/\s+(?:Gr[áa]tis|Free(?:\s+to\s+Play)?|Compre agora|Buy Now|Em breve|Coming Soon)$/i, "")
        .trim();
      return stripTrademarkSymbols(txt);
    }

    function hasAncestorInSet(el, seenSet) {
      let cur = el && el.parentElement;
      for (let d = 0; d < 6 && cur; d++) {
        if (seenSet.has(cur)) return true;
        cur = cur.parentElement;
      }
      return false;
    }

    function extractCards(doc, host) {
      if (!doc || !doc.querySelectorAll) return [];
      const h = String(host || "").toLowerCase();
      const isSteam = h.includes("store.steampowered.com") || h.includes("steamcommunity.com");
      const selectors = isSteam
        ? [
            "[data-ds-appid]",
            "a.search_result_row",
            ".tab_item",
            ".store_capsule",
            ".home_area_spotlight",
            ".sale_item_browser .sale_item",
            ".apphub_Card",
            ".workshopItem",
            'a[href*="/app/"]',
          ]
        : h.includes("epicgames.com")
          ? ['[data-component="OfferCard"]', '[data-testid="offer-card"]', "article", 'a[href*="/p/"]']
          : h.includes("gog.com")
            ? ["product-tile", ".product-tile", 'a[href*="/game/"]']
            : h.includes("lutris.net")
              ? [".game-preview", 'a[href*="/games/"]']
              : [".game_cell"];

      const seen = new Set();
      const cards = [];
      for (const sel of selectors) {
        let els;
        try {
          els = doc.querySelectorAll(sel);
        } catch (_) {
          continue;
        }
        for (const rawEl of els) {
          const isFallbackLink = sel.startsWith("a[href*=") || (rawEl && rawEl.tagName === "A");
          const el = isFallbackLink ? resolveCardContainer(rawEl, h) : rawEl;
          if (!el || seen.has(el) || hasAncestorInSet(el, seen)) continue;
          if (el.closest && el.closest("header, nav, footer")) continue;

          const linkEl = el.tagName === "A" ? el : (el.querySelector && el.querySelector("a[href]"));
          const href = (el.getAttribute && el.getAttribute("href")) || (linkEl && linkEl.getAttribute("href")) || "";
          if (h.includes("lutris.net") && href && /\/games\/(?:genre|platform|tags?|category|search|year|company|series)\b/i.test(href)) {
            continue;
          }
          seen.add(el);

          const attrAppIds = parseIdArrayAttr(el, "data-ds-appid").concat(parseIdArrayAttr(el, "data-appid"));
          const urlAppId = extractSteamAppIdFromUrl(href);
          const appId = attrAppIds[0] || urlAppId || null;

          let title = "";
          const titleEl =
            el.querySelector &&
            el.querySelector(
              '[data-testid="offer-title-info-title"], [data-component="OfferTitleInfo"], .product-tile__title, .game-name, .game_title a, .game_title, .title, .tab_item_name, .search_name, .apphub_CardContentTitle, .workshopItemTitle, h3, h2'
            );
          if (titleEl) {
            const attrTitle = titleEl.getAttribute ? titleEl.getAttribute("title") : "";
            const rawTxt = attrTitle && !isGenericStorefrontTitle(attrTitle) ? attrTitle : titleEl.textContent;
            if (rawTxt) title = cleanStoreCardTitle(rawTxt);
          }
          if (!title && el.querySelector) {
            const img = el.querySelector("img[alt]");
            const alt = img ? cleanStoreCardTitle(img.getAttribute("alt") || "") : "";
            if (alt && !isGenericStorefrontTitle(alt) && alt.length <= 120) {
              title = alt;
            }
          }
          if (!title) {
            const aria =
              (el.getAttribute && el.getAttribute("aria-label")) ||
              (linkEl && linkEl.getAttribute && linkEl.getAttribute("aria-label")) ||
              "";
            if (aria) {
              const cleanedAria = cleanStoreCardTitle(aria);
              if (cleanedAria && !isGenericStorefrontTitle(cleanedAria) && cleanedAria.length <= 120) {
                title = cleanedAria;
              }
            }
          }
          if (!title && href) {
            try {
              const parsedHref = new URL(href, "https://" + (h || "example.com"));
              const slugTitle = extractSlugTitleFromUrl(parsedHref, h);
              if (slugTitle) title = slugTitle;
            } catch (_) {}
          }
          if (!title && el.tagName === "A" && el.textContent) {
            const linkTxt = cleanStoreCardTitle(el.textContent);
            if (linkTxt && linkTxt.length <= 120 && !isGenericStorefrontTitle(linkTxt)) {
              title = linkTxt;
            }
          }

          const siteTagIds = parseIdArrayAttr(el, "data-ds-tagids");
          const descIds = parseIdArrayAttr(el, "data-ds-descids");
          const siteTags = expandKnownTagIds(siteTagIds, descIds);
          const pushCardTag = (rawTag) => {
            const tClean = normalizeExtractedStoreTag(rawTag);
            if (tClean && !siteTags.includes(tClean)) siteTags.push(tClean);
          };
          if (el.querySelectorAll) {
            el.querySelectorAll(
              ".tab_item_top_tags .top_tag, .search_tags span, .game_genre, .tag_link, a[href*='/games/tag-'], .game-details a[href*='/games/genre/'], .game_details a[href*='/games/genre/']"
            ).forEach((tg) => pushCardTag(tg.textContent || ""));
            if (h.includes("lutris.net")) {
              el.querySelectorAll(".game-details .small-text, .game_details .small-text").forEach((st) => {
                const rawSt = (st.textContent || "").replace(/\s+/g, " ").trim();
                const gm = rawSt.match(/^(?:Genres?|G[êe]neros?)\s*:\s*(.+)$/i);
                if (gm && gm[1]) {
                  gm[1].split(/[,;]/).forEach(pushCardTag);
                }
              });
            }
          }

          if (appId || (title && !isGenericStorefrontTitle(title))) {
            cards.push({ el, href, appId, title, siteTags, siteTagIds, descIds });
          }
        }
      }
      return cards;
    }

    function apply(rawFilters, opts) {
      const cfg = opts || {};
      const doc = cfg.document || (typeof document !== "undefined" ? document : null);
      if (!doc) return;
      const loc = cfg.location || (typeof window !== "undefined" ? window.location : null);
      const urlStr = cfg.url || (loc && loc.href) || "";
      const host = String(cfg.host || (loc && loc.hostname) || "").toLowerCase();
      const filters = normalizeFilters(rawFilters);

      const sig = filterSignature(filters);
      if (sig !== lastFilterSig) {
        lastFilterSig = sig;
        resolvedCache.clear();
        blockedNavTriggered = false;
      }
      if (urlStr !== lastUrlStr) {
        lastUrlStr = urlStr;
        blockedNavTriggered = false;
      }

      const active =
        isLauncherStoreHost(host) &&
        filters.launcherFilterEnabled &&
        ((filters.launcherBlockedTags && filters.launcherBlockedTags.length > 0) ||
          (filters.launcherBlockedNames && filters.launcherBlockedNames.length > 0));

      if (!active) {
        restoreAllHidden(doc);
        return;
      }

      // 1. Check current single-game / guide / discussion / artwork / tag-hub page -> full site block
      const pageInfo = extractPageGameInfo(doc, urlStr, host);
      if (pageInfo.isSingleGamePage) {
        const localHit = matchLocalGame(pageInfo.title, pageInfo.siteTags, filters);
        if (localHit) {
          if (
            !pageInfo.isSearchQuery &&
            pageInfo.title &&
            !isGenericStorefrontTitle(pageInfo.title) &&
            pageInfo.siteTags &&
            pageInfo.siteTags.length > 0 &&
            typeof cfg.resolveItems === "function" &&
            !blockedNavTriggered
          ) {
            try {
              cfg.resolveItems(
                [
                  {
                    id: "__learn__",
                    appId: pageInfo.appId,
                    url: urlStr,
                    title: pageInfo.title,
                    siteTags: pageInfo.siteTags,
                    siteTagIds: pageInfo.siteTagIds || [],
                    descIds: [],
                    isSingleGamePage: true,
                    isSearchQuery: false,
                  },
                ],
                () => {},
                { keepalive: true }
              );
            } catch (_) {}
          }
          if (!blockedNavTriggered && typeof cfg.onBlockPage === "function") {
            blockedNavTriggered = true;
            cfg.onBlockPage({
              title: pageInfo.title || (pageInfo.siteTags && pageInfo.siteTags[0]) || host,
              reason: localHit.reason,
              appId: pageInfo.appId,
              url: urlStr,
            });
          }
          return;
        }
      }

      const BATCH_LIMIT = 60;
      const pendingItems = [];
      const cardById = new Map();

      const shouldResolvePage =
        pageInfo.isSingleGamePage &&
        (pageInfo.appId ||
          pageInfo.hasUrlTagHub ||
          (!pageInfo.isSearchQuery && pageInfo.title && !isGenericStorefrontTitle(pageInfo.title)));

      if (shouldResolvePage) {
        const pKey = pageInfo.appId
          ? `app:${pageInfo.appId}`
          : pageInfo.hasUrlTagHub
            ? `hub:${urlStr}`
            : `t:${foldMatchText(pageInfo.title)}`;
        const cachedPage = resolvedCache.get(pKey);
        if (cachedPage) {
          if (cachedPage.blocked && !blockedNavTriggered && typeof cfg.onBlockPage === "function") {
            blockedNavTriggered = true;
            cfg.onBlockPage({
              title: cachedPage.title || pageInfo.title || host,
              reason: cachedPage.reason,
              appId: pageInfo.appId,
              url: urlStr,
            });
            return;
          }
        } else if (!inflightKeys.has(pKey)) {
          inflightKeys.add(pKey);
          pendingItems.push({
            id: "__page__",
            cacheKey: pKey,
            appId: pageInfo.appId,
            url: urlStr,
            title: pageInfo.title,
            siteTags: pageInfo.siteTags,
            siteTagIds: pageInfo.siteTagIds || [],
            descIds: [],
            isPage: true,
            isSingleGamePage: true,
            isSearchQuery: !!pageInfo.isSearchQuery,
          });
        }
      }

      // 2. Filter storefront / community listing cards
      const cardsByKey = new Map();
      const cards = extractCards(doc, host);
      let hasMorePending = false;

      for (const card of cards) {
        const localHit = matchLocalGame(card.title, card.siteTags, filters);
        if (localHit) {
          hideCard(card.el);
          continue;
        }
        const cKey = card.appId ? `app:${card.appId}` : `t:${foldMatchText(card.title)}`;
        const cached = resolvedCache.get(cKey);
        if (cached) {
          if (cached.blocked) hideCard(card.el);
          continue;
        }
        let list = cardsByKey.get(cKey);
        if (!list) {
          list = [];
          cardsByKey.set(cKey, list);
        }
        list.push(card.el);
        if (!inflightKeys.has(cKey)) {
          if (pendingItems.length < BATCH_LIMIT) {
            inflightKeys.add(cKey);
            const itemId = `c:${pendingItems.length}`;
            cardById.set(itemId, { card, cacheKey: cKey });
            pendingItems.push({
              id: itemId,
              cacheKey: cKey,
              appId: card.appId,
              url: card.href,
              title: card.title,
              siteTags: card.siteTags,
              siteTagIds: card.siteTagIds || [],
              descIds: card.descIds || [],
              isSingleGamePage: false,
              isSearchQuery: false,
            });
          } else {
            hasMorePending = true;
          }
        }
      }

      if (pendingItems.length > 0 && typeof cfg.resolveItems === "function") {
        const hasPageItem = pendingItems.some((p) => p.isPage);
        const payloadItems = pendingItems.map(
          ({ id, appId, url, title, siteTags, siteTagIds, descIds, isSingleGamePage, isSearchQuery }) => ({
            id,
            appId,
            url,
            title,
            siteTags,
            siteTagIds,
            descIds,
            isSingleGamePage: !!isSingleGamePage,
            isSearchQuery: !!isSearchQuery,
          })
        );
        cfg.resolveItems(
          payloadItems,
          (resp) => {
            for (const it of pendingItems) inflightKeys.delete(it.cacheKey);
            if (!resp || resp.success === false || !Array.isArray(resp.results)) return;
            for (const res of resp.results) {
              const orig = pendingItems.find((p) => p.id === res.id);
              if (!orig) continue;
              if (!res.transientError) {
                resolvedCache.set(orig.cacheKey, {
                  title: res.title || orig.title,
                  tags: res.tags || [],
                  blocked: !!res.blocked,
                  reason: res.reason || "",
                });
              }
            if (res.blocked) {
              if (orig.isPage) {
                if (!blockedNavTriggered && typeof cfg.onBlockPage === "function") {
                  blockedNavTriggered = true;
                  cfg.onBlockPage({
                    title: res.title || pageInfo.title || host,
                    reason: res.reason || "Filtro de launcher ativo",
                    appId: orig.appId,
                    url: urlStr,
                  });
                }
              } else {
                const els = cardsByKey.get(orig.cacheKey) || [];
                for (const el of els) hideCard(el);
                const hit = cardById.get(res.id);
                if (hit) hideCard(hit.card.el);
              }
            }
          }
          // Re-apply against live DOM (catches React node replacements) and continue remaining batches (>60 cards)
          if (hasMorePending) {
            scheduleScan(rawFilters, opts, 30);
          } else {
            try {
              const latestCards = extractCards(doc, host);
              for (const lc of latestCards) {
                const k = lc.appId ? `app:${lc.appId}` : `t:${foldMatchText(lc.title)}`;
                const c = resolvedCache.get(k);
                if (c && c.blocked) hideCard(lc.el);
              }
            } catch (_) {}
          }
        },
        { keepalive: hasPageItem }
        );
      }
    }

    function scheduleScan(rawFilters, opts, delayMs) {
      if (scanTimer) return;
      scanTimer = setTimeout(() => {
        scanTimer = null;
        apply(rawFilters, opts);
      }, typeof delayMs === "number" ? delayMs : 120);
    }

    function setTagCatalogMap(tagMap) {
      if (tagMap && typeof tagMap === "object") {
        dynamicSteamTagMap = tagMap;
      }
    }

    return {
      isLauncherStoreHost,
      isGenericStorefrontTitle,
      extractSteamAppIdFromUrl,
      extractPageGameInfo,
      matchLocalGame,
      expandKnownTagIds,
      setTagCatalogMap,
      apply,
      scheduleScan,
    };
  }

  /**
   * YouTube "mostrar apenas": reveals feed/related cards whose video type is allowed,
   * keeps the rest hidden (CSS hides unmarked cards), and skips disallowed Shorts.
   * opts: { document, location, classifyItems(items, done), skipShort() }
   */
  function createYoutubeTypeFilter() {
    const cache = new Map(); // videoId -> { types: [], known: bool, at: ms }
    const inflight = new Set();
    const RETRY_UNKNOWN_MS = 20000;
    const CARD_SELECTOR = [
      'ytd-browse[page-subtype="home"] ytd-rich-item-renderer',
      'ytd-browse[page-subtype="subscriptions"] ytd-rich-item-renderer',
      "ytd-watch-next-secondary-results-renderer ytd-compact-video-renderer",
      "ytd-watch-next-secondary-results-renderer yt-lockup-view-model",
    ].join(", ");
    let skippedShortId = "";

    function videoIdFromHref(href) {
      const h = String(href || "");
      const m = h.match(/[?&]v=([A-Za-z0-9_-]{11})/) || h.match(/\/shorts\/([A-Za-z0-9_-]{11})/);
      return m ? m[1] : "";
    }

    function cardVideoId(el) {
      if (!el || !el.querySelector) return "";
      const a = el.querySelector('a[href*="watch?v="], a[href*="/shorts/"]');
      return a ? videoIdFromHref(a.getAttribute("href")) : "";
    }

    function isAllowed(entry, allowed) {
      return !!entry && entry.known && entry.types.some((t) => allowed.has(String(t).toLowerCase()));
    }

    function fresh(entry) {
      return entry && (entry.known || Date.now() - entry.at < RETRY_UNKNOWN_MS);
    }

    function request(ids, opts, rerun) {
      const pending = ids.filter((id) => !inflight.has(id) && !fresh(cache.get(id))).slice(0, 40);
      if (!pending.length || typeof opts.classifyItems !== "function") return;
      pending.forEach((id) => inflight.add(id));
      opts.classifyItems(
        pending.map((id) => ({ id, videoId: id })),
        (resp) => {
          pending.forEach((id) => inflight.delete(id));
          const results = resp && Array.isArray(resp.results) ? resp.results : [];
          for (const r of results) {
            cache.set(r.id, { types: Array.isArray(r.types) ? r.types : [], known: !!r.known, at: Date.now() });
          }
          for (const id of pending) {
            if (!cache.has(id)) cache.set(id, { types: [], known: false, at: Date.now() });
          }
          rerun();
        }
      );
    }

    function apply(rawFilters, opts) {
      const filters = normalizeFilters(rawFilters);
      const doc = opts && opts.document;
      const loc = opts && opts.location;
      if (!doc || !loc || !filters.ytShowOnlyEnabled) return;
      const host = String(loc.hostname || "").toLowerCase();
      if (!host.includes("youtube.com")) return;
      const allowed = new Set(filters.ytShowOnlyTypes);
      const rerun = () => apply(rawFilters, opts);

      // Feed / related cards
      const unknown = [];
      for (const el of doc.querySelectorAll ? doc.querySelectorAll(CARD_SELECTOR) : []) {
        const id = cardVideoId(el);
        if (!id) continue;
        const entry = cache.get(id);
        if (isAllowed(entry, allowed)) {
          if (el.getAttribute("data-chronos-yt-ok") !== "1") el.setAttribute("data-chronos-yt-ok", "1");
        } else {
          if (el.getAttribute("data-chronos-yt-ok") === "1") el.removeAttribute("data-chronos-yt-ok");
          if (!fresh(entry)) unknown.push(id);
        }
      }
      if (unknown.length) request(unknown, opts, rerun);

      // Shorts: skip disallowed ones (only when Shorts are not blocked entirely)
      const path = String(loc.pathname || "");
      const m = path.match(/^\/shorts\/([A-Za-z0-9_-]{11})/);
      if (m && !filters.ytBlockShorts) {
        const id = m[1];
        const entry = cache.get(id);
        if (!fresh(entry)) {
          request([id], opts, rerun);
        } else if (!isAllowed(entry, allowed) && skippedShortId !== id) {
          skippedShortId = id;
          if (typeof opts.skipShort === "function") opts.skipShort();
        }
      }
    }

    return { apply, videoIdFromHref, _cache: cache };
  }

  /**
   * +18 content on Reddit and X: hides flagged posts (marks them with
   * data-chronos-nsfw="1", hidden by buildFocusCss) and reports pages that are adult
   * as a whole (NSFW subreddit/post, sensitive X profile) so the caller can block them.
   */
  const X_SENSITIVE_RE =
    /(content warning|aviso de conte[uú]do|potentially sensitive|potencialmente sens[ií]vel|conte[uú]do sens[ií]vel|sensitive content|m[ií]dia sens[ií]vel|sensitive media)/i;
  const X_SENSITIVE_PROFILE_RE =
    /(may include potentially sensitive content|pode incluir conte[uú]do potencialmente sens[ií]vel|this profile may include|este perfil pode incluir)/i;
  const X_SENSITIVE_COMMUNITY_RE =
    /(this community (may contain|contains) (potentially )?sensitive|nsfw community|comunidade (pode conter|cont[eé]m) conte[uú]do (potencialmente )?sens[ií]vel|adult content|conte[uú]do adulto)/i;
  const REDDIT_GATE_RE =
    /(mature content|you must be (at least )?18|over 18|maiores de 18|conte[uú]do adulto|voc[eê] tem 18 anos|confirm(e)? (que )?(voc[eê] )?tem 18)/i;

  function markHidden(el) {
    if (el && el.getAttribute && el.getAttribute("data-chronos-nsfw") !== "1") {
      el.setAttribute("data-chronos-nsfw", "1");
    }
  }

  // signals (optional): { tweets: Set<id>, users: Set<lowercase handle> } reported by
  // x_sensitive_hook.js from X's own API data (possibly_sensitive flags).
  function scanAdultSocial(rawFilters, hostInput, pathInput, doc, signals) {
    const sigTweets = signals && signals.tweets ? signals.tweets : null;
    const sigUsers = signals && signals.users ? signals.users : null;
    const sigCommunities = signals && signals.communities ? signals.communities : null;
    const filters = normalizeFilters(rawFilters);
    const host = String(hostInput || "").toLowerCase();
    const path = String(pathInput || "/");
    if (!doc || !doc.querySelectorAll) return null;

    if (host.includes("reddit.com") && filters.rdBlockNsfw) {
      if (path.startsWith("/over18")) return "Subreddit +18 bloqueado pelo Chronos";
      // Search/feed units flagged with an "NSFW" badge.
      doc.querySelectorAll("[data-testid='search-post-unit'], faceplate-tracker, search-telemetry-tracker, .Post").forEach((unit) => {
        if (unit.getAttribute("data-chronos-nsfw") === "1") return;
        const badges = unit.querySelectorAll("span, faceplate-tag, .nsfw-stamp, [data-testid='nsfw-badge']");
        for (const b of badges) {
          if ((b.textContent || "").trim().toUpperCase() === "NSFW") {
            markHidden(unit);
            break;
          }
        }
      });
      const isPost = /\/comments\//.test(path);
      if (isPost) {
        const main = doc.querySelector("shreddit-post");
        if (main && main.hasAttribute("nsfw")) return "Post +18 bloqueado pelo Chronos";
        if (doc.querySelector(".thing.over18.link, #siteTable .over18")) return "Post +18 bloqueado pelo Chronos";
      }
      const isSub = /^\/r\/[^/]+\/?$/.test(path) || /^\/r\/[^/]+\/(hot|new|top|rising)\/?/.test(path);
      if (isSub || isPost) {
        if (doc.querySelector("shreddit-async-loader[bundlename*='nsfw' i], xpromo-nsfw-blocking-container, nsfw-blocking-modal, [data-testid='nsfw-blocking-modal']")) {
          return "Subreddit +18 bloqueado pelo Chronos";
        }
        const gate = doc.querySelector("[role='dialog'], dialog, .interstitial");
        if (gate && REDDIT_GATE_RE.test(gate.textContent || "")) return "Subreddit +18 bloqueado pelo Chronos";
        const posts = doc.querySelectorAll("shreddit-post");
        if (isSub && posts.length >= 4) {
          let nsfw = 0;
          posts.forEach((p) => {
            if (p.hasAttribute("nsfw")) nsfw += 1;
          });
          if (nsfw / posts.length >= 0.6) return "Subreddit +18 bloqueado pelo Chronos";
        }
      }
    }

    if ((host.includes("twitter.com") || host === "x.com" || host.endsWith(".x.com")) && filters.twBlockSensitive) {
      doc.querySelectorAll("article[data-testid='tweet'], article").forEach((art) => {
        if (art.getAttribute("data-chronos-nsfw") === "1") return;
        let flagged = X_SENSITIVE_RE.test(art.textContent || "");
        if (!flagged && (sigTweets || sigUsers) && art.querySelectorAll) {
          for (const a of art.querySelectorAll("a[href]")) {
            const href = a.getAttribute("href") || "";
            const cm = href.match(/^\/i\/communities\/(\d+)/);
            if (cm && sigCommunities && sigCommunities.has(cm[1])) {
              flagged = true;
              break;
            }
            const m = href.match(/^\/([A-Za-z0-9_]{1,15})(?:\/status\/(\d+))?/);
            if (!m) continue;
            if (m[2] && sigTweets && sigTweets.has(m[2])) flagged = true;
            if (!m[2] && sigUsers && sigUsers.has(m[1].toLowerCase())) flagged = true;
            if (m[2] && sigUsers && sigUsers.has(m[1].toLowerCase())) flagged = true;
            if (flagged) break;
          }
        }
        if (flagged) {
          const cell = art.closest ? art.closest("[data-testid='cellInnerDiv']") : null;
          markHidden(cell || art);
        }
      });
      const primary = doc.querySelector("[data-testid='primaryColumn']") || doc.body;
      const segs = path.split("/").filter(Boolean);
      // Community pages: /i/communities/<id>
      if (segs[0] === "i" && segs[1] === "communities" && /^\d+$/.test(segs[2] || "")) {
        if (sigCommunities && sigCommunities.has(segs[2])) return "Comunidade +18 bloqueada pelo Chronos";
        if (primary && X_SENSITIVE_COMMUNITY_RE.test(primary.textContent || "")) {
          return "Comunidade +18 bloqueada pelo Chronos";
        }
      }
      const reserved = ["home", "explore", "search", "notifications", "messages", "i", "settings", "compose"];
      if (segs.length >= 1 && !reserved.includes(segs[0].toLowerCase())) {
        const handle = segs[0].toLowerCase();
        if (sigUsers && sigUsers.has(handle)) return "Perfil +18 bloqueado pelo Chronos";
        if (segs[1] === "status" && segs[2] && sigTweets && sigTweets.has(segs[2])) return "Post +18 bloqueado pelo Chronos";
        if (primary && X_SENSITIVE_PROFILE_RE.test(primary.textContent || "")) return "Perfil +18 bloqueado pelo Chronos";
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Local image AI (+18): decision rules + page-side blur/scan.

  const NSFW_MIN_SIDE = 96;

  function isNsfwVerdict(p) {
    if (!p) return false;
    return (p.porn || 0) >= 0.6 || (p.hentai || 0) >= 0.6 || (p.sexy || 0) >= 0.85;
  }

  function shouldBlockImagePage(nsfwCount, analyzedCount) {
    return nsfwCount >= 4 || (analyzedCount >= 4 && nsfwCount / analyzedCount > 0.5);
  }

  function hostInAllowlist(host, allowlist) {
    const h = String(host || "").toLowerCase().replace(/^www\./, "");
    return (allowlist || []).some((a) => {
      const x = String(a || "").toLowerCase().replace(/^www\./, "");
      return x && (h === x || h.endsWith("." + x));
    });
  }

  /**
   * Blurs every big-enough <img> until it is classified; +18 ones stay blurred.
   * opts: { document, location, classify(url) -> Promise<{nsfw:boolean}|null>, onBlockPage(reason) }
   */
  function createImageNsfwFilter() {
    let page = "";
    let nsfw = 0;
    let analyzed = 0;
    let reported = false;
    const STYLE_ID = "chronos-nsfw-style";

    function removeStyle(doc) {
      const el = doc.getElementById && doc.getElementById(STYLE_ID);
      if (el && el.parentNode) el.parentNode.removeChild(el);
    }

    function ensureStyle(doc) {
      if (!doc.getElementById || doc.getElementById(STYLE_ID)) return;
      const st = doc.createElement("style");
      st.id = STYLE_ID;
      st.textContent =
        'img[data-chronos-img="pending"],img[data-chronos-img="nsfw"]{filter:blur(24px)!important;}';
      (doc.head || doc.documentElement).appendChild(st);
    }

    function apply(cfg, opts) {
      const doc = opts && opts.document;
      if (!doc || !doc.querySelectorAll) return;
      const loc = opts.location || {};
      const host = String(loc.hostname || "").toLowerCase();
      const off =
        !cfg ||
        !cfg.imageAi ||
        host === "127.0.0.1" ||
        host === "localhost" ||
        hostInAllowlist(host, cfg.allowlist);
      if (off) {
        removeStyle(doc);
        doc.querySelectorAll('img[data-chronos-img="pending"]').forEach((img) => img.setAttribute("data-chronos-img", "ok"));
        return;
      }
      if (loc.href !== page) {
        page = loc.href;
        nsfw = 0;
        analyzed = 0;
        reported = false;
      }
      ensureStyle(doc);
      doc.querySelectorAll("img").forEach((img) => {
        const src = img.currentSrc || img.src || "";
        if (!src || /^(blob:|chrome|moz-extension:|about:)/i.test(src)) return;
        if (img.getAttribute("data-chronos-src") === src) return;
        const wAttr = parseInt(img.getAttribute("width") || "0", 10);
        const hAttr = parseInt(img.getAttribute("height") || "0", 10);
        const loadedSmall =
          img.complete && img.naturalWidth > 0 && (img.naturalWidth < NSFW_MIN_SIDE || img.naturalHeight < NSFW_MIN_SIDE);
        const declaredSmall = wAttr > 0 && hAttr > 0 && (wAttr < NSFW_MIN_SIDE || hAttr < NSFW_MIN_SIDE);
        img.setAttribute("data-chronos-src", src);
        if (loadedSmall || declaredSmall || /\.svg(\?|$)/i.test(src)) {
          img.setAttribute("data-chronos-img", "ok");
          return;
        }
        img.setAttribute("data-chronos-img", "pending");
        const pageAtStart = page;
        Promise.resolve(opts.classify(src))
          .then((res) => {
            if (img.getAttribute("data-chronos-src") !== src) return;
            const isNsfw = !!(res && res.nsfw);
            img.setAttribute("data-chronos-img", isNsfw ? "nsfw" : "ok");
            if (pageAtStart !== page || !res || res.skipped) return;
            analyzed += 1;
            if (isNsfw) nsfw += 1;
            if (!reported && shouldBlockImagePage(nsfw, analyzed) && typeof opts.onBlockPage === "function") {
              reported = true;
              opts.onBlockPage("Imagens +18 bloqueadas pelo Chronos");
            }
          })
          .catch(() => {
            if (img.getAttribute("data-chronos-src") === src) img.setAttribute("data-chronos-img", "ok");
          });
      });
    }

    return { apply, _counts: () => ({ nsfw, analyzed }) };
  }

  const imageNsfwFilter = createImageNsfwFilter();

  const launcherDomFilter = createLauncherDomFilter();
  const youtubeTypeFilter = createYoutubeTypeFilter();

  globalScope.ChronosFocusCore = {
    normalizeFilters,
    buildFocusCss,
    getRedirectTarget,
    syncHtmlAttributes,
    foldMatchText,
    normalizeTermList,
    launcherDomFilter,
    createLauncherDomFilter,
    youtubeTypeFilter,
    createYoutubeTypeFilter,
    scanAdultSocial,
    isNsfwVerdict,
    shouldBlockImagePage,
    hostInAllowlist,
    createImageNsfwFilter,
    imageNsfwFilter,
  };
  globalScope.ChronosLauncherDomFilter = launcherDomFilter;
  globalScope.ChronosYoutubeTypeFilter = youtubeTypeFilter;

  if (typeof module !== "undefined" && module.exports) {
    module.exports = globalScope.ChronosFocusCore;
  }
})(typeof globalThis !== "undefined" ? globalThis : this);
