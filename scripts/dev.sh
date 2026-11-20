#!/usr/bin/env bash
# Chronos dev environment: builds and runs the DEBUG app (dev profile) side by side
# with the installed release, without touching release data or system integrations.
#
#   scripts/dev.sh            build + run the dev app
#   scripts/dev.sh --browser  also open Chromium with a separate dev profile and the
#                             dev extension (talks to the dev daemon on 5545/5546)
#   scripts/dev.sh --no-build skip building
#   scripts/dev.sh --stop     stop the dev daemon
#
# Dev profile: ports 5545/5546, data ~/.local/share/chronos-dev, DB ~/Documents/chronos-dev.db,
# service chronos-proxy-dev.service (never enabled at login), closing the window quits.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEV_DIR="$HOME/.local/share/chronos-dev"
BUILD=1
BROWSER=0
for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD=0 ;;
    --browser) BROWSER=1 ;;
    --stop)
      systemctl --user stop chronos-proxy-dev.service 2>/dev/null || true
      echo "[dev] daemon dev parado."
      exit 0 ;;
    *) echo "uso: $0 [--no-build] [--browser] [--stop]" >&2; exit 2 ;;
  esac
done

cd "$ROOT"
if [ "$BUILD" -eq 1 ]; then
  echo "[dev] compilando daemon (debug) e app (debug)…"
  (cd rust && cargo build --bin chronos_proxy)
  flutter build linux --debug
fi

# Dev extension: same code, pointed at the dev daemon ports.
EXT="$DEV_DIR/extension"
rm -rf "$EXT"
mkdir -p "$EXT"
cp -r chronos_extension/. "$EXT/"
rm -f "$EXT"/*.crx "$EXT"/*.pem
grep -rl --include='*.js' --include='*.json' --include='*.html' '127.0.0.1:454[56]' "$EXT" \
  | xargs -r sed -i 's/127\.0\.0\.1:4545/127.0.0.1:5545/g; s/127\.0\.0\.1:4546/127.0.0.1:5546/g'
python3 - "$EXT/manifest.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p))
m["name"] = m.get("name", "Chronos") + " (DEV)"
m.pop("update_url", None)
json.dump(m, open(p, "w"), indent=2, ensure_ascii=False)
PY

if [ "$BROWSER" -eq 1 ]; then
  BROWSER_BIN="$(command -v chromium || command -v chromium-browser || true)"
  if [ -z "$BROWSER_BIN" ]; then
    echo "[dev] Chromium não encontrado; carregue $EXT manualmente (chrome://extensions → Carregar sem compactação)." >&2
  else
    echo "[dev] abrindo Chromium com perfil dev e extensão dev…"
    "$BROWSER_BIN" \
      --user-data-dir="$DEV_DIR/chromium-profile" \
      --disable-features=DisableLoadExtensionCommandLineSwitch \
      --load-extension="$EXT" \
      --no-first-run >/dev/null 2>&1 &
  fi
fi

echo "[dev] iniciando o app dev (fechar a janela encerra)…"
exec "$ROOT/build/linux/x64/debug/bundle/chronos_app"
