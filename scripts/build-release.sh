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
revision="$(git -C "$ROOT_DIR" rev-parse HEAD)"
# Pin this published entry point to the same immutable source and binary release.
sed "s/GUEPARDO_REF:-master/GUEPARDO_REF:-installer-$revision/" "$ROOT_DIR/install.sh" > "$DIST_DIR/install.sh"
chmod +x "$DIST_DIR/install.sh"
bash "$ROOT_DIR/scripts/source-digest.sh" "$ROOT_DIR" > "$DIST_DIR/SOURCE_SHA256"
(cd "$DIST_DIR" && sha256sum guepardo-linux-amd64 guepardo-linux-arm64 SOURCE_SHA256 install.sh > SHA256SUMS)
printf 'Release assets: %s\n' "$DIST_DIR"
