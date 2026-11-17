#!/usr/bin/env bash
# Chronos installer (Linux x64). Downloads the latest signed release from GitHub,
# verifies it, installs it under ~/.local/share/chronos/app and adds a menu entry.
# The app itself sets up the background daemon, browser extensions and (with your
# authorization) the system Guard on first launch.
#
#   curl -fsSL https://github.com/danielwu05/Chronos/releases/latest/download/install.sh | bash
set -euo pipefail

REPO="danielwu05/Chronos"
# Must match rust/src/api/updater.rs UPDATE_PUBLIC_KEY_B64.
PUBKEY_B64="eOeAJxxLfHQ2RSTUzC+hxwzJVXJAkIc+bsnHbSu6P4g="
BASE_URL="${CHRONOS_RELEASE_BASE:-https://github.com/$REPO/releases/latest/download}"
APP_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/chronos/app"

say() { printf '\033[1;36m[chronos]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[chronos] erro:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Linux" ] || die "este instalador é para Linux."
[ "$(uname -m)" = "x86_64" ] || die "apenas x86_64 é suportado por enquanto."
for cmd in curl tar openssl sha256sum base64; do
  command -v "$cmd" >/dev/null 2>&1 || die "comando necessário ausente: $cmd"
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say "Baixando manifesto da última versão…"
curl -fsSL "$BASE_URL/latest.json" -o "$WORK/latest.json"
curl -fsSL "$BASE_URL/latest.json.sig" -o "$WORK/latest.json.sig"

# Ed25519 SubjectPublicKeyInfo = fixed 12-byte DER prefix + raw 32-byte key.
{ printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'; printf '%s' "$PUBKEY_B64" | base64 -d; } > "$WORK/pub.der"
openssl pkey -pubin -inform DER -in "$WORK/pub.der" -out "$WORK/pub.pem" 2>/dev/null
base64 -d "$WORK/latest.json.sig" > "$WORK/sig.bin"
openssl pkeyutl -verify -pubin -inkey "$WORK/pub.pem" -rawin -in "$WORK/latest.json" -sigfile "$WORK/sig.bin" >/dev/null 2>&1 \
  || die "assinatura do manifesto inválida — instalação abortada."
say "Assinatura verificada."

json_field() { tr -d '\n' < "$WORK/latest.json" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/'; }
VERSION="$(json_field version)"
ARCHIVE="chronos-linux-x64-$VERSION.tar.gz"
EXPECTED_SHA="$(tr -d '\n' < "$WORK/latest.json" | grep -o "\"linux-x64\"[^}]*" | grep -o '"sha256"[[:space:]]*:[[:space:]]*"[0-9a-fA-F]*"' | sed 's/.*"\([0-9a-fA-F]*\)"$/\1/')"
[ -n "$VERSION" ] && [ -n "$EXPECTED_SHA" ] || die "manifesto incompleto."

say "Baixando Chronos $VERSION…"
curl -fL --progress-bar "$BASE_URL/$ARCHIVE" -o "$WORK/$ARCHIVE"
echo "$EXPECTED_SHA  $WORK/$ARCHIVE" | sha256sum -c --quiet - || die "SHA-256 do pacote não confere."

DEST="$APP_ROOT/versions/$VERSION"
rm -rf "$DEST.tmp"
mkdir -p "$DEST.tmp"
tar -xzf "$WORK/$ARCHIVE" -C "$DEST.tmp"
[ -x "$DEST.tmp/chronos_app" ] && [ -f "$DEST.tmp/chronos_proxy" ] || die "pacote incompleto."
rm -rf "$DEST"
mv "$DEST.tmp" "$DEST"
ln -sfn "versions/$VERSION" "$APP_ROOT/current.new"
mv -Tf "$APP_ROOT/current.new" "$APP_ROOT/current"
say "Instalado em $DEST"

# Runtime libraries check (no automatic package installation).
MISSING="$(ldd "$APP_ROOT/current/chronos_app" 2>/dev/null | awk '/not found/{print $1}' | sort -u || true)"
for tool in certutil systemctl; do command -v "$tool" >/dev/null 2>&1 || MISSING="$MISSING $tool"; done
if [ -n "${MISSING// /}" ]; then
  say "Dependências ausentes: $MISSING"
  if command -v pacman >/dev/null; then say "  Arch: sudo pacman -S --needed gtk3 nss"
  elif command -v apt-get >/dev/null; then say "  Debian/Ubuntu: sudo apt-get install libgtk-3-0 libnss3-tools"
  elif command -v dnf >/dev/null; then say "  Fedora: sudo dnf install gtk3 nss-tools"
  fi
fi

APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$APPS_DIR"
cat > "$APPS_DIR/chronos.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Chronos
Comment=Foco, limites de tempo e filtros de conteúdo
Exec=$APP_ROOT/current/chronos_app
Icon=preferences-system-time
Terminal=false
Categories=Utility;
DESKTOP
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true

say "Pronto! Abra o Chronos pelo menu de aplicativos (ou: $APP_ROOT/current/chronos_app)."
say "Na primeira abertura ele instala o serviço em segundo plano e as extensões dos navegadores."
