#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/install-common/apps.sh"
TARGET_HOME="/unused-test-home"
log() { :; }
error() { printf '%s\n' "$*" >&2; }
installed=false
downloads=0
checks=0
command_exists() { [[ "$installed" == true ]]; }
install_remote_script() { downloads=$((downloads + 1)); installed=true; }
run_quiet() { checks=$((checks + 1)); }
DRY_RUN=true
ensure_cargo
[[ "$downloads" == 0 && "$checks" == 0 ]]
DRY_RUN=false
ensure_cargo
[[ "$installed" == true && "$downloads" == 1 && "$checks" == 2 ]]
ensure_cargo
[[ "$downloads" == 1 && "$checks" == 4 ]]
installed=false
install_remote_script() { return 1; }
if ensure_cargo; then echo 'Failed Rust download accepted' >&2; exit 1; fi
install_remote_script() { :; }
if ensure_cargo 2>/dev/null; then echo 'Missing Rust binaries accepted' >&2; exit 1; fi
printf 'Rust toolchain checks passed\n'
