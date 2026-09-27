#!/usr/bin/env bash
# Behavioural tests for the fixes applied after a real Ubuntu 25.04 run.
# These complement the static assertions in dev-tools.sh by actually invoking
# the functions with stubbed external commands.

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORIGINAL_PATH="$PATH"

PASSED=0
FAILED=0
FAILURES=()

CURRENT_TEST=""

fail() {
  FAILED=$((FAILED + 1))
  FAILURES+=("$CURRENT_TEST: $*")
}

ok() {
  PASSED=$((PASSED + 1))
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="${3:-values differ}"

  if [[ "$expected" == "$actual" ]]; then
    ok
  else
    fail "$message | expected: '$expected' | actual: '$actual'"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-missing substring}"

  if [[ "$haystack" == *"$needle"* ]]; then
    ok
  else
    fail "$message | expected to contain: '$needle' | actual: '$haystack'"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-unexpected substring}"

  if [[ "$haystack" != *"$needle"* ]]; then
    ok
  else
    fail "$message | expected NOT to contain: '$needle' | actual: '$haystack'"
  fi
}

run_test() {
  local name="$1"
  shift
  CURRENT_TEST="$name"
  "$@"
}

# Builds a throwaway HOME plus a stub bin dir prepended to PATH.
new_sandbox() {
  SANDBOX="$(mktemp -d)"
  BIN_DIR="$SANDBOX/bin"
  mkdir -p "$BIN_DIR"
  TARGET_HOME="$SANDBOX/home"
  mkdir -p "$TARGET_HOME"
  CALLS="$SANDBOX/calls"
  : > "$CALLS"

  export PATH="$BIN_DIR:$ORIGINAL_PATH"
  export HOME="$TARGET_HOME"
  export TARGET_HOME
  export DRY_RUN=false
  export INSTALL_LOG="$SANDBOX/install.log"
  export LOG_DIR="$SANDBOX/logs"
  unset XDG_SESSION_TYPE WAYLAND_DISPLAY SUDO_ASKPASS 2>/dev/null || true
}

load_common() {
  # shellcheck source=/dev/null
  source "$ROOT_DIR/install-common/lib.sh"
}

load_ubuntu() {
  load_common
  # shellcheck source=/dev/null
  source "$ROOT_DIR/install-ubuntu/lib.sh"
}

# Writes a stub executable that appends its arguments to $CALLS.
stub_recording() {
  local name="$1"
  local exit_code="${2:-0}"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s $*" >> "%s"\nexit %s\n' \
    "$name" "$CALLS" "$exit_code" > "$BIN_DIR/$name"
  chmod +x "$BIN_DIR/$name"
}

stub_exit() {
  local name="$1"
  local exit_code="${2:-0}"
  printf '#!/usr/bin/env bash\nexit %s\n' "$exit_code" > "$BIN_DIR/$name"
  chmod +x "$BIN_DIR/$name"
}

stub_output() {
  local name="$1"
  local output="$2"
  printf '#!/usr/bin/env bash\nprintf "%%s" %q\n' "$output" > "$BIN_DIR/$name"
  chmod +x "$BIN_DIR/$name"
}

# Like stub_output, but the stub body can reference $CALLS at runtime.
stub_script() {
  local name="$1"
  local body="$2"
  printf '#!/usr/bin/env bash\nCALLS=%q\n%s\n' "$CALLS" "$body" > "$BIN_DIR/$name"
  chmod +x "$BIN_DIR/$name"
}

cleanup_sandbox() {
  export PATH="$ORIGINAL_PATH"
  [[ -n "${SANDBOX:-}" ]] && rm -rf "$SANDBOX"
  SANDBOX=""
}

########################################
# session_is_wayland
########################################

test_session_is_wayland() {
  new_sandbox
  load_common

  XDG_SESSION_TYPE=wayland
  WAYLAND_DISPLAY=wayland-0
  session_is_wayland && ok || fail "XDG_SESSION_TYPE=wayland was not detected"

  XDG_SESSION_TYPE=x11
  WAYLAND_DISPLAY=
  session_is_wayland && fail "X11 session was misdetected as Wayland" || ok

  unset XDG_SESSION_TYPE WAYLAND_DISPLAY
  session_is_wayland && fail "unset session was misdetected as Wayland" || ok

  cleanup_sandbox
}

########################################
# github_latest_asset_url
########################################

test_github_asset_url_rejects_api_error_payload() {
  new_sandbox
  load_common

  # The API answers HTTP 200 with an error object for a bad token or an
  # exhausted rate limit, which must not be parsed as a release.
  stub_exit gh 127
  stub_output curl '{"message":"API rate limit exceeded"}'

  if github_latest_asset_url "owner/repo" '.*\.deb$' >/dev/null 2>&1; then
    fail "an API error payload was accepted as a valid release"
  else
    ok
  fi

  cleanup_sandbox
}

test_github_asset_url_selects_matching_asset() {
  new_sandbox
  load_common

  stub_exit gh 127
  stub_output curl '{"assets":[{"name":"obsidian_1.9.10_arm64.deb","browser_download_url":"https://example.test/arm64.deb"},{"name":"obsidian_1.9.10_amd64.deb","browser_download_url":"https://example.test/amd64.deb"}]}'

  local url
  url="$(github_latest_asset_url "obsidianmd/obsidian-releases" 'obsidian_.*_amd64\.deb$')"
  assert_equals "https://example.test/amd64.deb" "$url" "the wrong asset was selected"

  cleanup_sandbox
}

test_github_api_get_prefers_authenticated_gh() {
  new_sandbox
  load_common

  # An authenticated gh session must win over anonymous curl.
  cat > "$BIN_DIR/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "auth" ]]; then
  exit 0
fi
printf '%s' '{"tag_name":"v1.2.3","assets":[{"name":"gh.deb","browser_download_url":"https://example.test/from-gh.deb"}]}'
STUB
  chmod +x "$BIN_DIR/gh"
  stub_output curl '{"assets":[{"name":"curl.deb","browser_download_url":"https://example.test/from-curl.deb"}]}'

  local response
  response="$(github_api_get "repos/owner/repo/releases/latest")"
  assert_contains "$response" "from-gh.deb" "the authenticated gh API was not preferred"
  assert_not_contains "$response" "from-curl.deb" "the anonymous curl fallback was used anyway"

  cleanup_sandbox
}

test_github_api_get_falls_back_when_gh_is_unauthenticated() {
  new_sandbox
  load_common

  cat > "$BIN_DIR/gh" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == "auth" ]] && exit 1
exit 1
STUB
  chmod +x "$BIN_DIR/gh"
  stub_output curl '{"assets":[{"name":"curl.deb","browser_download_url":"https://example.test/from-curl.deb"}]}'

  local response
  response="$(github_api_get "repos/owner/repo/releases/latest")"
  assert_contains "$response" "from-curl.deb" "the curl fallback was not used when gh is unusable"

  cleanup_sandbox
}

test_github_api_get_falls_back_when_gh_returns_nothing() {
  new_sandbox
  load_common

  cat > "$BIN_DIR/gh" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == "auth" ]] && exit 0
exit 0
STUB
  chmod +x "$BIN_DIR/gh"
  stub_output curl '{"assets":[{"name":"curl.deb","browser_download_url":"https://example.test/from-curl.deb"}]}'

  local response
  response="$(github_api_get "repos/owner/repo/releases/latest")"
  assert_contains "$response" "from-curl.deb" "an empty gh response was not retried over curl"

  cleanup_sandbox
}

test_github_api_get_honours_github_token() {
  new_sandbox
  load_common

  stub_exit gh 127
  stub_script curl 'for arg in "$@"; do
  case "$arg" in
    Authorization:*) printf "%s\n" "$arg" >> "$CALLS" ;;
  esac
done
printf "%s" "{\"assets\":[]}"'

  GITHUB_TOKEN="secret-token"
  export GITHUB_TOKEN
  github_api_get "repos/owner/repo/releases/latest" >/dev/null

  assert_contains "$(cat "$CALLS")" "Authorization: Bearer secret-token" "GITHUB_TOKEN was not sent"

  cleanup_sandbox
}

test_github_asset_url_fails_on_network_error() {
  new_sandbox
  load_common

  stub_exit gh 127
  stub_exit curl 7

  if github_latest_asset_url "owner/repo" '.*' >/dev/null 2>&1; then
    fail "a network failure was reported as success"
  else
    ok
  fi

  cleanup_sandbox
}

########################################
# ensure_log_dir_writable
########################################

test_ensure_log_dir_keeps_writable_dir() {
  new_sandbox
  load_common

  local good="$SANDBOX/good-logs"
  LOG_DIR="$good"
  ensure_log_dir_writable "$good" >/dev/null
  assert_equals "$good" "$LOG_DIR" "a writable log dir was replaced"

  cleanup_sandbox
}

test_ensure_log_dir_falls_back_when_unwritable() {
  new_sandbox
  load_common

  local blocked="$SANDBOX/blocked"
  mkdir -p "$blocked"
  chmod 000 "$blocked"

  if [[ -w "$blocked" ]]; then
    # Running as root bypasses the permission bits, so there is nothing to test.
    ok
    ok
  else
    LOG_DIR="$blocked"
    ensure_log_dir_writable "$blocked" >/dev/null 2>&1 || true
    assert_not_contains "${LOG_DIR:-}" "$blocked" "the unwritable log dir was kept"
    if [[ -n "${LOG_DIR:-}" && -w "$LOG_DIR" ]]; then
      ok
    else
      fail "the fallback log dir is not writable"
    fi
  fi

  chmod 755 "$blocked"
  cleanup_sandbox
}

########################################
# install_user_autostart_entry / FLAMESHOT_ENV
########################################

test_flameshot_env_forces_xwayland() {
  new_sandbox
  load_common

  assert_equals "QT_QPA_PLATFORM=xcb" "$FLAMESHOT_ENV" "FLAMESHOT_ENV must pin Qt to XWayland"

  cleanup_sandbox
}

test_autostart_entry_contents() {
  new_sandbox
  load_common

  install_user_autostart_entry "flameshot" "env $FLAMESHOT_ENV flameshot" "flameshot" "Flameshot screenshot tool" >/dev/null

  local entry="$TARGET_HOME/.config/autostart/flameshot.desktop"
  if [[ ! -f "$entry" ]]; then
    fail "the autostart entry was not created at $entry"
  else
    ok
    local contents
    contents="$(cat "$entry")"
    assert_contains "$contents" "Exec=env $FLAMESHOT_ENV flameshot" "the Exec line is missing the XWayland environment"
    assert_contains "$contents" "X-GNOME-Autostart-enabled=true" "the entry is not enabled for autostart"
    assert_contains "$contents" "Type=Application" "the entry type is wrong"
  fi

  cleanup_sandbox
}

########################################
# install_steam
########################################

test_steam_detects_binary_on_path() {
  new_sandbox
  load_ubuntu

  stub_exit steam 0
  steam_command_exists && ok || fail "a PATH-visible steam was not detected"

  rm -f "$BIN_DIR/steam"
  if [[ -x /usr/games/steam ]]; then
    # This host has the out-of-PATH binary, so detection must still succeed.
    steam_command_exists && ok || fail "/usr/games/steam was not detected"
  else
    steam_command_exists && fail "steam was reported as present with no binary at all" || ok
  fi

  cleanup_sandbox
}

test_steam_installs_available_package_name() {
  new_sandbox
  load_ubuntu

  # Force the install path regardless of what this host already has.
  steam_command_exists() { return 1; }
  stub_recording sudo 0
  stub_recording add-apt-repository 0
  apt_update() { :; }
  apt_install() { printf 'apt_install %s\n' "$1" >> "$CALLS"; }
  # Ubuntu 25.04 dropped the transitional "steam" package.
  apt_package_available() { [[ "$1" == "steam-installer" ]]; }

  install_steam >/dev/null 2>&1

  local calls
  calls="$(cat "$CALLS")"
  assert_contains "$calls" "apt_install steam-installer" "steam-installer was not installed"
  assert_not_contains "$calls" "apt_install steam
" "the removed steam package was requested"
  assert_contains "$calls" "add-apt-repository -y multiverse" "multiverse was not enabled"
  assert_equals "1" "$(printf '%s\n' "$calls" | grep -c '^apt_install ')" "more than one package was installed"

  cleanup_sandbox
}

test_steam_enables_i386_architecture() {
  new_sandbox
  load_ubuntu

  steam_command_exists() { return 1; }
  stub_recording sudo 0
  stub_recording add-apt-repository 0
  # Report that no foreign architecture is registered yet.
  dpkg() { [[ "$*" == *"--print-foreign-architectures"* ]] && exit 0; return 0; }
  apt_update() { :; }
  apt_install() { printf 'apt_install %s\n' "$1" >> "$CALLS"; }
  apt_package_available() { [[ "$1" == "steam-installer" ]]; }

  install_steam >/dev/null 2>&1

  assert_contains "$(cat "$CALLS")" "--add-architecture i386" "i386 was not enabled before installing Steam"

  cleanup_sandbox
}

test_steam_skips_i386_when_present() {
  new_sandbox
  load_ubuntu

  steam_command_exists() { return 1; }
  stub_recording sudo 0
  stub_recording add-apt-repository 0
  dpkg() { [[ "$*" == *"--print-foreign-architectures"* ]] && { printf 'i386\n'; return 0; }; return 0; }
  apt_update() { :; }
  apt_install() { printf 'apt_install %s\n' "$1" >> "$CALLS"; }
  apt_package_available() { [[ "$1" == "steam-installer" ]]; }

  install_steam >/dev/null 2>&1

  assert_not_contains "$(cat "$CALLS")" "--add-architecture" "i386 was re-added even though it was already enabled"

  cleanup_sandbox
}

########################################
# install_obsidian
########################################

test_obsidian_prefers_deb_when_resolvable() {
  new_sandbox
  load_ubuntu

  command_exists() { return 1; }
  github_latest_asset_url() { printf 'https://example.test/obsidian_amd64.deb\n'; }
  download_file() { printf 'download %s\n' "$1" >> "$CALLS"; return 0; }
  run_quiet() { printf 'run %s\n' "$*" >> "$CALLS"; return 0; }
  flatpak_install_app() { printf 'flatpak %s\n' "$1" >> "$CALLS"; }

  install_obsidian >/dev/null 2>&1

  local calls
  calls="$(cat "$CALLS")"
  assert_contains "$calls" "download https://example.test/obsidian_amd64.deb" "the .deb was not downloaded"
  assert_not_contains "$calls" "flatpak" "Flatpak was used even though the .deb resolved"

  cleanup_sandbox
}

test_obsidian_falls_back_when_url_unresolvable() {
  new_sandbox
  load_ubuntu

  command_exists() { return 1; }
  github_latest_asset_url() { return 1; }
  flatpak_install_app() { printf 'flatpak %s\n' "$1" >> "$CALLS"; }

  install_obsidian >/dev/null 2>&1

  assert_contains "$(cat "$CALLS")" "flatpak md.obsidian.Obsidian" "Obsidian did not fall back to Flatpak"

  cleanup_sandbox
}

test_obsidian_falls_back_when_deb_install_fails() {
  new_sandbox
  load_ubuntu

  command_exists() { return 1; }
  github_latest_asset_url() { printf 'https://example.test/obsidian_amd64.deb\n'; }
  download_file() { return 0; }
  run_quiet() { return 1; }
  flatpak_install_app() { printf 'flatpak %s\n' "$1" >> "$CALLS"; }

  install_obsidian >/dev/null 2>&1

  assert_contains "$(cat "$CALLS")" "flatpak md.obsidian.Obsidian" "a failed .deb install did not fall back to Flatpak"

  cleanup_sandbox
}

test_obsidian_falls_back_when_download_fails() {
  new_sandbox
  load_ubuntu

  command_exists() { return 1; }
  github_latest_asset_url() { printf 'https://example.test/obsidian_amd64.deb\n'; }
  download_file() { return 1; }
  flatpak_install_app() { printf 'flatpak %s\n' "$1" >> "$CALLS"; }

  install_obsidian >/dev/null 2>&1

  assert_contains "$(cat "$CALLS")" "flatpak md.obsidian.Obsidian" "a failed download did not fall back to Flatpak"

  cleanup_sandbox
}

########################################
# require_sudo with SUDO_ASKPASS
########################################

test_require_sudo_uses_askpass() {
  new_sandbox
  load_common

  stub_recording sudo 0
  stub_exit sudo-askpass 0

  # A non-interactive session can only authenticate through askpass.
  SUDO_ASKPASS="$BIN_DIR/askpass-helper"
  export SUDO_ASKPASS
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SUDO_ASKPASS"
  chmod +x "$SUDO_ASKPASS"

  # sudo must still require a password for the non-interactive probe, so the
  # stub fails on `-n true` and only accepts the askpass path.
  stub_script sudo 'printf "sudo %s\n" "$*" >> "$CALLS"
if [[ "$*" == *"-n true"* ]]; then
  exit 1
fi
if [[ "$*" == *"-A -v"* ]]; then
  exit 0
fi
exit 1'

  require_sudo && ok || fail "require_sudo rejected a working askpass helper"
  assert_contains "$(cat "$CALLS")" "sudo -A -v" "sudo -A -v was never attempted"

  cleanup_sandbox
}

test_require_sudo_skipped_in_dry_run() {
  new_sandbox
  load_common

  DRY_RUN=true
  stub_recording sudo 1
  require_sudo && ok || fail "require_sudo failed during a dry run"
  assert_equals "" "$(cat "$CALLS")" "sudo was invoked during a dry run"

  cleanup_sandbox
}

########################################
# install_antigravity_desktop
########################################

test_antigravity_handles_private_bucket() {
  new_sandbox
  load_common

  # The public bucket now answers 401 to anonymous listing requests.
  stub_exit curl 22

  local output
  output="$(install_antigravity_desktop 2>&1)"
  assert_contains "$output" "no longer public" "the 401 probe did not report the expected warning"
  assert_not_contains "$output" "curl:" "curl leaked its raw error to the user"

  cleanup_sandbox
}

test_antigravity_extract_dir_matches_arch() {
  new_sandbox
  load_common

  # The tarball unpacks into a directory named after the architecture; using a
  # hardcoded name breaks every non-x86_64 host.
  local source_body
  source_body="$(cat "$ROOT_DIR/install-common/lib.sh")"
  assert_contains "$source_body" 'extract_dir_name="Antigravity-x64"' "the x86_64 extract dir is missing"
  assert_contains "$source_body" 'extract_dir_name="Antigravity-arm"' "the arm64 extract dir is missing"
  assert_contains "$source_body" 'mv "$extract_dir/$extract_dir_name" "$app_dir"' "the extract dir is still hardcoded"
  assert_not_contains "$source_body" 'mv "$extract_dir/Antigravity-x64"' "a hardcoded x86_64 path remains"

  cleanup_sandbox
}

########################################
# Runner
########################################

run_test "session_is_wayland detects Wayland and X11" test_session_is_wayland
run_test "github_latest_asset_url rejects API error payloads" test_github_asset_url_rejects_api_error_payload
run_test "github_latest_asset_url selects the matching asset" test_github_asset_url_selects_matching_asset
run_test "github_api_get prefers the authenticated gh CLI" test_github_api_get_prefers_authenticated_gh
run_test "github_api_get falls back when gh is unauthenticated" test_github_api_get_falls_back_when_gh_is_unauthenticated
run_test "github_api_get falls back when gh returns nothing" test_github_api_get_falls_back_when_gh_returns_nothing
run_test "github_api_get honours GITHUB_TOKEN" test_github_api_get_honours_github_token
run_test "github_latest_asset_url fails on network errors" test_github_asset_url_fails_on_network_error
run_test "ensure_log_dir_writable keeps a writable dir" test_ensure_log_dir_keeps_writable_dir
run_test "ensure_log_dir_writable falls back from an unwritable dir" test_ensure_log_dir_falls_back_when_unwritable
run_test "FLAMESHOT_ENV pins Qt to XWayland" test_flameshot_env_forces_xwayland
run_test "install_user_autostart_entry writes a working entry" test_autostart_entry_contents
run_test "install_steam detects a steam binary outside PATH" test_steam_detects_binary_on_path
run_test "install_steam installs steam-installer when steam is gone" test_steam_installs_available_package_name
run_test "install_steam enables the i386 architecture" test_steam_enables_i386_architecture
run_test "install_steam skips i386 when already enabled" test_steam_skips_i386_when_present
run_test "install_obsidian prefers the .deb when resolvable" test_obsidian_prefers_deb_when_resolvable
run_test "install_obsidian falls back when the URL is unresolvable" test_obsidian_falls_back_when_url_unresolvable
run_test "install_obsidian falls back when the .deb install fails" test_obsidian_falls_back_when_deb_install_fails
run_test "install_obsidian falls back when the download fails" test_obsidian_falls_back_when_download_fails
run_test "require_sudo authenticates through SUDO_ASKPASS" test_require_sudo_uses_askpass
run_test "require_sudo is skipped during a dry run" test_require_sudo_skipped_in_dry_run
run_test "install_antigravity_desktop handles the private bucket" test_antigravity_handles_private_bucket
run_test "install_antigravity_desktop unpacks per architecture" test_antigravity_extract_dir_matches_arch

if (( FAILED > 0 )); then
  printf "Installation fix checks FAILED (%d passed, %d failed)\n" "$PASSED" "$FAILED" >&2
  for failure in "${FAILURES[@]}"; do
    printf '  - %s\n' "$failure" >&2
  done
  exit 1
fi

printf 'Installation fix checks passed (%d assertions)\n' "$PASSED"
