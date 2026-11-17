#!/usr/bin/env bash
# Publishes a Chronos release: bumps pubspec.yaml, commits, tags vX.Y.Z and pushes.
# GitHub Actions (.github/workflows/release.yml) then builds, signs and publishes it.
#   scripts/release.sh 1.2.0
set -euo pipefail

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "uso: $0 X.Y.Z" >&2; exit 2; }
cd "$(git rev-parse --show-toplevel)"

[ -z "$(git status --porcelain)" ] || { echo "Há alterações não commitadas. Faça commit antes de lançar." >&2; exit 1; }
git rev-parse "v$VERSION" >/dev/null 2>&1 && { echo "A tag v$VERSION já existe." >&2; exit 1; }

BUILD="$(grep -E '^version:' pubspec.yaml | sed -E 's/.*\+([0-9]+).*/\1/')"
[[ "$BUILD" =~ ^[0-9]+$ ]] || BUILD=0
sed -i -E "s/^version: .*/version: $VERSION+$((BUILD + 1))/" pubspec.yaml

git add pubspec.yaml
git commit -m "Release v$VERSION"
git tag -a "v$VERSION" -m "Chronos v$VERSION"
echo "Pronto para publicar v$VERSION. Enviando branch e tag…"
git push origin HEAD
git push origin "v$VERSION"
echo "Acompanhe o build em: https://github.com/$(git remote get-url origin | sed -E 's#.*github.com[:/](.*)\.git#\1#')/actions"
