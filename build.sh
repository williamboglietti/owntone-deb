#!/usr/bin/env bash
# Construit le .deb dans un conteneur Ubuntu 24.04 amd64 (même commande que la CI).
# Résultat : ./dist/owntone_<version>_amd64.deb et son .sha256.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=versions.env
. ./versions.env
mkdir -p dist
docker run --rm --platform linux/amd64 -v "$PWD:/src:ro" -v "$PWD/dist:/out" "$BUILD_IMAGE" \
  bash /src/build/build-deb.sh
