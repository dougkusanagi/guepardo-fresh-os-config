#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORY="dougkusanagi/guepardo-fresh-os-config"
REF="${GUEPARDO_REF:-stable}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR=""

cleanup_bootstrap() {
  if [[ -n "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup_bootstrap EXIT

# Process substitution supplies only install.sh, so fetch all supporting files
# from the same branch. The caller can choose another branch with GUEPARDO_REF.
if [[ ! -f "$ROOT_DIR/go.mod" || ! -d "$ROOT_DIR/install-common" ]]; then
  TMP_DIR="$(mktemp -d)"
  curl -fsSL "https://github.com/$REPOSITORY/archive/refs/heads/$REF.tar.gz" -o "$TMP_DIR/repo.tar.gz"
  tar -xzf "$TMP_DIR/repo.tar.gz" -C "$TMP_DIR"
  ROOT_DIR="$TMP_DIR/guepardo-fresh-os-config-$REF"
  [[ -f "$ROOT_DIR/go.mod" ]] || { echo "Could not download repository ref $REF" >&2; exit 1; }
fi

if [[ -n "${GUEPARDO_BIN:-}" ]]; then
  "$GUEPARDO_BIN" --root="$ROOT_DIR" "$@"
  exit $?
fi

if command -v go >/dev/null 2>&1; then
  (cd "$ROOT_DIR" && go run ./cmd/guepardo --root="$ROOT_DIR" "$@")
  exit $?
fi

case "$(uname -m)" in
  x86_64|amd64) architecture="amd64" ;;
  aarch64|arm64) architecture="arm64" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if [[ -z "$TMP_DIR" ]]; then
  TMP_DIR="$(mktemp -d)"
fi
release="https://github.com/$REPOSITORY/releases/latest/download"
asset="guepardo-linux-$architecture"
if curl -fsSL "$release/$asset" -o "$TMP_DIR/$asset" 2>/dev/null \
  && curl -fsSL "$release/SHA256SUMS" -o "$TMP_DIR/SHA256SUMS" 2>/dev/null; then
  (cd "$TMP_DIR" && grep -F "  $asset" SHA256SUMS | sha256sum -c -)
  chmod +x "$TMP_DIR/$asset"
  "$TMP_DIR/$asset" --root="$ROOT_DIR" "$@"
else
  echo "No Go release binary is available yet; using the Bash fallback." >&2
  bash "$ROOT_DIR/scripts/fallback.sh" "$@"
fi
