#!/usr/bin/env bash
# Generates the Ed25519 key that signs Chronos release manifests (latest.json).
# The PRIVATE key must never be committed: keep a backup (password manager) and
# register it as the GitHub secret CHRONOS_UPDATE_SIGNING_KEY.
set -euo pipefail

OUT_DIR="${1:-$HOME/.config/chronos-release}"
KEY="$OUT_DIR/chronos-update-signing.pem"

if [ -e "$KEY" ]; then
  echo "Já existe uma chave em $KEY — não sobrescrevo (perder a chave impede atualizações)." >&2
else
  install -d -m 0700 "$OUT_DIR"
  (umask 077 && openssl genpkey -algorithm ed25519 -out "$KEY")
  echo "Chave privada criada: $KEY"
fi

PUB_B64="$(openssl pkey -in "$KEY" -pubout -outform DER | tail -c 32 | base64 -w0)"
echo
echo "Chave pública (base64, 32 bytes): $PUB_B64"
echo "Coloque em rust/src/api/updater.rs -> UPDATE_PUBLIC_KEY_B64"
echo
echo "Próximos passos:"
echo "  1. Faça backup de $KEY fora deste computador."
echo "  2. gh secret set CHRONOS_UPDATE_SIGNING_KEY < \"$KEY\""
