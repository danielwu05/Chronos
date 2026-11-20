#!/usr/bin/env bash
# Builds the release app locally and opens it (without publishing a release).
# Chronos is single-instance and keeps running in the background, so the running
# copy is stopped first; otherwise launching the binary only re-shows the old build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
APP="$ROOT/build/linux/x64/release/bundle/chronos_app"

echo "==> cargo build --release (daemon + cofre)"
if ! (cd rust && cargo build --release --bin chronos_proxy --bin chronos_vault); then
  echo "Falha no build do Rust (veja o erro acima)." >&2
  exit 1
fi

echo "==> flutter build linux --release"
if ! flutter build linux --release; then
  echo "Falha no build (veja o erro acima). O app não foi reiniciado." >&2
  exit 1
fi

if pgrep -x chronos_app >/dev/null; then
  echo "==> encerrando a instância atual"
  pkill -x chronos_app || true
  for _ in $(seq 1 20); do
    pgrep -x chronos_app >/dev/null || break
    sleep 0.25
  done
fi

echo "==> abrindo $APP"
setsid -f "$APP" >/dev/null 2>&1
echo "Chronos (release) aberto."

# Firefox: when the AMO keys exist, sign the new extension version automatically (Firefox
# then updates itself from the app's HTTPS update server). Skip with CHRONOS_SKIP_FIREFOX_SIGN=1.
AMO_ENV="${CHRONOS_AMO_ENV:-$HOME/.config/chronos-release/amo.env}"
if [ -z "${CHRONOS_SKIP_FIREFOX_SIGN:-}" ] && { [ -f "$AMO_ENV" ] || [ -n "${AMO_JWT_ISSUER:-}" ]; }; then
  served=""
  for _ in $(seq 1 60); do
    served="$(curl -fsS http://127.0.0.1:4545/extension/update.xml 2>/dev/null | grep -o "version='[0-9.]*'" | tail -1 | tr -d "version='")" || true
    [ -n "$served" ] && break
    sleep 1
  done
  SIGNED_XPI="$HOME/.local/share/chronos/chronos-signed.xpi"
  signed="$(unzip -p "$SIGNED_XPI" manifest.json 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["version"])' 2>/dev/null || true)"
  if [ -z "$served" ]; then
    echo "==> Firefox: versão servida pelo app não encontrada; assinatura pulada."
  elif [ "$served" = "$signed" ] || [ "${signed#"$served".}" != "$signed" ]; then
    echo "==> Firefox: extensão $served já assinada."
  else
    echo "==> Firefox: assinando a extensão $served na AMO (pode levar alguns minutos)"
    if CHRONOS_XPI_VERSION="$served" "$ROOT/scripts/sign-firefox.sh"; then
      echo "Firefox vai se atualizar sozinho pelo app."
    else
      echo "Assinatura do Firefox falhou (o app continua funcionando; rode scripts/sign-firefox.sh depois)." >&2
    fi
  fi
fi
