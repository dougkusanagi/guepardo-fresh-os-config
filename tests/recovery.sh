#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export GUEPARDO_STATE_DIR="$sandbox/state" GUEPARDO_CACHE_DIR="$sandbox/cache" GUEPARDO_RESUME=true
export GUEPARDO_FAILURES_FILE="$sandbox/failures"
source "$ROOT_DIR/install-common/lib.sh"
export DRY_RUN=false
calls="$sandbox/calls"
ensure_cargo() { echo called >> "$calls"; touch "$sandbox/cargo"; }
guepardo_verify_task() { [[ -f "$sandbox/cargo" ]]; }
run_app Rust ensure_cargo
run_app Rust ensure_cargo
[[ "$(wc -l < "$calls")" == 1 ]]
rm "$sandbox/cargo"
run_app Rust ensure_cargo
[[ "$(wc -l < "$calls")" == 2 ]]
ensure_cargo() { return 1; }
rm "$sandbox/cargo"
run_app Rust ensure_cargo
grep -q 'Rust (exit 1)' "$GUEPARDO_FAILURES_FILE"
grep -q failed "$GUEPARDO_STATE_DIR/"*.status
# A zero exit code is insufficient when the expected tool was not installed.
ensure_cargo() { :; }
run_app Rust ensure_cargo
[[ "$(wc -l < "$GUEPARDO_FAILURES_FILE")" == 2 ]]
# Cache behavior with fake network: corrupt content and checksum failures.
counter="$sandbox/network"
curl() {
  local output
  while (($#)); do if [[ "$1" == -o ]]; then output="$2"; shift; fi; shift; done
  echo call >> "$counter"; printf 'expected' > "$output"
}
checksum="$(printf expected | sha256sum | cut -d ' ' -f 1)"
download_file https://example.test/app "$sandbox/out" "$checksum"
download_file https://example.test/app "$sandbox/out" "$checksum"
[[ "$(wc -l < "$counter")" == 1 ]]
key="$(printf '%s|%s' https://example.test/app "$checksum" | sha256sum | cut -d ' ' -f 1)"
printf corrupt > "$GUEPARDO_CACHE_DIR/$key"
download_file https://example.test/app "$sandbox/out" "$checksum"
[[ "$(wc -l < "$counter")" == 2 && "$(cat "$sandbox/out")" == expected ]]
mkdir "$GUEPARDO_CACHE_DIR/$key.lock"; printf 99999999 > "$GUEPARDO_CACHE_DIR/$key.lock/pid"
download_file https://example.test/app "$sandbox/out" "$checksum"
curl() { local output; while (($#)); do if [[ "$1" == -o ]]; then output="$2"; shift; fi; shift; done; printf bad > "$output"; }
sleep() { :; }
if download_file https://example.test/wrong "$sandbox/out" "$checksum"; then echo 'Bad checksum accepted' >&2; exit 1; fi
[[ "$(cat "$sandbox/out")" == expected ]]
printf 'Recovery/cache checks passed\n'
