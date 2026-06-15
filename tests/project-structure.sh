#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf "ERROR %s\n" "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "Expected file: ${1#$ROOT_DIR/}"
}

assert_dir() {
  [[ -d "$1" ]] || fail "Expected directory: ${1#$ROOT_DIR/}"
}

assert_contains() {
  local file="$1"
  local expected="$2"

  grep -Fq "$expected" "$file" || fail "Expected ${file#$ROOT_DIR/} to contain: $expected"
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"

  if grep -Fq "$unexpected" "$file"; then
    fail "Did not expect ${file#$ROOT_DIR/} to contain: $unexpected"
  fi
}

assert_file "$ROOT_DIR/install.sh"
assert_file "$ROOT_DIR/test.sh"
assert_dir "$ROOT_DIR/install-ubuntu"
assert_dir "$ROOT_DIR/install-fedora"
assert_dir "$ROOT_DIR/install-common"
assert_file "$ROOT_DIR/install-common/lib.sh"
assert_file "$ROOT_DIR/install-common/terminal.sh"
assert_file "$ROOT_DIR/install-common/desktop.sh"
assert_file "$ROOT_DIR/install-ubuntu/lib.sh"
assert_file "$ROOT_DIR/install-fedora/lib.sh"

assert_file "$ROOT_DIR/.gitignore"
assert_dir "$ROOT_DIR/logs"
assert_file "$ROOT_DIR/logs/.gitkeep"
assert_contains "$ROOT_DIR/.gitignore" "/*.log"
assert_contains "$ROOT_DIR/.gitignore" "/logs/*"
assert_contains "$ROOT_DIR/.gitignore" "!/logs/.gitkeep"
assert_contains "$ROOT_DIR/install.sh" 'LOG_DIR="$ROOT_DIR/logs"'
assert_contains "$ROOT_DIR/install.sh" "show_install_intro()"
assert_contains "$ROOT_DIR/install.sh" "Fresh Config Installer"
assert_contains "$ROOT_DIR/install.sh" "COLOR_CYAN"
assert_contains "$ROOT_DIR/install.sh" "wsl"
assert_contains "$ROOT_DIR/install-common/lib.sh" "desktop_install_enabled()"

if find "$ROOT_DIR" -maxdepth 1 -type f -name 'install-*.log' | grep -q .; then
  fail "Runtime install logs must live under logs/, not the repository root."
fi

assert_contains "$ROOT_DIR/test.sh" 'INSTALL_DIR="install-ubuntu"'
assert_contains "$ROOT_DIR/test.sh" 'INSTALLER_ARGS=(--distro=fedora)'
assert_not_contains "$ROOT_DIR/test.sh" 'install-fedora.sh'

printf "Project structure checks passed\n"
