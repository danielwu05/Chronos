// Chronos Focus Engine - Shared Minimal Pill, Draggable Eye & App-Miniature HUD (Extension + Proxy)
(function (globalScope) {
  const POS_STORAGE_KEY = "chronos_hud_pos_v1";
  const MODE_SESSION_KEY = "chronos_hud_mode_v1";
  const LEGACY_HIDDEN_KEY = "chronos_hud_hidden_v1";

  const FILTER_GROUPS = [
    {
      title: "DETOX GLOBAL",
      cls: "c-grp-gl",
      items: [
        ["globalGrayscale", "Modo Preto e Branco (Grayscale)"],
        ["globalBlockNotifications", "Bloquear Notificações / Badges"],
      ],
    },
    {
      title: "YOUTUBE",
      cls: "c-grp-yt",
      items: [
        ["ytBlockShorts", "Bloquear Shorts"],
        ["ytEducationalMode", "Modo Educativo (Ocultar Feed Home)"],
        ["ytBlockSidebar", "Ocultar Vídeos Relacionados"],
        ["ytBlockComments", "Ocultar Comentários"],
      ],
    },
    {
      title: "INSTAGRAM",
      cls: "c-grp-ig",
      items: [
        ["igBlockReels", "Bloquear Reels"],
        ["igBlockFeed", "Bloquear Feed Principal"],
        ["igBlockComments", "Ocultar Comentários"],
      ],
    },
    {
      title: "TIKTOK",
      cls: "c-grp-tt",
      items: [["ttBlockFeed", "Bloquear Feed Recomendado"]],
    },
    {
      title: "REDDIT",
      cls: "c-grp-rd",
      items: [
        ["rdBlockFeed", "Bloquear Feed Principal"],
        ["rdBlockComments", "Ocultar Comentários"],
      ],
    },
    {
      title: "X (TWITTER)",
      cls: "c-grp-tw",
      items: [
        ["twBlockFeed", "Bloquear Timeline"],
        ["twBlockTrends", "Ocultar Assuntos do Momento"],
      ],
    },
    {
      title: "LINKEDIN",
      cls: "c-grp-li",
      items: [["liBlockFeed", "Bloquear Feed de Notícias"]],
    },
  ];

  const HUD_STYLES = [
    ":host{all:initial;position:fixed;bottom:18px;right:18px;z-index:2147483647;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;line-height:normal;color-scheme:dark;}",
    "*{box-sizing:border-box;}",
    ".is-hidden{display:none !important;}",
    // Pílula mínima (sem 6 pontinhos e sem texto "Filtros")
    ".c-pill{display:inline-flex;align-items:center;min-height:32px;line-height:1.2;background:rgba(18,20,23,0.94);color:#f8fafc;padding:4px 6px 4px 11px;border-radius:999px;font-family:inherit;font-size:12px;font-weight:700;border:1px solid rgba(100,255,218,0.38);box-shadow:0 6px 22px rgba(0,0,0,0.45);backdrop-filter:blur(8px);user-select:none;touch-action:none;cursor:grab;transition:border-color 0.15s ease,box-shadow 0.15s ease;}",
    ".c-pill:hover{border-color:rgba(100,255,218,0.85);}",
    ".c-pill.is-dragging,.c-eye.is-dragging{cursor:grabbing;border-color:#64ffda;box-shadow:0 10px 28px rgba(0,0,0,0.65);}",
    ".c-pill.is-dragging .c-pill-main{cursor:grabbing;}",
    ".c-pill-main{display:inline-flex;align-items:center;gap:7px;background:transparent;border:0;color:inherit;font:inherit;padding:2px 6px 2px 0;margin:0;cursor:inherit;}",
    ".c-dot{width:8px;height:8px;border-radius:50%;display:inline-block;flex-shrink:0;background:#64ffda;}",
    ".c-dot.is-neutral{background:#00b4d8;}",
    ".c-dot.is-ok{background:#64ffda;}",
    ".c-dot.is-warn{background:#ffb300;}",
    ".c-dot.is-danger{background:#ff5252;}",
    ".c-pill-hide{display:inline-flex;align-items:center;justify-content:center;background:transparent;border:0;border-left:1px solid rgba(255,255,255,0.14);color:#94a3b8;padding:2px 4px 2px 7px;margin:0;cursor:pointer;line-height:1;}",
    ".c-pill-hide:hover{color:#fff;}",
    // Bolinha com olho fechado arrastável (diâmetro igual à altura da pílula)
    ".c-eye{position:relative;display:inline-flex;align-items:center;justify-content:center;width:32px;height:32px;border-radius:50%;background:rgba(18,20,23,0.94);color:#64ffda;border:1px solid rgba(100,255,218,0.45);box-shadow:0 6px 18px rgba(0,0,0,0.5);backdrop-filter:blur(8px);cursor:grab;user-select:none;touch-action:none;padding:0;margin:0;transition:border-color 0.15s ease,transform 0.15s ease;}",
    ".c-eye:hover{border-color:#64ffda;transform:scale(1.05);}",
    ".c-eye-dot{position:absolute;top:4px;right:4px;width:7px;height:7px;border-radius:50%;border:1px solid #121417;background:#64ffda;}",
    ".c-eye-dot.is-neutral{background:#00b4d8;}",
    ".c-eye-dot.is-ok{background:#64ffda;}",
    ".c-eye-dot.is-warn{background:#ffb300;}",
    ".c-eye-dot.is-danger{background:#ff5252;}",
    // Painel miniatura do App Chronos (Material 3 Dark Theme do desktop)
    ".c-panel{display:none;flex-direction:column;position:fixed;bottom:62px;right:18px;width:348px;max-width:calc(100vw - 16px);max-height:78vh;background:#121417;color:#f1f5f9;border:1px solid #2d3748;border-radius:14px;box-shadow:0 18px 44px rgba(0,0,0,0.72);overflow:hidden;font-family:inherit;opacity:1;}",
    ".c-panel.is-open{display:flex;}",
    ".c-appbar{display:flex;align-items:center;justify-content:space-between;padding:10px 12px;background:#15181e;border-bottom:1px solid #232730;gap:8px;}",
    ".c-brand{display:flex;align-items:center;gap:7px;min-width:0;}",
    ".c-brand-icon{color:#64ffda;display:inline-flex;align-items:center;flex-shrink:0;}",
    ".c-title{font-weight:800;font-size:13px;color:#f8fafc;letter-spacing:0.2px;white-space:nowrap;}",
    ".c-title-sub{font-size:9px;font-weight:800;color:#64ffda;background:rgba(100,255,218,0.12);border:1px solid rgba(100,255,218,0.3);padding:1px 5px;border-radius:6px;letter-spacing:0.4px;}",
    ".c-head-right{display:flex;align-items:center;gap:5px;flex-shrink:0;}",
    ".c-badge{font-size:10px;padding:2px 7px;border-radius:999px;font-weight:700;white-space:nowrap;}",
    ".c-badge.is-ok{background:rgba(100,255,218,0.14);color:#64ffda;border:1px solid rgba(100,255,218,0.35);}",
    ".c-badge.is-warn{background:rgba(255,179,0,0.16);color:#ffb300;border:1px solid rgba(255,179,0,0.35);}",
    ".c-badge.is-err{background:rgba(255,82,82,0.18);color:#ff5252;border:1px solid rgba(255,82,82,0.4);}",
    ".c-icon-btn{display:inline-flex;align-items:center;justify-content:center;background:transparent;border:0;color:#94a3b8;font-size:16px;line-height:1;cursor:pointer;padding:4px;border-radius:6px;}",
    ".c-icon-btn:hover{color:#fff;background:rgba(255,255,255,0.06);}",
    ".c-view-wrap{padding:11px 12px;overflow-y:auto;display:flex;flex-direction:column;gap:10px;flex:1;min-height:0;}",
    // Hero Monitor Card (miniatura de _LiveMonitorCard)
    ".c-hero{background:#1c2027;border:1px solid #2d3748;border-radius:14px;padding:13px;display:flex;flex-direction:column;gap:10px;}",
    ".c-hero.is-blocked{background:rgba(127,29,29,0.34);border-color:rgba(255,82,82,0.55);}",
    ".c-hero-top{display:flex;align-items:center;justify-content:space-between;gap:8px;}",
    ".c-hero-id{display:flex;align-items:center;gap:8px;min-width:0;}",
    ".c-hero-shield{display:inline-flex;align-items:center;flex-shrink:0;color:#64ffda;}",
    ".c-hero.is-blocked .c-hero-shield{color:#ff5252;}",
    ".c-hero.is-warn .c-hero-shield{color:#ffb300;}",
    ".c-hero.is-free .c-hero-shield{color:#94a3b8;}",
    ".c-hero-name{font-weight:700;font-size:14px;color:#f8fafc;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}",
    ".c-tokens-pill{font-size:10px;font-weight:700;color:#d8b4fe;background:rgba(88,28,135,0.35);border:1px solid rgba(192,132,252,0.55);padding:2px 8px;border-radius:999px;white-space:nowrap;flex-shrink:0;}",
    ".c-hero-clock{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:31px;font-weight:900;letter-spacing:1.5px;text-align:center;color:#64ffda;margin:2px 0;}",
    ".c-hero.is-blocked .c-hero-clock{color:#ff5252;}",
    ".c-hero.is-warn .c-hero-clock{color:#ffb300;}",
    ".c-hero.is-free .c-hero-clock{font-size:15px;font-weight:700;letter-spacing:0;color:#cbd5e1;padding:6px 0;}",
    ".c-progress-track{width:100%;height:7px;background:rgba(255,255,255,0.12);border-radius:999px;overflow:hidden;}",
    ".c-progress-fill{height:100%;width:0%;background:#64ffda;border-radius:999px;transition:width 0.25s ease;}",
    ".c-hero.is-blocked .c-progress-fill{background:#ff5252;}",
    ".c-hero.is-warn .c-progress-fill{background:#ffb300;}",
    ".c-hero-meta{display:flex;justify-content:space-between;gap:8px;font-size:10.5px;color:#94a3b8;flex-wrap:wrap;}",
    ".c-activity{display:flex;align-items:center;justify-content:center;gap:6px;background:rgba(0,0,0,0.36);border-radius:10px;padding:6px 10px;font-size:11px;color:#cbd5e1;word-break:break-word;}",
    ".c-activity-dot{width:6px;height:6px;border-radius:50%;background:#64ffda;flex-shrink:0;}",
    ".c-hero.is-blocked .c-activity-dot{background:#ff5252;}",
    ".c-hero.is-free .c-activity-dot{background:#94a3b8;}",
    // Seções e cards padrão do App (#1B1E23)
    ".c-sec{font-size:10px;font-weight:700;color:#94a3b8;text-transform:uppercase;letter-spacing:0.6px;padding-left:2px;}",
    ".c-card{background:#1b1e23;border:1px solid #2d3748;border-radius:14px;padding:10px 12px;display:flex;flex-direction:column;gap:7px;}",
    ".c-sites{display:flex;flex-direction:column;gap:7px;}",
    ".c-site-row{display:flex;flex-direction:column;gap:6px;padding:9px 10px;background:#1b1e23;border:1px solid #2d3748;border-radius:12px;font-size:11.5px;}",
    ".c-site-top{display:flex;align-items:center;justify-content:space-between;gap:8px;}",
    ".c-site-info{min-width:0;display:flex;flex-direction:column;gap:2px;}",
    ".c-site-name{font-weight:600;color:#f8fafc;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}",
    ".c-site-pat{font-size:10px;color:#94a3b8;font-family:monospace;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}",
    ".c-site-badge{font-size:10px;font-weight:700;padding:2px 8px;border-radius:999px;white-space:nowrap;flex-shrink:0;}",
    ".c-site-badge.is-ok{background:rgba(100,255,218,0.14);color:#64ffda;}",
    ".c-site-badge.is-blocked{background:rgba(255,82,82,0.18);color:#ff5252;}",
    ".c-mini-track{width:100%;height:4px;background:rgba(255,255,255,0.09);border-radius:999px;overflow:hidden;}",
    ".c-mini-fill{height:100%;background:#64ffda;border-radius:999px;}",
    ".c-mini-fill.is-blocked{background:#ff5252;}",
    ".c-empty{font-size:11px;color:#94a3b8;text-align:center;padding:10px;}",
    // Aba Filtros & Aparência HUD (Slider de Alfa + Material 3 Switches)
    ".c-grp-title{font-size:10px;font-weight:800;margin-top:4px;letter-spacing:0.4px;}",
    ".c-grp-hud{color:#64ffda;}",
    ".c-grp-yt{color:#ff5252;}",
    ".c-grp-ig{color:#e1306c;}",
    ".c-grp-tt{color:#25f4ee;}",
    ".c-grp-rd{color:#ff4500;}",
    ".c-grp-tw{color:#1da1f2;}",
    ".c-grp-li{color:#0a66c2;}",
    ".c-grp-gl{color:#64ffda;}",
    ".c-grp-ln{color:#ffb300;}",
    ".c-ac-lock{font-size:10px;color:#ffb300;background:rgba(255,179,0,0.12);border:1px solid rgba(255,179,0,0.35);border-radius:6px;padding:3px 7px;margin-top:2px;}",
    ".c-chips{display:flex;flex-wrap:wrap;gap:4px;margin-top:4px;}",
    ".c-chip{display:inline-flex;align-items:center;gap:4px;background:rgba(255,255,255,0.07);border:1px solid #334155;border-radius:999px;padding:2px 7px;font-size:10.5px;color:#e2e8f0;}",
    ".c-chip-rm{background:transparent;border:0;color:#94a3b8;cursor:pointer;font-size:11px;padding:0;line-height:1;}",
    ".c-chip-rm:hover{color:#ff5252;}",
    ".c-term-row{display:flex;gap:5px;align-items:center;margin-top:4px;}",
    ".c-term-in{flex:1;min-width:0;background:#121417;border:1px solid #334155;border-radius:7px;color:#f1f5f9;padding:4px 7px;font-size:11px;font-family:inherit;}",
    ".c-term-btn{background:rgba(100,255,218,0.16);border:1px solid rgba(100,255,218,0.4);color:#64ffda;border-radius:7px;padding:4px 8px;font-size:10.5px;font-weight:700;cursor:pointer;white-space:nowrap;}",
    ".c-term-lbl{font-size:10.5px;font-weight:600;color:#cbd5e1;margin-top:3px;}",
    ".c-ac-menu{margin-top:4px;background:#111419;border:1px solid #334155;border-radius:8px;max-height:136px;overflow-y:auto;display:flex;flex-direction:column;}",
    ".c-ac-item{display:flex;align-items:center;justify-content:space-between;gap:6px;width:100%;background:transparent;border:0;border-bottom:1px solid rgba(255,255,255,0.05);color:#f1f5f9;padding:5px 7px;font-size:11px;text-align:left;cursor:pointer;font-family:inherit;}",
    ".c-ac-item:last-child{border-bottom:0;}",
    ".c-ac-item:hover{background:rgba(100,255,218,0.12);}",
    ".c-ac-left{display:flex;align-items:center;gap:6px;min-width:0;flex:1;}",
    ".c-ac-title{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-weight:600;}",
    ".c-ac-sub{font-size:9.5px;color:#94a3b8;white-space:nowrap;}",
    ".c-ac-thumb{width:34px;height:14px;object-fit:cover;border-radius:3px;flex-shrink:0;}",
    ".c-site-details{margin-top:5px;}",
    ".c-site-summary{cursor:pointer;font-size:10.5px;font-weight:700;color:#64ffda;user-select:none;}",
    ".c-site-sublist{display:flex;flex-wrap:wrap;gap:4px;margin-top:5px;}",
    ".c-site-chip{background:rgba(255,255,255,0.06);border:1px solid #2d3748;border-radius:6px;padding:2px 6px;font-size:10px;color:#cbd5e1;}",
    ".c-divider{height:1px;background:#232730;margin:2px 0;}",
    ".c-slider-block{display:flex;flex-direction:column;gap:5px;padding:2px 0;}",
    ".c-slider-head{display:flex;align-items:center;justify-content:space-between;font-size:11.5px;color:#e2e8f0;font-weight:600;}",
    ".c-slider-val{font-size:11px;font-weight:700;color:#64ffda;font-family:monospace;}",
    ".c-range{width:100%;accent-color:#00bfa5;cursor:pointer;margin:0;}",
    ".c-filter-row{display:flex;align-items:center;justify-content:space-between;gap:10px;font-size:11.5px;color:#e2e8f0;cursor:pointer;padding:2px 0;}",
    ".c-switch{appearance:none;-webkit-appearance:none;position:relative;width:34px;height:19px;border-radius:999px;background:#2d3748;border:1px solid #475569;cursor:pointer;flex-shrink:0;margin:0;transition:background 0.16s ease,border-color 0.16s ease;}",
    ".c-switch::after{content:'';position:absolute;top:2px;left:2px;width:13px;height:13px;border-radius:50%;background:#cbd5e1;transition:transform 0.16s ease,background 0.16s ease;}",
    ".c-switch:checked{background:rgba(0,191,165,0.35);border-color:#64ffda;}",
    ".c-switch:checked::after{transform:translateX(15px);background:#64ffda;}",
    // Barra de navegação inferior estilo App NavigationBar
    ".c-navbar{display:grid;grid-template-columns:1fr 1fr;background:#15181e;border-top:1px solid #232730;padding:6px 8px;gap:6px;}",
    ".c-nav-btn{display:flex;align-items:center;justify-content:center;gap:6px;background:transparent;border:0;color:#94a3b8;font-family:inherit;font-size:11.5px;font-weight:700;padding:7px 10px;border-radius:10px;cursor:pointer;transition:background 0.15s ease,color 0.15s ease;}",
    ".c-nav-btn:hover{color:#e2e8f0;background:rgba(255,255,255,0.04);}",
    ".c-nav-btn.is-active{background:rgba(100,255,218,0.14);color:#64ffda;}",
    // Toast não bloqueante
    ".c-toast{position:fixed;bottom:18px;right:18px;background:rgba(18,20,23,0.94);color:#e2e8f0;border:1px solid rgba(100,255,218,0.35);border-radius:10px;padding:8px 12px;font-size:11.5px;box-shadow:0 8px 24px rgba(0,0,0,0.5);pointer-events:none;z-index:2147483647;}",
  ].join("");

  function formatTime(sec) {
    const s = Math.max(0, Math.floor(sec || 0));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const remS = s % 60;
    if (h > 0) {
      return h + ":" + String(m).padStart(2, "0") + ":" + String(remS).padStart(2, "0");
    }
    return String(m).padStart(2, "0") + ":" + String(remS).padStart(2, "0");
  }

  function formatHms(sec) {
    const s = Math.max(0, Math.floor(sec || 0));
    const h = String(Math.floor(s / 3600)).padStart(2, "0");
    const m = String(Math.floor((s % 3600) / 60)).padStart(2, "0");
    const remS = String(s % 60).padStart(2, "0");
    return h + ":" + m + ":" + remS;
  }

  function clampAlpha(v) {
    const n = Number(v);
    if (!Number.isFinite(n)) return 0.94;
    return Math.min(1.0, Math.max(0.15, n));
  }

  function clampScale(v) {
    const n = Number(v);
    if (!Number.isFinite(n)) return 1.0;
    return Math.min(1.6, Math.max(0.7, n));
  }

  function normalize(raw) {
    if (globalScope.ChronosFocusCore && typeof globalScope.ChronosFocusCore.normalizeFilters === "function") {
      return globalScope.ChronosFocusCore.normalizeFilters(raw);
    }
    const base = Object.assign({}, raw || {});
    base.hudAlpha = clampAlpha(base.hudAlpha !== undefined ? base.hudAlpha : base.hud_alpha);
    base.hudScale = clampScale(base.hudScale !== undefined ? base.hudScale : base.hud_scale);
    const eye = base.hudHideToEye !== undefined ? base.hudHideToEye : base.hud_hide_to_eye;
    base.hudHideToEye = eye === undefined ? true : !!eye;
    const lnEn = base.launcherFilterEnabled !== undefined ? base.launcherFilterEnabled : base.launcher_filter_enabled;
    base.launcherFilterEnabled = lnEn === undefined ? true : !!lnEn;
    base.launcherBlockedTags = Array.isArray(base.launcherBlockedTags)
      ? base.launcherBlockedTags
      : Array.isArray(base.launcher_blocked_tags)
        ? base.launcher_blocked_tags
        : [];
    base.launcherBlockedNames = Array.isArray(base.launcherBlockedNames)
      ? base.launcherBlockedNames
      : Array.isArray(base.launcher_blocked_names)
        ? base.launcher_blocked_names
        : [];
    return base;
  }

  function sanitizePosition(raw) {
    if (!raw || typeof raw !== "object") return null;
    const anchorX = raw.anchorX === "left" ? "left" : raw.anchorX === "right" ? "right" : null;
    const anchorY = raw.anchorY === "top" ? "top" : raw.anchorY === "bottom" ? "bottom" : null;
    const offsetX = Number(raw.offsetX);
    const offsetY = Number(raw.offsetY);
    if (!anchorX || !anchorY || !Number.isFinite(offsetX) || !Number.isFinite(offsetY)) {
      return null;
    }
    return {
      anchorX,
      anchorY,
      offsetX: Math.max(8, Math.round(offsetX)),
      offsetY: Math.max(8, Math.round(offsetY)),
    };
  }

  function readSessionMode() {
    try {
      if (typeof sessionStorage !== "undefined" && sessionStorage) {
        const mode = sessionStorage.getItem(MODE_SESSION_KEY);
        if (mode === "eye" || mode === "hidden" || mode === "pill") return mode;
        if (sessionStorage.getItem(LEGACY_HIDDEN_KEY) === "1") return "hidden";
      }
    } catch (_) {}
    return "pill";
  }

  function writeSessionMode(mode) {
    try {
      if (typeof sessionStorage !== "undefined" && sessionStorage) {
        if (mode === "pill") {
          sessionStorage.removeItem(MODE_SESSION_KEY);
          sessionStorage.removeItem(LEGACY_HIDDEN_KEY);
        } else {
          sessionStorage.setItem(MODE_SESSION_KEY, mode);
        }
      }
    } catch (_) {}
  }

  function readLocalPosition() {
    try {
      if (typeof localStorage !== "undefined" && localStorage) {
        const raw = localStorage.getItem(POS_STORAGE_KEY);
        return raw ? sanitizePosition(JSON.parse(raw)) : null;
      }
    } catch (_) {}
    return null;
  }

  function writeLocalPosition(pos) {
    try {
      if (typeof localStorage !== "undefined" && localStorage) {
        if (pos) {
          localStorage.setItem(POS_STORAGE_KEY, JSON.stringify(pos));
        } else {
          localStorage.removeItem(POS_STORAGE_KEY);
        }
      }
    } catch (_) {}
  }

  function createSvgIcon(size, fallbackText, builder) {
    if (typeof document !== "undefined" && typeof document.createElementNS === "function") {
      try {
        const ns = "http://www.w3.org/2000/svg";
        const svg = document.createElementNS(ns, "svg");
        svg.setAttribute("viewBox", "0 0 24 24");
        svg.setAttribute("width", String(size));
        svg.setAttribute("height", String(size));
        svg.setAttribute("fill", "none");
        svg.setAttribute("stroke", "currentColor");
        svg.setAttribute("stroke-width", "2");
        svg.setAttribute("stroke-linecap", "round");
        svg.setAttribute("stroke-linejoin", "round");
        svg.setAttribute("aria-hidden", "true");
        const add = (tag, attrs) => {
          const el = document.createElementNS(ns, tag);
          Object.keys(attrs).forEach((k) => el.setAttribute(k, String(attrs[k])));
          svg.appendChild(el);
          return el;
        };
        builder(add);
        return svg;
      } catch (_) {}
    }
    const span = document.createElement("span");
    span.textContent = fallbackText;
    return span;
  }

  function createEyeOffIcon(size) {
    return createSvgIcon(size || 13, "\u2014", (add) => {
      add("path", { d: "M17.94 17.94A10.94 10.94 0 0 1 12 20c-7 0-11-8-11-8a21.77 21.77 0 0 1 5.06-5.94" });
      add("path", { d: "M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a21.8 21.8 0 0 1-2.16 3.19" });
      add("line", { x1: 1, y1: 1, x2: 23, y2: 23 });
    });
  }

  function createShieldIcon(size) {
    return createSvgIcon(size || 16, "\u23F1", (add) => {
      add("path", { d: "M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" });
    });
  }

  function createClockIcon(size) {
    return createSvgIcon(size || 14, "\u23F1", (add) => {
      add("circle", { cx: 12, cy: 12, r: 9 });
      add("polyline", { points: "12 7 12 12 15.5 14" });
    });
  }

  function createSlidersIcon(size) {
    return createSvgIcon(size || 14, "\u2699", (add) => {
      add("line", { x1: 4, y1: 21, x2: 4, y2: 14 });
      add("line", { x1: 4, y1: 10, x2: 4, y2: 3 });
      add("line", { x1: 12, y1: 21, x2: 12, y2: 12 });
      add("line", { x1: 12, y1: 8, x2: 12, y2: 3 });
      add("line", { x1: 20, y1: 21, x2: 20, y2: 16 });
      add("line", { x1: 20, y1: 12, x2: 20, y2: 3 });
      add("line", { x1: 1, y1: 14, x2: 7, y2: 14 });
      add("line", { x1: 9, y1: 8, x2: 15, y2: 8 });
      add("line", { x1: 17, y1: 16, x2: 23, y2: 16 });
    });
  }

  function attachShadowStyles(shadowRoot, nonce) {
    if (nonce) {
      const stEl = document.createElement("style");
      stEl.setAttribute("nonce", nonce);
      stEl.textContent = HUD_STYLES;
      shadowRoot.appendChild(stEl);
      return;
    }

    try {
      if (typeof CSSStyleSheet !== "undefined" && "adoptedStyleSheets" in shadowRoot) {
        const sheet = new CSSStyleSheet();
        if (typeof sheet.replaceSync === "function") {
          sheet.replaceSync(HUD_STYLES);
          shadowRoot.adoptedStyleSheets = [sheet];
          return;
        }
      }
    } catch (_) {}

    const fallbackEl = document.createElement("style");
    fallbackEl.textContent = HUD_STYLES;
    shadowRoot.appendChild(fallbackEl);
  }

  function create(opts) {
    const cfg = opts || {};
    const source = cfg.source === "proxy" ? "proxy" : "extension";
    const defaultConnectedText = cfg.idleBadgeText || (source === "proxy" ? "Proxy Ativo" : "Protegido");

    let currentFilters = normalize(
      typeof cfg.getInitialFilters === "function" ? cfg.getInitialFilters() : cfg.initialFilters
    );
    let isConnected = source === "proxy";
    let antiCheatActive =
      typeof cfg.getAntiCheatActive === "function"
        ? !!cfg.getAntiCheatActive()
        : !!cfg.antiCheatActive;
    let lastMatchedRule = null;
    let lastSites = [];
    let panelOpen = false;
    let activeTab = "tempo";
    let savingFilters = false;
    let saveSeq = 0;
    let suppressPollUntil = 0;
    let lastMeasuredPillHeight = 32;
    let lastMeasuredPillScale = 1.0;

    let viewMode = readSessionMode();
    let currentPos = readLocalPosition();
    let dragState = null;
    let suppressClickUntil = 0;
    let toastTimer = null;

    let hudHost = null;
    let hudShadow = null;
    let pillWrapEl = null;
    let pillMainBtn = null;
    let pillDot = null;
    let pillLabel = null;
    let pillHideBtn = null;
    let eyeBtnEl = null;
    let eyeDotEl = null;
    let panelEl = null;
    let panelConnBadge = null;
    let viewTempoEl = null;
    let viewFiltersEl = null;
    let navTempoBtn = null;
    let navFiltersBtn = null;
    let heroCardEl = null;
    let heroTitleEl = null;
    let heroTokensEl = null;
    let heroClockEl = null;
    let heroProgressFillEl = null;
    let heroConsumedEl = null;
    let heroQuotaEl = null;
    let heroActivityEl = null;
    let sitesContainerEl = null;
    let alphaSliderEl = null;
    let alphaValueEl = null;
    let scaleSliderEl = null;
    let scaleValueEl = null;
    let hideToEyeChkEl = null;
    let launcherEnabledChkEl = null;
    let launcherLockNoteEl = null;
    let launcherTagsWrapEl = null;
    let launcherNamesWrapEl = null;
    let tagDisplayMap =
      typeof cfg.getTagDisplayMap === "function" && cfg.getTagDisplayMap()
        ? Object.assign({}, cfg.getTagDisplayMap())
        : {};
    let primaryLanguage =
      typeof cfg.getPrimaryLanguage === "function" && cfg.getPrimaryLanguage()
        ? cfg.getPrimaryLanguage()
        : "pt-BR";
    let toastEl = null;
    let listenersBound = false;
    let dragListenersBound = false;
    const filterCheckboxes = {};

    if (typeof cfg.loadPosition === "function") {
      try {
        cfg.loadPosition((loaded) => {
          const parsed = sanitizePosition(loaded);
          if (parsed && !dragState) {
            currentPos = parsed;
            applyHostPosition();
            if (panelOpen) positionPanel();
          }
        });
      } catch (_) {}
    }

    function resolvedHost() {
      if (typeof cfg.getHost === "function") {
        return cfg.getHost() || "";
      }
      return (typeof window !== "undefined" && window.location && window.location.hostname
        ? window.location.hostname
        : ""
      ).toLowerCase();
    }

    function viewportSize() {
      const vw = typeof window !== "undefined" && Number(window.innerWidth) > 0 ? Number(window.innerWidth) : 1024;
      const vh = typeof window !== "undefined" && Number(window.innerHeight) > 0 ? Number(window.innerHeight) : 768;
      return { vw, vh };
    }

    function activeHandleEl() {
      if (viewMode === "eye" && eyeBtnEl) return eyeBtnEl;
      if (viewMode === "pill" && pillWrapEl) return pillWrapEl;
      return hudHost;
    }

    function handleRect() {
      const target = activeHandleEl();
      if (target && typeof target.getBoundingClientRect === "function") {
        const r = target.getBoundingClientRect();
        if (r && (r.width > 0 || r.height > 0)) {
          return r;
        }
      }
      const { vw, vh } = viewportSize();
      const d = lastMeasuredPillHeight || Math.round(32 * clampScale(currentFilters.hudScale));
      const w = viewMode === "eye" ? d : Math.round(140 * clampScale(currentFilters.hudScale));
      const h = d;
      return { left: vw - 18 - w, right: vw - 18, top: vh - 18 - h, bottom: vh - 18, width: w, height: h };
    }

    function applyAlphaStyles() {
      const alphaStr = String(clampAlpha(currentFilters.hudAlpha));
      if (pillWrapEl && pillWrapEl.style) {
        pillWrapEl.style.opacity = alphaStr;
      }
      if (eyeBtnEl && eyeBtnEl.style) {
        eyeBtnEl.style.opacity = alphaStr;
      }
    }

    function syncEyeDiameter() {
      const scale = clampScale(currentFilters.hudScale);
      let diameter =
        lastMeasuredPillHeight > 0 && lastMeasuredPillScale > 0
          ? Math.max(20, Math.round(lastMeasuredPillHeight * (scale / lastMeasuredPillScale)))
          : Math.round(32 * scale);
      if (pillWrapEl && viewMode === "pill" && typeof pillWrapEl.getBoundingClientRect === "function") {
        const rect = pillWrapEl.getBoundingClientRect();
        if (rect && rect.height > 0) {
          diameter = Math.round(rect.height);
          lastMeasuredPillHeight = diameter;
          lastMeasuredPillScale = scale;
        }
      }

      if (eyeBtnEl && eyeBtnEl.style) {
        eyeBtnEl.style.width = diameter + "px";
        eyeBtnEl.style.height = diameter + "px";
        eyeBtnEl.style.borderRadius = "50%";
        const iconEl = eyeBtnEl.firstElementChild;
        if (iconEl && typeof iconEl.setAttribute === "function") {
          const iconPx = String(Math.max(12, Math.round(diameter * 0.52)));
          iconEl.setAttribute("width", iconPx);
          iconEl.setAttribute("height", iconPx);
        }
      }
      if (eyeDotEl && eyeDotEl.style) {
        const dotPx = Math.max(5, Math.round(diameter * 0.2)) + "px";
        const insetPx = Math.max(2, Math.round(diameter * 0.1)) + "px";
        eyeDotEl.style.width = dotPx;
        eyeDotEl.style.height = dotPx;
        eyeDotEl.style.top = insetPx;
        eyeDotEl.style.right = insetPx;
      }
    }

    function applySizeStyles() {
      const s = clampScale(currentFilters.hudScale);
      const targetMinH = Math.round(32 * s);
      if (pillWrapEl && pillWrapEl.style) {
        pillWrapEl.style.fontSize = (12 * s).toFixed(1) + "px";
        pillWrapEl.style.minHeight = targetMinH + "px";
        pillWrapEl.style.padding =
          Math.round(4 * s) + "px " + Math.round(6 * s) + "px " + Math.round(4 * s) + "px " + Math.round(11 * s) + "px";
      }
      if (pillDot && pillDot.style) {
        const dSz = Math.round(8 * s) + "px";
        pillDot.style.width = dSz;
        pillDot.style.height = dSz;
      }
      if (pillHideBtn && pillHideBtn.firstElementChild && typeof pillHideBtn.firstElementChild.setAttribute === "function") {
        const iSz = String(Math.max(10, Math.round(13 * s)));
        pillHideBtn.firstElementChild.setAttribute("width", iSz);
        pillHideBtn.firstElementChild.setAttribute("height", iSz);
      }
      syncEyeDiameter();
    }

    function applyHostPosition() {
      if (!hudHost || !hudHost.style) return;
      if (!currentPos) {
        hudHost.style.left = "auto";
        hudHost.style.top = "auto";
        hudHost.style.right = "18px";
        hudHost.style.bottom = "18px";
        return;
      }

      const { vw, vh } = viewportSize();
      const rect = handleRect();
      const maxX = Math.max(8, vw - (rect.width || 36) - 8);
      const maxY = Math.max(8, vh - (rect.height || 36) - 8);
      const cx = Math.min(Math.max(8, currentPos.offsetX), maxX);
      const cy = Math.min(Math.max(8, currentPos.offsetY), maxY);

      if (currentPos.anchorX === "left") {
        hudHost.style.left = cx + "px";
        hudHost.style.right = "auto";
      } else {
        hudHost.style.right = cx + "px";
        hudHost.style.left = "auto";
      }

      if (currentPos.anchorY === "top") {
        hudHost.style.top = cy + "px";
        hudHost.style.bottom = "auto";
      } else {
        hudHost.style.bottom = cy + "px";
        hudHost.style.top = "auto";
      }
    }

    function positionPanel() {
      if (!panelEl || !panelEl.style) return;
      if (!currentPos && !dragState) {
        panelEl.style.left = "auto";
        panelEl.style.top = "auto";
        panelEl.style.right = "18px";
        panelEl.style.bottom = "62px";
        panelEl.style.width = "";
        panelEl.style.maxHeight = "";
        return;
      }

      const { vw, vh } = viewportSize();
      const r = handleRect();
      const panelW = Math.min(348, Math.max(230, vw - 16));
      let pLeft = r.left + (r.width || 0) / 2 > vw / 2 ? r.right - panelW : r.left;
      pLeft = Math.max(8, Math.min(pLeft, vw - panelW - 8));

      panelEl.style.left = Math.round(pLeft) + "px";
      panelEl.style.right = "auto";
      panelEl.style.width = Math.round(panelW) + "px";

      const spaceAbove = r.top - 16;
      const spaceBelow = vh - r.bottom - 16;
      if (spaceAbove >= 280 || spaceAbove >= spaceBelow) {
        panelEl.style.bottom = Math.round(Math.max(8, vh - r.top + 8)) + "px";
        panelEl.style.top = "auto";
        panelEl.style.maxHeight = Math.round(Math.max(180, Math.min(vh * 0.78, spaceAbove))) + "px";
      } else {
        panelEl.style.top = Math.round(Math.max(8, r.bottom + 8)) + "px";
        panelEl.style.bottom = "auto";
        panelEl.style.maxHeight = Math.round(Math.max(180, Math.min(vh * 0.78, spaceBelow))) + "px";
      }
    }

    function persistPosition(pos) {
      writeLocalPosition(pos);
      if (typeof cfg.savePosition === "function") {
        try {
          cfg.savePosition(pos);
        } catch (_) {}
      }
    }

    function showToast(text) {
      if (!toastEl) return;
      if (toastTimer) {
        clearTimeout(toastTimer);
        toastTimer = null;
      }
      toastEl.textContent = text;
      toastEl.classList.remove("is-hidden");
      toastTimer = setTimeout(() => {
        toastTimer = null;
        if (toastEl) toastEl.classList.add("is-hidden");
      }, 3200);
    }

    function hideToast() {
      if (toastTimer) {
        clearTimeout(toastTimer);
        toastTimer = null;
      }
      if (toastEl) toastEl.classList.add("is-hidden");
    }

    function syncVisibilityDom() {
      if (pillWrapEl) {
        pillWrapEl.classList.toggle("is-hidden", viewMode !== "pill");
      }
      if (eyeBtnEl) {
        eyeBtnEl.classList.toggle("is-hidden", viewMode !== "eye");
      }
    }

    function setViewMode(nextMode, options) {
      const next = nextMode === "eye" || nextMode === "hidden" ? nextMode : "pill";
      if (next === "eye") {
        syncEyeDiameter();
      }
      viewMode = next;
      writeSessionMode(viewMode);
      if (viewMode !== "pill") {
        panelOpen = false;
        if (panelEl) panelEl.classList.remove("is-open");
      }
      syncVisibilityDom();
      applySizeStyles();
      applyAlphaStyles();
      applyHostPosition();
      if (viewMode === "hidden" && options && options.showToast) {
        showToast("P\u00edlula ocultada \u2022 Pressione Alt+Shift+C para reexibir");
      } else if (viewMode !== "hidden") {
        hideToast();
      }
      return viewMode;
    }

    function setHidden(hidden, options) {
      if (!hidden) {
        setViewMode("pill");
        return false;
      }
      const forceFull = options && options.forceFullHide;
      const nextMode = !forceFull && currentFilters.hudHideToEye !== false ? "eye" : "hidden";
      setViewMode(nextMode, { showToast: nextMode === "hidden" && (!options || options.showToast !== false) });
      return true;
    }

    function resetPosition() {
      currentPos = null;
      applyHostPosition();
      persistPosition(null);
      if (panelOpen) positionPanel();
    }

    function setPosition(pos) {
      currentPos = sanitizePosition(pos);
      if (!dragState) {
        applyHostPosition();
        if (panelOpen) positionPanel();
      }
    }

    function setActiveTab(tab) {
      activeTab = tab === "filtros" ? "filtros" : "tempo";
      if (viewTempoEl) viewTempoEl.classList.toggle("is-hidden", activeTab !== "tempo");
      if (viewFiltersEl) viewFiltersEl.classList.toggle("is-hidden", activeTab !== "filtros");
      if (navTempoBtn) navTempoBtn.classList.toggle("is-active", activeTab === "tempo");
      if (navFiltersBtn) navFiltersBtn.classList.toggle("is-active", activeTab === "filtros");
    }

    function applyBadge(text, stateClass) {
      if (!panelConnBadge) return;
      panelConnBadge.textContent = text;
      panelConnBadge.className = "c-badge " + (stateClass || "is-ok");
    }

    function applyIdleBadge() {
      if (source === "proxy") {
        applyBadge(defaultConnectedText, "is-ok");
      } else if (isConnected) {
        applyBadge(defaultConnectedText, "is-ok");
      } else {
        applyBadge("Offline", "is-err");
      }
    }

    function renderTermChips(containerEl, list, isTag) {
      if (!containerEl) return;
      containerEl.textContent = "";
      (Array.isArray(list) ? list : []).forEach((term) => {
        const chip = document.createElement("span");
        chip.className = "c-chip";
        const txt = document.createElement("span");
        const disp = isTag && tagDisplayMap && tagDisplayMap[term] ? tagDisplayMap[term] : term;
        txt.textContent =
          isTag && disp.toLowerCase() !== term.toLowerCase()
            ? disp + " (" + term + ")"
            : disp;
        if (isTag && disp.toLowerCase() !== term.toLowerCase()) {
          chip.title = "Tag Steam API: " + term;
        }
        const rmBtn = document.createElement("button");
        rmBtn.type = "button";
        rmBtn.className = "c-chip-rm";
        rmBtn.textContent = antiCheatActive ? "\uD83D\uDD12" : "\u00D7";
        rmBtn.title = antiCheatActive
          ? "Desative o Anti-Cheat para remover"
          : "Remover " + disp;
        rmBtn.addEventListener("click", (ev) => {
          ev.stopPropagation();
          if (antiCheatActive) {
            showToast("Anti-Cheat ativo: desative para remover tags ou nomes.");
            return;
          }
          const key = isTag ? "launcherBlockedTags" : "launcherBlockedNames";
          const nextList = (currentFilters[key] || []).filter((t) => t !== term);
          saveFilters(Object.assign({}, currentFilters, { [key]: nextList }));
        });
        chip.appendChild(txt);
        chip.appendChild(rmBtn);
        containerEl.appendChild(chip);
      });
    }

    function syncFilterControls(f) {
      if (!f) return;
      Object.keys(filterCheckboxes).forEach((k) => {
        const el = filterCheckboxes[k];
        if (!el) return;
        if (k === "globalGrayscale") {
          el.checked = !!(f.globalGrayscale || f.grayscaleMode);
        } else if (k === "globalBlockNotifications") {
          el.checked = !!(f.globalBlockNotifications || f.blockNotifications);
        } else {
          el.checked = !!f[k];
        }
      });
      const pct = Math.round(clampAlpha(f.hudAlpha) * 100);
      if (alphaSliderEl) alphaSliderEl.value = String(pct);
      if (alphaValueEl) alphaValueEl.textContent = pct + "%";
      const scalePct = Math.round(clampScale(f.hudScale) * 100);
      if (scaleSliderEl) scaleSliderEl.value = String(scalePct);
      if (scaleValueEl) scaleValueEl.textContent = scalePct + "%";
      if (hideToEyeChkEl) hideToEyeChkEl.checked = f.hudHideToEye !== false;
      if (launcherEnabledChkEl) launcherEnabledChkEl.checked = f.launcherFilterEnabled !== false;
      if (launcherLockNoteEl) launcherLockNoteEl.classList.toggle("is-hidden", !antiCheatActive);
      renderTermChips(launcherTagsWrapEl, f.launcherBlockedTags, true);
      renderTermChips(launcherNamesWrapEl, f.launcherBlockedNames, false);
      applySizeStyles();
      applyAlphaStyles();
    }

    function resolveActiveRule() {
      if (!lastMatchedRule) return null;
      if (Array.isArray(lastSites) && lastSites.length) {
        const found = lastSites.find(
          (s) =>
            (lastMatchedRule.entityId && s.entityId === lastMatchedRule.entityId) ||
            (lastMatchedRule.displayName && s.displayName === lastMatchedRule.displayName)
        );
        if (found) {
          return Object.assign({}, found, lastMatchedRule, {
            consumedSeconds:
              lastMatchedRule.consumedSeconds !== undefined ? lastMatchedRule.consumedSeconds : found.consumedSeconds,
            dailyQuotaSeconds:
              lastMatchedRule.dailyQuotaSeconds !== undefined
                ? lastMatchedRule.dailyQuotaSeconds
                : found.dailyQuotaSeconds,
            emergencyTokensRemaining:
              lastMatchedRule.emergencyTokensRemaining !== undefined
                ? lastMatchedRule.emergencyTokensRemaining
                : found.emergencyTokensRemaining,
          });
        }
      }
      return lastMatchedRule;
    }

    function renderHeroMonitor() {
      if (!heroCardEl) return;
      const host = resolvedHost();
      const rule = resolveActiveRule();

      if (!rule || rule.remainingSeconds === undefined) {
        heroCardEl.className = "c-hero is-free";
        if (heroTitleEl) heroTitleEl.textContent = "Navega\u00e7\u00e3o Livre";
        if (heroTokensEl) heroTokensEl.classList.add("is-hidden");
        if (heroClockEl) heroClockEl.textContent = "Sem limite ativo neste site";
        if (heroProgressFillEl && heroProgressFillEl.style) heroProgressFillEl.style.width = "0%";
        if (heroConsumedEl) heroConsumedEl.textContent = "Dom\u00ednio sem cota di\u00e1ria";
        if (heroQuotaEl) heroQuotaEl.textContent = host || "navegador";
        if (heroActivityEl) heroActivityEl.textContent = "Filtros de foco ativos em " + (host || "navegador");
        return;
      }

      const rem = Math.max(0, Math.floor(rule.remainingSeconds || 0));
      const totalQuota = Math.max(0, Math.floor(rule.dailyQuotaSeconds || 0));
      const consumed =
        rule.consumedSeconds !== undefined
          ? Math.max(0, Math.floor(rule.consumedSeconds || 0))
          : Math.max(0, totalQuota - rem);
      const isBlocked = !!rule.isBlocked || rem <= 0;
      const isWarn = !isBlocked && rem <= 300;
      const pct = totalQuota > 0 ? Math.min(100, Math.max(0, (consumed / totalQuota) * 100)) : isBlocked ? 100 : 0;

      heroCardEl.className = "c-hero " + (isBlocked ? "is-blocked" : isWarn ? "is-warn" : "");
      if (heroTitleEl) heroTitleEl.textContent = rule.displayName || host || "Sess\u00e3o Ativa";
      if (heroTokensEl) {
        if (rule.emergencyTokensRemaining !== undefined) {
          heroTokensEl.textContent = "Tokens: " + rule.emergencyTokensRemaining + "/2";
          heroTokensEl.classList.remove("is-hidden");
        } else {
          heroTokensEl.classList.add("is-hidden");
        }
      }
      if (heroClockEl) heroClockEl.textContent = isBlocked ? "BLOQUEADO" : formatHms(rem);
      if (heroProgressFillEl && heroProgressFillEl.style) {
        heroProgressFillEl.style.width = pct.toFixed(1) + "%";
      }
      if (heroConsumedEl) heroConsumedEl.textContent = "Consumido: " + formatHms(consumed);
      if (heroQuotaEl) {
        heroQuotaEl.textContent =
          totalQuota > 0 ? "Limite: " + formatHms(totalQuota) + " (" + pct.toFixed(0) + "%)" : "";
      }
      if (heroActivityEl) {
        heroActivityEl.textContent = (isBlocked ? "Bloqueado em " : "Monitorando ") + (host || "aba atual");
      }
    }

    function parseGroupPatternData(site) {
      const result = { isGroup: false, sites: [], apps: [] };
      if (!site) return result;
      if (Array.isArray(site.groupSites) || Array.isArray(site.groupApps)) {
        result.sites = Array.isArray(site.groupSites) ? site.groupSites.filter(Boolean) : [];
        result.apps = Array.isArray(site.groupApps) ? site.groupApps : [];
        result.isGroup =
          result.sites.length > 0 ||
          result.apps.length > 0 ||
          String(site.pattern || "").trim().startsWith("{");
        if (result.isGroup) return result;
      }
      const raw = String(site.pattern || "").trim();
      if (raw.startsWith("{")) {
        try {
          const p = JSON.parse(raw);
          if (p && typeof p === "object") {
            result.isGroup = true;
            if (Array.isArray(p.sites)) {
              p.sites.forEach((s) => {
                const v = typeof s === "string" ? s.trim() : s && (s.domain || s.url || s.name);
                if (v) result.sites.push(String(v).trim());
              });
            }
            if (Array.isArray(p.apps)) {
              p.apps.forEach((a) => {
                if (typeof a === "string" && a.trim()) {
                  result.apps.push({ name: a.trim(), exec: a.trim() });
                } else if (a && typeof a === "object" && (a.name || a.exec)) {
                  result.apps.push({ name: a.name || a.exec, exec: a.exec || a.name });
                }
              });
            }
            return result;
          }
        } catch (_) {}
      }
      if (raw.includes(",")) {
        const parts = raw
          .split(",")
          .map((x) => x.trim())
          .filter(Boolean);
        if (parts.length > 1) {
          result.isGroup = true;
          result.sites = parts;
        }
      }
      return result;
    }

    function renderSitesList(sites) {
      if (!sitesContainerEl) return;
      sitesContainerEl.textContent = "";
      if (!Array.isArray(sites) || !sites.length) {
        const empty = document.createElement("div");
        empty.className = "c-empty";
        empty.textContent = "Nenhum site ou sess\u00e3o monitorada configurada.";
        sitesContainerEl.appendChild(empty);
        return;
      }
      sites.forEach((s) => {
        const row = document.createElement("div");
        row.className = "c-site-row";

        const top = document.createElement("div");
        top.className = "c-site-top";

        const left = document.createElement("div");
        left.className = "c-site-info";
        const name = document.createElement("div");
        name.className = "c-site-name";
        name.textContent = s.displayName || s.entityId || "";
        const grp = parseGroupPatternData(s);
        const pat = document.createElement("div");
        pat.className = "c-site-pat";
        pat.textContent = grp.isGroup
          ? grp.sites.length + " site(s) \u2022 " + grp.apps.length + " app(s)"
          : s.pattern || s.entityId || "";
        left.appendChild(name);
        left.appendChild(pat);

        const isBlocked = !!s.isBlocked || (s.remainingSeconds !== undefined && s.remainingSeconds <= 0);
        const badge = document.createElement("span");
        badge.className = "c-site-badge " + (isBlocked ? "is-blocked" : "is-ok");
        badge.textContent = isBlocked ? "BLOQUEADO" : formatTime(s.remainingSeconds);

        top.appendChild(left);
        top.appendChild(badge);
        row.appendChild(top);

        const total = Math.max(0, Math.floor(s.dailyQuotaSeconds || 0));
        const used =
          s.consumedSeconds !== undefined
            ? Math.max(0, Math.floor(s.consumedSeconds || 0))
            : Math.max(0, total - Math.max(0, Math.floor(s.remainingSeconds || 0)));
        if (total > 0) {
          const pct = Math.min(100, Math.max(0, (used / total) * 100));
          const track = document.createElement("div");
          track.className = "c-mini-track";
          const fill = document.createElement("div");
          fill.className = "c-mini-fill" + (isBlocked ? " is-blocked" : "");
          if (fill.style) fill.style.width = pct.toFixed(1) + "%";
          track.appendChild(fill);
          row.appendChild(track);
        }

        if (grp.isGroup && (grp.sites.length || grp.apps.length)) {
          const details = document.createElement("details");
          details.className = "c-site-details";
          const summary = document.createElement("summary");
          summary.className = "c-site-summary";
          summary.textContent = "Ver itens do grupo (" + (grp.sites.length + grp.apps.length) + ")";
          details.appendChild(summary);
          const sub = document.createElement("div");
          sub.className = "c-site-sublist";
          grp.sites.forEach((siteDomain) => {
            const chip = document.createElement("span");
            chip.className = "c-site-chip";
            chip.textContent = "\uD83C\uDF10 " + siteDomain;
            sub.appendChild(chip);
          });
          grp.apps.forEach((appObj) => {
            const chip = document.createElement("span");
            chip.className = "c-site-chip";
            chip.textContent = "\uD83D\uDCBB " + (appObj.name || appObj.exec);
            sub.appendChild(chip);
          });
          details.appendChild(sub);
          row.appendChild(details);
        }

        sitesContainerEl.appendChild(row);
      });
    }

    function requestStatus() {
      if (typeof cfg.onRequestStatus !== "function") return;
      try {
        cfg.onRequestStatus((res) => {
          if (!res) return;
          if (typeof res.isConnected === "boolean") {
            isConnected = res.isConnected;
          }
          const nextAc = !!res.antiCheatActive;
          const acChanged = nextAc !== antiCheatActive;
          antiCheatActive = nextAc;
          if (res.tagDisplayMap && typeof res.tagDisplayMap === "object") {
            tagDisplayMap = Object.assign({}, tagDisplayMap, res.tagDisplayMap);
          }
          if (typeof res.primaryLanguage === "string" && res.primaryLanguage) {
            primaryLanguage = res.primaryLanguage;
          }

          if (res.focusFilters && !savingFilters && Date.now() >= suppressPollUntil) {
            currentFilters = normalize(res.focusFilters);
            if (typeof cfg.onApplyFilters === "function") {
              cfg.onApplyFilters(currentFilters);
            }
            syncFilterControls(currentFilters);
          } else if (acChanged) {
            syncFilterControls(currentFilters);
          }
          if (Array.isArray(res.sites)) {
            lastSites = res.sites;
            renderSitesList(lastSites);
            renderHeroMonitor();
          }
          if (!savingFilters) {
            applyIdleBadge();
          }
        });
      } catch (_) {}
    }

    function saveFilters(nextFilters) {
      const previousFilters = normalize(currentFilters);
      const normalized = normalize(nextFilters);
      currentFilters = normalized;
      applySizeStyles();
      applyAlphaStyles();
      const mySeq = ++saveSeq;
      savingFilters = true;
      suppressPollUntil = Date.now() + 1800;

      if (typeof cfg.onApplyFilters === "function") {
        cfg.onApplyFilters(normalized);
      }
      applyBadge("Salvando...", "is-warn");

      if (typeof cfg.onSaveFilters !== "function") {
        savingFilters = false;
        applyIdleBadge();
        return;
      }

      try {
        cfg.onSaveFilters(normalized, (res) => {
          if (mySeq !== saveSeq) return;
          savingFilters = false;
          if (res && res.success) {
            let acChanged = false;
            if (typeof res.antiCheatActive === "boolean") {
              acChanged = antiCheatActive !== res.antiCheatActive;
              antiCheatActive = res.antiCheatActive;
            }
            if (res.tagDisplayMap && typeof res.tagDisplayMap === "object") {
              tagDisplayMap = Object.assign({}, tagDisplayMap, res.tagDisplayMap);
            }
            if (typeof res.primaryLanguage === "string" && res.primaryLanguage) {
              primaryLanguage = res.primaryLanguage;
            }
            const saved = res.filters || res.focusFilters;
            if (saved) {
              currentFilters = normalize(saved);
              if (typeof cfg.onApplyFilters === "function") {
                cfg.onApplyFilters(currentFilters);
              }
              syncFilterControls(currentFilters);
            } else if (acChanged) {
              syncFilterControls(currentFilters);
            }
            isConnected = true;
            applyBadge("Salvo", "is-ok");
            setTimeout(() => {
              if (mySeq === saveSeq && !savingFilters) {
                applyIdleBadge();
              }
            }, 1200);
          } else {
            if (res && typeof res.isConnected === "boolean") {
              isConnected = res.isConnected;
            }
            if (res && typeof res.antiCheatActive === "boolean") {
              antiCheatActive = res.antiCheatActive;
            } else if (res && res.antiCheatLocked) {
              antiCheatActive = true;
            }
            const revertRaw = (res && (res.filters || res.focusFilters)) || previousFilters;
            currentFilters = normalize(revertRaw);
            if (typeof cfg.onApplyFilters === "function") {
              cfg.onApplyFilters(currentFilters);
            }
            syncFilterControls(currentFilters);
            if (res && res.antiCheatLocked) {
              showToast(res.message || "Anti-Cheat ativo: remo\u00e7\u00e3o bloqueada.");
              applyBadge("Bloqueado (AC)", "is-err");
            } else {
              applyBadge("Erro ao salvar", "is-err");
            }
          }
        });
      } catch (_) {
        if (mySeq === saveSeq) {
          savingFilters = false;
          currentFilters = previousFilters;
          syncFilterControls(currentFilters);
          applyBadge("Erro ao salvar", "is-err");
        }
      }
    }

    function togglePanel(forceState) {
      panelOpen = typeof forceState === "boolean" ? forceState : !panelOpen;
      if (panelOpen && viewMode !== "pill") {
        setViewMode("pill");
      }
      if (panelEl) {
        panelEl.classList.toggle("is-open", panelOpen);
      }
      if (panelOpen) {
        positionPanel();
        syncFilterControls(currentFilters);
        renderHeroMonitor();
        requestStatus();
      }
    }

    function unbindDragListeners() {
      if (!dragListenersBound || typeof window === "undefined") return;
      window.removeEventListener("pointermove", onWindowPointerMove, true);
      window.removeEventListener("pointerup", onWindowPointerUp, true);
      window.removeEventListener("pointercancel", onWindowPointerUp, true);
      dragListenersBound = false;
    }

    function onWindowPointerMove(ev) {
      if (!dragState) return;
      if (ev.pointerId !== undefined && dragState.pointerId !== undefined && ev.pointerId !== dragState.pointerId) {
        return;
      }
      const dx = (ev.clientX || 0) - dragState.startClientX;
      const dy = (ev.clientY || 0) - dragState.startClientY;
      if (!dragState.active) {
        if (Math.hypot(dx, dy) < 5) return;
        dragState.active = true;
        if (dragState.handleEl) {
          dragState.handleEl.classList.add("is-dragging");
          if (typeof dragState.handleEl.setPointerCapture === "function" && ev.pointerId !== undefined) {
            try {
              dragState.handleEl.setPointerCapture(ev.pointerId);
            } catch (_) {}
          }
        }
      }

      const { vw, vh } = viewportSize();
      const maxLeft = Math.max(8, vw - (dragState.width || 36) - 8);
      const maxTop = Math.max(8, vh - (dragState.height || 36) - 8);
      const nextLeft = Math.min(Math.max(8, dragState.startLeft + dx), maxLeft);
      const nextTop = Math.min(Math.max(8, dragState.startTop + dy), maxTop);

      dragState.lastLeft = nextLeft;
      dragState.lastTop = nextTop;

      if (hudHost && hudHost.style) {
        hudHost.style.left = Math.round(nextLeft) + "px";
        hudHost.style.top = Math.round(nextTop) + "px";
        hudHost.style.right = "auto";
        hudHost.style.bottom = "auto";
      }
      if (panelOpen) positionPanel();
    }

    function onWindowPointerUp(ev) {
      if (!dragState) {
        unbindDragListeners();
        return;
      }
      if (ev && ev.pointerId !== undefined && dragState.pointerId !== undefined && ev.pointerId !== dragState.pointerId) {
        return;
      }
      unbindDragListeners();

      if (
        dragState.handleEl &&
        ev &&
        ev.pointerId !== undefined &&
        typeof dragState.handleEl.releasePointerCapture === "function"
      ) {
        try {
          dragState.handleEl.releasePointerCapture(ev.pointerId);
        } catch (_) {}
      }

      if (dragState.active) {
        suppressClickUntil = Date.now() + 120;
        if (dragState.handleEl) dragState.handleEl.classList.remove("is-dragging");

        const finalLeft = typeof dragState.lastLeft === "number" ? dragState.lastLeft : dragState.startLeft;
        const finalTop = typeof dragState.lastTop === "number" ? dragState.lastTop : dragState.startTop;
        const { vw, vh } = viewportSize();
        const w = dragState.width || 36;
        const h = dragState.height || 36;
        const leftDist = finalLeft;
        const rightDist = Math.max(8, vw - (finalLeft + w));
        const topDist = finalTop;
        const bottomDist = Math.max(8, vh - (finalTop + h));

        currentPos = {
          anchorX: leftDist <= rightDist ? "left" : "right",
          offsetX: Math.max(8, Math.round(leftDist <= rightDist ? leftDist : rightDist)),
          anchorY: topDist <= bottomDist ? "top" : "bottom",
          offsetY: Math.max(8, Math.round(topDist <= bottomDist ? topDist : bottomDist)),
        };
        applyHostPosition();
        persistPosition(currentPos);
        if (panelOpen) positionPanel();
      }
      dragState = null;
    }

    function bindDraggable(el, options) {
      el.addEventListener("pointerdown", (ev) => {
        if (!ev) return;
        if (ev.button !== undefined && ev.button !== 0) return;
        if (options && typeof options.shouldIgnore === "function" && options.shouldIgnore(ev)) {
          return;
        }
        const rect = handleRect();
        dragState = {
          handleEl: el,
          pointerId: ev.pointerId,
          startClientX: ev.clientX || 0,
          startClientY: ev.clientY || 0,
          startLeft: rect.left || 0,
          startTop: rect.top || 0,
          width: rect.width || 36,
          height: rect.height || 36,
          active: false,
          lastLeft: rect.left || 0,
          lastTop: rect.top || 0,
        };
        if (!dragListenersBound && typeof window !== "undefined") {
          window.addEventListener("pointermove", onWindowPointerMove, true);
          window.addEventListener("pointerup", onWindowPointerUp, true);
          window.addEventListener("pointercancel", onWindowPointerUp, true);
          dragListenersBound = true;
        }
      });
    }

    function onDocClick(ev) {
      if (!panelOpen || !hudHost) return;
      if (Date.now() < suppressClickUntil) return;
      const path = typeof ev.composedPath === "function" ? ev.composedPath() : null;
      if (path) {
        if (path.indexOf(hudHost) !== -1) return;
      } else if (ev.target === hudHost || (hudHost.contains && hudHost.contains(ev.target))) {
        return;
      }
      togglePanel(false);
    }

    function onWindowKeyDown(ev) {
      if (!ev) return;
      if (panelOpen && ev.key === "Escape") {
        togglePanel(false);
        return;
      }
      if (
        ev.altKey &&
        ev.shiftKey &&
        !ev.ctrlKey &&
        !ev.metaKey &&
        (ev.code === "KeyC" || (ev.key && ev.key.toLowerCase() === "c"))
      ) {
        if (typeof ev.preventDefault === "function") ev.preventDefault();
        if (viewMode === "hidden") {
          setViewMode("pill");
        } else {
          setViewMode("hidden", { showToast: true });
        }
      }
    }

    function onWindowResize() {
      if (!hudHost || dragState) return;
      applyHostPosition();
      if (panelOpen) positionPanel();
    }

    function bindGlobalListeners() {
      if (listenersBound || typeof document === "undefined") return;
      document.addEventListener("click", onDocClick, true);
      if (typeof window !== "undefined") {
        window.addEventListener("keydown", onWindowKeyDown, true);
        window.addEventListener("resize", onWindowResize, { passive: true });
      }
      listenersBound = true;
    }

    function unbindGlobalListeners() {
      unbindDragListeners();
      if (!listenersBound || typeof document === "undefined") return;
      document.removeEventListener("click", onDocClick, true);
      if (typeof window !== "undefined") {
        window.removeEventListener("keydown", onWindowKeyDown, true);
        window.removeEventListener("resize", onWindowResize);
      }
      listenersBound = false;
    }

    function destroy() {
      hideToast();
      unbindGlobalListeners();
      dragState = null;
      if (hudHost && hudHost.parentNode) {
        try {
          hudHost.parentNode.removeChild(hudHost);
        } catch (_) {}
      }
      hudHost = null;
      hudShadow = null;
      pillWrapEl = null;
      pillMainBtn = null;
      pillDot = null;
      pillLabel = null;
      pillHideBtn = null;
      eyeBtnEl = null;
      eyeDotEl = null;
      panelEl = null;
      panelConnBadge = null;
      viewTempoEl = null;
      viewFiltersEl = null;
      navTempoBtn = null;
      navFiltersBtn = null;
      heroCardEl = null;
      heroTitleEl = null;
      heroTokensEl = null;
      heroClockEl = null;
      heroProgressFillEl = null;
      heroConsumedEl = null;
      heroQuotaEl = null;
      heroActivityEl = null;
      sitesContainerEl = null;
      alphaSliderEl = null;
      alphaValueEl = null;
      hideToEyeChkEl = null;
      toastEl = null;
    }

    function ensureMounted() {
      if (typeof document === "undefined") return false;
      if (typeof window !== "undefined" && window.top !== window.self) {
        return false;
      }

      if (source === "extension") {
        const proxyEl = document.querySelector('#chronos-focus-hud[data-chronos-proxy="1"]');
        if (proxyEl) {
          if (hudHost) destroy();
          return false;
        }
      } else {
        const extEl = document.querySelector('#chronos-focus-hud[data-chronos-extension="1"]');
        if (extEl && extEl !== hudHost && extEl.parentNode) {
          try {
            extEl.parentNode.removeChild(extEl);
          } catch (_) {}
        }
      }

      const target = document.body || document.documentElement;
      if (!target) return false;

      if (hudHost) {
        if (!hudHost.isConnected || hudHost.parentNode !== target) {
          target.appendChild(hudHost);
          applyHostPosition();
        }
        return true;
      }

      hudHost = document.createElement("div");
      hudHost.id = "chronos-focus-hud";
      hudHost.setAttribute(source === "proxy" ? "data-chronos-proxy" : "data-chronos-extension", "1");
      hudShadow = hudHost.attachShadow({ mode: "open" });

      attachShadowStyles(hudShadow, cfg.nonce);

      // 1. Pílula compacta sem "⚙ Filtros" e sem 6 pontinhos
      pillWrapEl = document.createElement("div");
      pillWrapEl.className = "c-pill";
      bindDraggable(pillWrapEl, {
        shouldIgnore: (ev) =>
          !!(pillHideBtn && (ev.target === pillHideBtn || (pillHideBtn.contains && pillHideBtn.contains(ev.target)))),
      });

      pillMainBtn = document.createElement("button");
      pillMainBtn.type = "button";
      pillMainBtn.className = "c-pill-main";
      pillMainBtn.title = "Clique para abrir o Chronos ou arraste para mover";
      pillDot = document.createElement("span");
      pillDot.className = "c-dot is-neutral";
      pillLabel = document.createElement("span");
      pillLabel.className = "c-label";
      pillLabel.textContent = "Chronos";
      pillMainBtn.appendChild(pillDot);
      pillMainBtn.appendChild(pillLabel);
      pillMainBtn.addEventListener("click", (ev) => {
        ev.stopPropagation();
        if (Date.now() < suppressClickUntil) {
          if (typeof ev.preventDefault === "function") ev.preventDefault();
          return;
        }
        togglePanel();
      });

      pillHideBtn = document.createElement("button");
      pillHideBtn.type = "button";
      pillHideBtn.className = "c-pill-hide";
      pillHideBtn.setAttribute("aria-label", "Esconder p\u00edlula");
      pillHideBtn.title = "Esconder p\u00edlula";
      pillHideBtn.appendChild(createEyeOffIcon(13));
      pillHideBtn.addEventListener("click", (ev) => {
        ev.stopPropagation();
        setHidden(true);
      });

      pillWrapEl.appendChild(pillMainBtn);
      pillWrapEl.appendChild(pillHideBtn);

      // 2. Olho flutuante arrastável (ao esconder quando hudHideToEye = true)
      eyeBtnEl = document.createElement("button");
      eyeBtnEl.type = "button";
      eyeBtnEl.className = "c-eye";
      eyeBtnEl.setAttribute("aria-label", "Restaurar p\u00edlula do Chronos");
      eyeBtnEl.title = "Clique para expandir a p\u00edlula ou arraste para mover";
      eyeDotEl = document.createElement("span");
      eyeDotEl.className = "c-eye-dot is-neutral";
      eyeBtnEl.appendChild(createEyeOffIcon(17));
      eyeBtnEl.appendChild(eyeDotEl);
      bindDraggable(eyeBtnEl);
      eyeBtnEl.addEventListener("click", (ev) => {
        ev.stopPropagation();
        if (Date.now() < suppressClickUntil) {
          if (typeof ev.preventDefault === "function") ev.preventDefault();
          return;
        }
        setViewMode("pill");
      });

      // 3. Miniatura do App Chronos
      panelEl = document.createElement("div");
      panelEl.className = "c-panel";

      const appbar = document.createElement("div");
      appbar.className = "c-appbar";
      const brand = document.createElement("div");
      brand.className = "c-brand";
      const brandIcon = document.createElement("span");
      brandIcon.className = "c-brand-icon";
      brandIcon.appendChild(createShieldIcon(15));
      const title = document.createElement("span");
      title.className = "c-title";
      title.textContent = "Chronos";
      const sub = document.createElement("span");
      sub.className = "c-title-sub";
      sub.textContent = "FOCUS";
      brand.appendChild(brandIcon);
      brand.appendChild(title);
      brand.appendChild(sub);

      const headRight = document.createElement("div");
      headRight.className = "c-head-right";
      panelConnBadge = document.createElement("span");
      panelConnBadge.className = "c-badge is-ok";
      applyIdleBadge();

      const drawerHideBtn = document.createElement("button");
      drawerHideBtn.type = "button";
      drawerHideBtn.className = "c-icon-btn c-hide";
      drawerHideBtn.setAttribute("aria-label", "Esconder p\u00edlula");
      drawerHideBtn.title = "Esconder p\u00edlula";
      drawerHideBtn.appendChild(createEyeOffIcon(14));
      drawerHideBtn.addEventListener("click", (ev) => {
        ev.stopPropagation();
        setHidden(true);
      });

      const closeBtn = document.createElement("button");
      closeBtn.type = "button";
      closeBtn.className = "c-icon-btn c-close";
      closeBtn.setAttribute("aria-label", "Fechar miniatura");
      closeBtn.textContent = "\u00D7";
      closeBtn.addEventListener("click", () => togglePanel(false));

      headRight.appendChild(panelConnBadge);
      headRight.appendChild(drawerHideBtn);
      headRight.appendChild(closeBtn);
      appbar.appendChild(brand);
      appbar.appendChild(headRight);

      // View 1: Aba Tempo (Live Monitor Card + Sessões)
      viewTempoEl = document.createElement("div");
      viewTempoEl.className = "c-view-wrap";

      heroCardEl = document.createElement("div");
      heroCardEl.className = "c-hero is-free";

      const heroTop = document.createElement("div");
      heroTop.className = "c-hero-top";
      const heroId = document.createElement("div");
      heroId.className = "c-hero-id";
      const heroShield = document.createElement("span");
      heroShield.className = "c-hero-shield";
      heroShield.appendChild(createShieldIcon(18));
      heroTitleEl = document.createElement("div");
      heroTitleEl.className = "c-hero-name";
      heroTitleEl.textContent = "Navega\u00e7\u00e3o Livre";
      heroId.appendChild(heroShield);
      heroId.appendChild(heroTitleEl);

      heroTokensEl = document.createElement("span");
      heroTokensEl.className = "c-tokens-pill is-hidden";
      heroTop.appendChild(heroId);
      heroTop.appendChild(heroTokensEl);

      heroClockEl = document.createElement("div");
      heroClockEl.className = "c-hero-clock";
      heroClockEl.textContent = "Sem limite ativo";

      const progTrack = document.createElement("div");
      progTrack.className = "c-progress-track";
      heroProgressFillEl = document.createElement("div");
      heroProgressFillEl.className = "c-progress-fill";
      progTrack.appendChild(heroProgressFillEl);

      const heroMeta = document.createElement("div");
      heroMeta.className = "c-hero-meta";
      heroConsumedEl = document.createElement("span");
      heroQuotaEl = document.createElement("span");
      heroMeta.appendChild(heroConsumedEl);
      heroMeta.appendChild(heroQuotaEl);

      const actWrap = document.createElement("div");
      actWrap.className = "c-activity";
      const actDot = document.createElement("span");
      actDot.className = "c-activity-dot";
      heroActivityEl = document.createElement("span");
      actWrap.appendChild(actDot);
      actWrap.appendChild(heroActivityEl);

      heroCardEl.appendChild(heroTop);
      heroCardEl.appendChild(heroClockEl);
      heroCardEl.appendChild(progTrack);
      heroCardEl.appendChild(heroMeta);
      heroCardEl.appendChild(actWrap);
      viewTempoEl.appendChild(heroCardEl);

      const secSites = document.createElement("div");
      secSites.className = "c-sec";
      secSites.textContent = "Sites e Sess\u00f5es Monitoradas";
      viewTempoEl.appendChild(secSites);

      sitesContainerEl = document.createElement("div");
      sitesContainerEl.className = "c-sites";
      renderSitesList([]);
      viewTempoEl.appendChild(sitesContainerEl);

      // View 2: Aba Filtros (HUD Alfa + Olho + Plataformas)
      viewFiltersEl = document.createElement("div");
      viewFiltersEl.className = "c-view-wrap is-hidden";

      const hudSecLabel = document.createElement("div");
      hudSecLabel.className = "c-sec";
      hudSecLabel.textContent = "P\u00edlula & Filtros de Foco";
      viewFiltersEl.appendChild(hudSecLabel);

      const hudCard = document.createElement("div");
      hudCard.className = "c-card";

      const hudGrp = document.createElement("div");
      hudGrp.className = "c-grp-title c-grp-hud";
      hudGrp.textContent = "HUD FLUTUANTE";
      hudCard.appendChild(hudGrp);

      function buildHudRangeControl(opts) {
        const block = document.createElement("div");
        block.className = "c-slider-block";
        const head = document.createElement("div");
        head.className = "c-slider-head";
        const lbl = document.createElement("span");
        lbl.textContent = opts.label;
        const valEl = document.createElement("span");
        valEl.className = "c-slider-val";
        valEl.textContent = opts.initialPct + "%";
        head.appendChild(lbl);
        head.appendChild(valEl);

        const range = document.createElement("input");
        range.type = "range";
        range.className = "c-range";
        range.min = String(opts.min);
        range.max = String(opts.max);
        range.step = String(opts.step);
        range.setAttribute("data-filter-key", opts.filterKey);
        range.value = String(opts.initialPct);
        range.addEventListener("input", () => opts.onInput(Number(range.value)));
        range.addEventListener("change", () => opts.onChange(Number(range.value)));

        block.appendChild(head);
        block.appendChild(range);
        hudCard.appendChild(block);
        return { range, valEl };
      }

      const alphaCtrl = buildHudRangeControl({
        label: "Opacidade da P\u00edlula (Alfa)",
        min: 15,
        max: 100,
        step: 5,
        filterKey: "hudAlpha",
        initialPct: Math.round(clampAlpha(currentFilters.hudAlpha) * 100),
        onInput: (pct) => {
          const nextAlpha = clampAlpha(pct / 100);
          currentFilters.hudAlpha = nextAlpha;
          if (alphaValueEl) alphaValueEl.textContent = Math.round(nextAlpha * 100) + "%";
          applyAlphaStyles();
        },
        onChange: (pct) => {
          saveFilters(Object.assign({}, currentFilters, { hudAlpha: clampAlpha(pct / 100) }));
        },
      });
      alphaSliderEl = alphaCtrl.range;
      alphaValueEl = alphaCtrl.valEl;

      const scaleCtrl = buildHudRangeControl({
        label: "Tamanho da P\u00edlula",
        min: 70,
        max: 160,
        step: 5,
        filterKey: "hudScale",
        initialPct: Math.round(clampScale(currentFilters.hudScale) * 100),
        onInput: (pct) => {
          const nextScale = clampScale(pct / 100);
          currentFilters.hudScale = nextScale;
          if (scaleValueEl) scaleValueEl.textContent = Math.round(nextScale * 100) + "%";
          applySizeStyles();
          applyHostPosition();
          if (panelOpen) positionPanel();
        },
        onChange: (pct) => {
          saveFilters(Object.assign({}, currentFilters, { hudScale: clampScale(pct / 100) }));
        },
      });
      scaleSliderEl = scaleCtrl.range;
      scaleValueEl = scaleCtrl.valEl;

      const eyeRow = document.createElement("label");
      eyeRow.className = "c-filter-row";
      const eyeLbl = document.createElement("span");
      eyeLbl.textContent = "Ao esconder, virar Olho arrast\u00e1vel";
      hideToEyeChkEl = document.createElement("input");
      hideToEyeChkEl.type = "checkbox";
      hideToEyeChkEl.className = "c-switch";
      hideToEyeChkEl.setAttribute("data-filter-key", "hudHideToEye");
      hideToEyeChkEl.checked = currentFilters.hudHideToEye !== false;
      hideToEyeChkEl.addEventListener("change", () => {
        const next = Object.assign({}, currentFilters, {
          hudHideToEye: !!hideToEyeChkEl.checked,
        });
        saveFilters(next);
      });
      eyeRow.appendChild(eyeLbl);
      eyeRow.appendChild(hideToEyeChkEl);
      hudCard.appendChild(eyeRow);
      viewFiltersEl.appendChild(hudCard);

      const filtersCard = document.createElement("div");
      filtersCard.className = "c-card";
      FILTER_GROUPS.forEach((grp, idx) => {
        if (idx > 0) {
          const div = document.createElement("div");
          div.className = "c-divider";
          filtersCard.appendChild(div);
        }
        const gTitle = document.createElement("div");
        gTitle.className = "c-grp-title " + grp.cls;
        gTitle.textContent = grp.title;
        filtersCard.appendChild(gTitle);

        grp.items.forEach((item) => {
          const key = item[0];
          const labelText = item[1];
          const lbl = document.createElement("label");
          lbl.className = "c-filter-row";
          const sp = document.createElement("span");
          sp.textContent = labelText;
          const chk = document.createElement("input");
          chk.type = "checkbox";
          chk.className = "c-switch";
          chk.setAttribute("data-filter-key", key);
          chk.addEventListener("change", () => {
            const next = Object.assign({}, currentFilters);
            next[key] = chk.checked;
            if (key === "globalGrayscale") next.grayscaleMode = chk.checked;
            if (key === "globalBlockNotifications") next.blockNotifications = chk.checked;
            saveFilters(next);
          });
          filterCheckboxes[key] = chk;
          lbl.appendChild(sp);
          lbl.appendChild(chk);
          filtersCard.appendChild(lbl);
        });
      });

      const lnDiv = document.createElement("div");
      lnDiv.className = "c-divider";
      filtersCard.appendChild(lnDiv);

      const lnTitle = document.createElement("div");
      lnTitle.className = "c-grp-title c-grp-ln";
      lnTitle.textContent = "\uD83C\uDFAE LAUNCHERS & JOGOS";
      filtersCard.appendChild(lnTitle);

      launcherLockNoteEl = document.createElement("div");
      launcherLockNoteEl.className = "c-ac-lock" + (antiCheatActive ? "" : " is-hidden");
      launcherLockNoteEl.textContent = "Anti-Cheat ativo: desative para remover tags/nomes ou desligar o filtro.";
      filtersCard.appendChild(launcherLockNoteEl);

      const lnRow = document.createElement("label");
      lnRow.className = "c-filter-row";
      const lnLbl = document.createElement("span");
      lnLbl.textContent = "Bloquear jogos por tag/nome (Launchers & Web)";
      launcherEnabledChkEl = document.createElement("input");
      launcherEnabledChkEl.type = "checkbox";
      launcherEnabledChkEl.className = "c-switch";
      launcherEnabledChkEl.setAttribute("data-filter-key", "launcherFilterEnabled");
      launcherEnabledChkEl.checked = currentFilters.launcherFilterEnabled !== false;
      launcherEnabledChkEl.addEventListener("change", () => {
        if (!launcherEnabledChkEl.checked && antiCheatActive) {
          launcherEnabledChkEl.checked = true;
          showToast("Anti-Cheat ativo: desative para desligar o filtro de launchers.");
          return;
        }
        saveFilters(
          Object.assign({}, currentFilters, {
            launcherFilterEnabled: !!launcherEnabledChkEl.checked,
          })
        );
      });
      lnRow.appendChild(lnLbl);
      lnRow.appendChild(launcherEnabledChkEl);
      filtersCard.appendChild(lnRow);

      function buildLauncherTermEditor(opts) {
        const lbl = document.createElement("div");
        lbl.className = "c-term-lbl";
        lbl.textContent = opts.label;
        filtersCard.appendChild(lbl);

        const row = document.createElement("div");
        row.className = "c-term-row";
        const input = document.createElement("input");
        input.type = "text";
        input.className = "c-term-in";
        input.placeholder = opts.placeholder;
        input.setAttribute("data-launcher-input", opts.attrName);

        const addBtn = document.createElement("button");
        addBtn.type = "button";
        addBtn.className = "c-term-btn";
        addBtn.textContent = "+ Add";

        const acMenu = document.createElement("div");
        acMenu.className = "c-ac-menu is-hidden";
        let debounceTimer = null;
        let querySeq = 0;

        function clearSuggestions() {
          acMenu.textContent = "";
          acMenu.classList.add("is-hidden");
        }

        function submitValue(rawOverride) {
          const val = String(rawOverride !== undefined ? rawOverride : input.value || "").trim();
          if (!val) return;
          const prev = Array.isArray(currentFilters[opts.filterKey])
            ? currentFilters[opts.filterKey]
            : [];
          input.value = "";
          clearSuggestions();
          if (prev.some((p) => String(p).trim().toLowerCase() === val.toLowerCase())) {
            showToast('"' + val + '" já está na lista.');
            return;
          }
          saveFilters(
            Object.assign({}, currentFilters, {
              [opts.filterKey]: prev.concat([val]),
            })
          );
        }

        function renderSuggestions(items) {
          acMenu.textContent = "";
          if (!Array.isArray(items) || !items.length) {
            acMenu.classList.add("is-hidden");
            return;
          }
          items.slice(0, 8).forEach((item) => {
            const val = opts.autocompleteKind === "game" ? item.title : item.canonicalEn;
            const mainLabel =
              opts.autocompleteKind === "game" ? item.title : item.displayName || item.canonicalEn;
            const subLabel =
              opts.autocompleteKind === "game"
                ? item.appId > 0
                  ? "#" + item.appId
                  : item.source || ""
                : mainLabel.toLowerCase() !== String(val || "").toLowerCase()
                  ? val
                  : "";
            if (!val) return;
            const btn = document.createElement("button");
            btn.type = "button";
            btn.className = "c-ac-item";
            const left = document.createElement("span");
            left.className = "c-ac-left";
            if (item.tinyImage) {
              const img = document.createElement("img");
              img.className = "c-ac-thumb";
              img.src = item.tinyImage;
              img.alt = "";
              left.appendChild(img);
            }
            const tSpan = document.createElement("span");
            tSpan.className = "c-ac-title";
            tSpan.textContent = mainLabel;
            left.appendChild(tSpan);
            btn.appendChild(left);
            if (subLabel) {
              const sSpan = document.createElement("span");
              sSpan.className = "c-ac-sub";
              sSpan.textContent = subLabel;
              btn.appendChild(sSpan);
            }
            btn.addEventListener("click", (ev) => {
              ev.stopPropagation();
              if (opts.autocompleteKind === "tag" && val && mainLabel) {
                tagDisplayMap[val] = mainLabel;
              }
              submitValue(val);
            });
            acMenu.appendChild(btn);
          });
          acMenu.classList.remove("is-hidden");
        }

        function requestSuggestions(q) {
          if (typeof cfg.onSearchLauncherAutocomplete !== "function") return;
          const mySeq = ++querySeq;
          cfg.onSearchLauncherAutocomplete(opts.autocompleteKind, q, (res) => {
            if (mySeq !== querySeq) return;
            if (!res || !Array.isArray(res.results)) {
              clearSuggestions();
              return;
            }
            renderSuggestions(res.results);
          });
        }

        input.addEventListener("input", () => {
          if (debounceTimer) clearTimeout(debounceTimer);
          const q = String(input.value || "").trim();
          const minLen = opts.autocompleteKind === "game" ? 2 : 1;
          if (q.length < minLen) {
            clearSuggestions();
            return;
          }
          debounceTimer = setTimeout(() => requestSuggestions(q), 220);
        });

        addBtn.addEventListener("click", (ev) => {
          ev.stopPropagation();
          submitValue();
        });
        input.addEventListener("keydown", (ev) => {
          if (ev.key === "Enter") {
            ev.preventDefault();
            submitValue();
          } else if (ev.key === "Escape") {
            clearSuggestions();
          }
        });

        row.appendChild(input);
        row.appendChild(addBtn);
        filtersCard.appendChild(row);
        filtersCard.appendChild(acMenu);

        const chipsWrap = document.createElement("div");
        chipsWrap.className = "c-chips";
        filtersCard.appendChild(chipsWrap);
        return chipsWrap;
      }

      launcherTagsWrapEl = buildLauncherTermEditor({
        label: "Tags bloqueadas (Steam API)",
        placeholder: "Buscar tag (ex: Ação, Souls-like, Terror)...",
        attrName: "tags",
        autocompleteKind: "tag",
        filterKey: "launcherBlockedTags",
      });
      launcherNamesWrapEl = buildLauncherTermEditor({
        label: "Nomes/jogos bloqueados",
        placeholder: "Buscar jogo na Steam API...",
        attrName: "names",
        autocompleteKind: "game",
        filterKey: "launcherBlockedNames",
      });

      viewFiltersEl.appendChild(filtersCard);

      // Barra de Navegação Inferior estilo App
      const navbar = document.createElement("nav");
      navbar.className = "c-navbar";
      navTempoBtn = document.createElement("button");
      navTempoBtn.type = "button";
      navTempoBtn.className = "c-nav-btn is-active";
      navTempoBtn.setAttribute("data-nav-tab", "tempo");
      navTempoBtn.appendChild(createClockIcon(14));
      const tLbl = document.createElement("span");
      tLbl.textContent = "Tempo";
      navTempoBtn.appendChild(tLbl);
      navTempoBtn.addEventListener("click", () => setActiveTab("tempo"));

      navFiltersBtn = document.createElement("button");
      navFiltersBtn.type = "button";
      navFiltersBtn.className = "c-nav-btn";
      navFiltersBtn.setAttribute("data-nav-tab", "filtros");
      navFiltersBtn.appendChild(createSlidersIcon(14));
      const fLbl = document.createElement("span");
      fLbl.textContent = "Filtros";
      navFiltersBtn.appendChild(fLbl);
      navFiltersBtn.addEventListener("click", () => setActiveTab("filtros"));

      navbar.appendChild(navTempoBtn);
      navbar.appendChild(navFiltersBtn);

      toastEl = document.createElement("div");
      toastEl.className = "c-toast is-hidden";

      panelEl.appendChild(appbar);
      panelEl.appendChild(viewTempoEl);
      panelEl.appendChild(viewFiltersEl);
      panelEl.appendChild(navbar);

      hudShadow.appendChild(panelEl);
      hudShadow.appendChild(pillWrapEl);
      hudShadow.appendChild(eyeBtnEl);
      hudShadow.appendChild(toastEl);
      target.appendChild(hudHost);

      syncVisibilityDom();
      applySizeStyles();
      applyAlphaStyles();
      applyHostPosition();
      bindGlobalListeners();
      syncFilterControls(currentFilters);
      updateRule(lastMatchedRule);
      return true;
    }

    function updateRule(rule) {
      lastMatchedRule = rule || null;
      if (!ensureMounted()) return;
      if (!pillDot || !pillLabel) return;

      if (!rule || rule.remainingSeconds === undefined) {
        pillDot.className = "c-dot is-neutral";
        if (eyeDotEl) eyeDotEl.className = "c-eye-dot is-neutral";
        pillLabel.textContent = "Chronos";
      } else {
        const rem = rule.remainingSeconds || 0;
        const dotState = rem <= 300 ? "is-danger" : rem <= 900 ? "is-warn" : "is-ok";
        pillDot.className = "c-dot " + dotState;
        if (eyeDotEl) eyeDotEl.className = "c-eye-dot " + dotState;
        pillLabel.textContent = (rule.displayName || "Chronos") + ": " + formatTime(rem);
      }

      if (panelOpen) {
        renderHeroMonitor();
      }
    }

    function syncFilters(filters, nextTagMap, nextLang, nextAntiCheatActive) {
      if (nextTagMap && typeof nextTagMap === "object") {
        tagDisplayMap = Object.assign({}, tagDisplayMap, nextTagMap);
      }
      if (typeof nextLang === "string" && nextLang) {
        primaryLanguage = nextLang;
      }
      let acChanged = false;
      if (typeof nextAntiCheatActive === "boolean") {
        acChanged = antiCheatActive !== nextAntiCheatActive;
        antiCheatActive = nextAntiCheatActive;
      }
      if (!filters) {
        if (acChanged && !savingFilters && Date.now() >= suppressPollUntil) {
          syncFilterControls(currentFilters);
        }
        return;
      }
      if (savingFilters || Date.now() < suppressPollUntil) return;
      currentFilters = normalize(filters);
      syncFilterControls(currentFilters);
    }

    function setConnectionState(connected) {
      isConnected = !!connected;
      if (!savingFilters) {
        applyIdleBadge();
      }
    }

    function pollIfPanelOpen() {
      if (!panelOpen || viewMode !== "pill" || (typeof document !== "undefined" && document.hidden)) return;
      requestStatus();
    }

    return {
      ensureMounted,
      destroy,
      updateRule,
      syncFilters,
      setConnectionState,
      pollIfPanelOpen,
      setActiveTab,
      setViewMode,
      setHidden,
      resetPosition,
      setPosition,
      getPosition: () => (currentPos ? Object.assign({}, currentPos) : null),
      getViewMode: () => viewMode,
      isHidden: () => viewMode !== "pill",
      isPanelOpen: () => panelOpen,
      isSaving: () => savingFilters,
      getSuppressPollUntil: () => suppressPollUntil,
    };
  }

  globalScope.ChronosHudPanel = {
    FILTER_GROUPS,
    HUD_STYLES,
    formatTime,
    formatHms,
    clampAlpha,
    clampScale,
    create,
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = globalScope.ChronosHudPanel;
  }
})(typeof globalThis !== "undefined" ? globalThis : this);
