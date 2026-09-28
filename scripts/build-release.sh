#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${1:-$ROOT_DIR/dist}"
mkdir -p "$DIST_DIR"
DIST_DIR="$(cd "$DIST_DIR" && pwd)"

for architecture in amd64 arm64; do
  printf 'Building Linux %s...\n' "$architecture"
  (cd "$ROOT_DIR" && CGO_ENABLED=0 GOOS=linux GOARCH="$architecture" go build -trimpath -ldflags='-s -w' -o "$DIST_DIR/guepardo-linux-$architecture" ./cmd/guepardo)
done
(cd "$DIST_DIR" && sha256sum guepardo-linux-amd64 guepardo-linux-arm64 > SHA256SUMS)
printf 'Release assets: %s\n' "$DIST_DIR"
