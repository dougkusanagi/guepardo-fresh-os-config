#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export TARGET_HOME="$sandbox/home"
export XDG_DATA_HOME="$TARGET_HOME/.local/share"
uuid='topbar-all-monitors@fa8i.github.io'
mkdir -p "$TARGET_HOME"
DRY_RUN=true
log() { printf '%s\n' "$*" >> "$sandbox/log"; }
section() { :; }
warn() { log "$*"; }
success() { log "$*"; }
command_exists() { command -v "$1" >/dev/null; }
gnome-shell() { echo "GNOME Shell ${test_version:-50}.1"; }
gnome-extensions() {
  echo "$*" >> "$sandbox/extension-calls"
  if [[ "$1" == install ]]; then
    [[ "${install_failure:-false}" != true ]] || return 1
    mkdir -p "$XDG_DATA_HOME/gnome-shell/extensions/$uuid"
    printf '{"uuid":"%s","shell-version":["50"]}' "$uuid" > "$XDG_DATA_HOME/gnome-shell/extensions/$uuid/metadata.json"
  else
    return 1 # A new extension is not detected in the running session yet.
  fi
}
download_file() {
  echo "$1" >> "$sandbox/downloads"
  [[ "${download_failure:-false}" != true ]] || return 1
  if [[ "$1" == *extension-info* ]]; then
    printf '{"uuid":"%s","shell_version_map":{"50":{"pk":75595}},"download_url":"/download-extension/%s.shell-extension.zip?version_tag=75595"}' "$uuid" "$uuid" > "$2"
  else
    : > "$2"
  fi
}
printf "['ding@rastersoft.com']" > "$sandbox/enabled-extensions"
printf "['%s', 'other@example.com']" "$uuid" > "$sandbox/disabled-extensions"
gsettings() {
  if [[ "$1" == get ]]; then
    cat "$sandbox/$3"
  else
    echo "$3" >> "$sandbox/settings-writes"
    printf '%s' "$4" > "$sandbox/$3"
  fi
}
source "$ROOT_DIR/install-common/desktop/25-multi-monitor-panel.sh"
[[ ! -e "$sandbox/downloads" ]] || { echo 'Dry run downloaded an extension'; exit 1; }
[[ ! -e "$sandbox/settings-writes" ]] || { echo 'Dry run changed settings'; exit 1; }
DRY_RUN=false
configure_multi_monitor_panel
[[ "$(wc -l < "$sandbox/downloads")" == 2 ]]
[[ "$(cat "$sandbox/enabled-extensions")" == "['ding@rastersoft.com', '$uuid']" ]]
[[ "$(cat "$sandbox/disabled-extensions")" == "['other@example.com']" ]]
configure_multi_monitor_panel
[[ "$(wc -l < "$sandbox/downloads")" == 2 ]]
[[ "$(wc -l < "$sandbox/settings-writes")" == 2 ]]
test_version=49
configure_multi_monitor_panel
[[ "$(wc -l < "$sandbox/downloads")" == 3 ]]
[[ "$(wc -l < "$sandbox/settings-writes")" == 2 ]]
test_version=50
rm -rf "$XDG_DATA_HOME/gnome-shell/extensions/$uuid"
download_failure=true
if configure_multi_monitor_panel; then echo 'Download failure was hidden'; exit 1; fi
[[ "$(wc -l < "$sandbox/settings-writes")" == 2 ]]
download_failure=false
install_failure=true
if configure_multi_monitor_panel; then echo 'Installation failure was hidden'; exit 1; fi
[[ "$(wc -l < "$sandbox/settings-writes")" == 2 ]]
echo 'Multi-monitor panel tests passed'
