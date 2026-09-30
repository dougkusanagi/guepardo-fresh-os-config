#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORY="dougkusanagi/guepardo-fresh-os-config"
REF="${GUEPARDO_REF:-master}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR=""

cleanup_bootstrap() {
  if [[ -n "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup_bootstrap EXIT

bootstrap_download() {
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 600 "$1" -o "$2"
}

for prerequisite in curl tar sha256sum mktemp; do
  command -v "$prerequisite" >/dev/null 2>&1 || {
    echo "Ferramenta necessária ausente: $prerequisite. Instale-a e execute novamente." >&2
    exit 1
  }
done
[[ "$(uname -s)" == Linux ]] || { echo 'No Windows use install.ps1; este instalador requer Linux.' >&2; exit 1; }

# Process substitution supplies only install.sh, so fetch all supporting files
# from the same branch. The caller can choose another branch with GUEPARDO_REF.
if [[ ! -f "$ROOT_DIR/go.mod" || ! -d "$ROOT_DIR/install-common" ]]; then
  TMP_DIR="$(mktemp -d)"
  echo "Baixando configuração: $REF..." >&2
  bootstrap_download "https://codeload.github.com/$REPOSITORY/tar.gz/$REF" "$TMP_DIR/repo.tar.gz"
  mkdir -p "$TMP_DIR/repository"
  tar -xzf "$TMP_DIR/repo.tar.gz" --strip-components=1 -C "$TMP_DIR/repository"
  ROOT_DIR="$TMP_DIR/repository"
  [[ -f "$ROOT_DIR/go.mod" ]] || { echo "Could not download repository ref $REF" >&2; exit 1; }
fi

if [[ -n "${GUEPARDO_BIN:-}" ]]; then
  "$GUEPARDO_BIN" --root="$ROOT_DIR" "$@"
  exit $?
fi

go_version="$(go version 2>/dev/null || true)"
if [[ "$go_version" =~ go1\.([0-9]+) ]] && (( BASH_REMATCH[1] >= 22 )); then
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
if bootstrap_download "$release/SOURCE_SHA256" "$TMP_DIR/SOURCE_SHA256" 2>/dev/null \
  && bootstrap_download "$release/SHA256SUMS" "$TMP_DIR/SHA256SUMS" 2>/dev/null; then
  source_checksum="$(awk '$2 == "SOURCE_SHA256" {print; exit}' "$TMP_DIR/SHA256SUMS")"
  [[ -n "$source_checksum" ]] || { echo 'Release sem checksum de origem; download rejeitado.' >&2; exit 1; }
  (cd "$TMP_DIR" && printf '%s\n' "$source_checksum" | sha256sum -c -)
  expected_source="$(bash "$ROOT_DIR/scripts/source-digest.sh" "$ROOT_DIR")"
  if [[ "$(cat "$TMP_DIR/SOURCE_SHA256")" == "$expected_source" ]]; then
    if bootstrap_download "$release/$asset" "$TMP_DIR/$asset" 2>/dev/null; then
      asset_checksum="$(awk -v asset="$asset" '$2 == asset {print; exit}' "$TMP_DIR/SHA256SUMS")"
      [[ -n "$asset_checksum" ]] || { echo 'Release sem checksum do binário; download rejeitado.' >&2; exit 1; }
      (cd "$TMP_DIR" && printf '%s\n' "$asset_checksum" | sha256sum -c -)
      chmod +x "$TMP_DIR/$asset"
      "$TMP_DIR/$asset" --root="$ROOT_DIR" "$@"
      exit $?
    fi
  fi
fi
echo "Sem binário Go compatível com esta configuração; usando o executor Bash." >&2
bash "$ROOT_DIR/scripts/fallback.sh" "$@"
