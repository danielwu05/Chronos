#!/usr/bin/env bash
# Signs the Firefox extension through Mozilla's AMO API (channel "unlisted": private,
# never listed on addons.mozilla.org). Firefox release only installs signed add-ons.
#
# One-time setup:
#   1. Create an AMO account and API key: https://addons.mozilla.org/developers/addon/api/key/
#   2. Save them (never commit this file):
#        mkdir -p ~/.config/chronos-release
#        printf 'AMO_JWT_ISSUER=%s\nAMO_JWT_SECRET=%s\n' 'user:123:456' 'secret' > ~/.config/chronos-release/amo.env
#        chmod 600 ~/.config/chronos-release/amo.env
#
# Usage: scripts/sign-firefox.sh
# Output: ~/.local/share/chronos/chronos-signed.xpi (picked up by the app's packager);
# then open Chronos → Configurações → "Atualizar Guard" so Firefox gets it.
#
# CI / overrides (environment):
#   AMO_JWT_ISSUER, AMO_JWT_SECRET   keys (instead of the amo.env file)
#   CHRONOS_XPI_VERSION              extension version to sign (default: what the app serves)
#   CHRONOS_XPI_OUT                  output path of the signed XPI
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${CHRONOS_AMO_ENV:-$HOME/.config/chronos-release/amo.env}"
OUT="${CHRONOS_XPI_OUT:-$HOME/.local/share/chronos/chronos-signed.xpi}"

die() { echo "sign-firefox: $*" >&2; exit 1; }

if [ -z "${AMO_JWT_ISSUER:-}" ] || [ -z "${AMO_JWT_SECRET:-}" ]; then
  [ -f "$ENV_FILE" ] || die "chaves da AMO não encontradas em $ENV_FILE (veja o topo deste script)."
  perm="$(stat -c %a "$ENV_FILE")"
  [ "$perm" = "600" ] || [ "$perm" = "400" ] || die "$ENV_FILE precisa de permissão 600 (chmod 600 $ENV_FILE)."
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi
[ -n "${AMO_JWT_ISSUER:-}" ] && [ -n "${AMO_JWT_SECRET:-}" ] || die "AMO_JWT_ISSUER/AMO_JWT_SECRET vazios em $ENV_FILE."
command -v npx >/dev/null || die "npx (Node.js) não encontrado."

# Same version the app is serving to Chromium browsers (AMO needs a new version each time).
VERSION="${CHRONOS_XPI_VERSION:-}"
[ -n "$VERSION" ] || VERSION="$(curl -fsS http://127.0.0.1:4545/extension/update.xml 2>/dev/null | grep -o "version='[0-9.]*'" | tail -1 | tr -d "version='")"
[ -n "$VERSION" ] || VERSION="$(python3 -c "import json;print(json.load(open('$ROOT/chronos_extension_firefox/manifest.json'))['version'])")"
# AMO never accepts the same version twice (not even after a failed attempt), so each
# signing gets a unique 4th part (minutes since 1970): 1.1.109 -> 1.1.109.29361234.
# Firefox and the app treat it as >= the Chromium version.
if [ "$(echo "$VERSION" | tr -cd '.' | wc -c)" -lt 3 ]; then
  VERSION="$VERSION.$(( $(date +%s) / 60 ))"
fi
LOG_DIR="$HOME/.cache/chronos"
LOG="$LOG_DIR/sign-firefox.log"
mkdir -p "$LOG_DIR"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src" "$WORK/out"
(cd "$ROOT/chronos_extension_firefox" && tar --exclude='*.xpi' --exclude='*.pem' -cf - .) | (cd "$WORK/src" && tar -xf -)
python3 - "$WORK/src/manifest.json" "$VERSION" <<'PY'
import json, sys
path, version = sys.argv[1], sys.argv[2]
m = json.load(open(path))
m["version"] = version
json.dump(m, open(path, "w"), indent=2, ensure_ascii=False)
PY

echo "==> assinando Chronos $VERSION para Firefox (AMO, unlisted); log: $LOG"
# Keys go through the environment (web-ext reads WEB_EXT_*): never on the command line,
# which npm writes to ~/.npm/_logs.
set +e
WEB_EXT_API_KEY="$AMO_JWT_ISSUER" WEB_EXT_API_SECRET="$AMO_JWT_SECRET" \
  npx --yes --loglevel=error web-ext@8 sign \
  --channel=unlisted \
  --source-dir "$WORK/src" \
  --artifacts-dir "$WORK/out" \
  --approval-timeout 900000 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}
set -e
[ "$status" -eq 0 ] || die "web-ext falhou (código $status); veja $LOG"

SIGNED="$(ls "$WORK"/out/*.xpi 2>/dev/null | head -1)"
[ -n "$SIGNED" ] || die "a AMO não devolveu um XPI assinado."
unzip -l "$SIGNED" | grep -q 'META-INF/mozilla.rsa' || die "XPI sem assinatura da Mozilla."
mkdir -p "$(dirname "$OUT")"
cp "$SIGNED" "$OUT"
echo "XPI assinado: $OUT"
[ -n "${CI:-}" ] || echo "O Chronos publica a versão nova para o Firefox sozinho (até ~1 min); se não, Configurações → \"Atualizar Guard\"."
