#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
source "$ROOT_DIR/install-common/lib.sh"
source "$ROOT_DIR/install-common/gnome-extensions.sh"
TARGET_HOME="$sandbox/home"
mkdir -p "$TARGET_HOME"
DRY_RUN=true
DISTRO=ubuntu
for family in ubuntu fedora; do
  output="$(GUEPARDO_DRY_RUN=true bash "$ROOT_DIR/scripts/run-profile.sh" "$family" dev)"
  [[ "$output" == *'codex'* && "$output" == *'claude'* && "$output" == *dotagents* ]]
  output="$(GUEPARDO_DRY_RUN=true bash "$ROOT_DIR/scripts/run-profile.sh" "$family" desktop)"
  [[ "$output" == *'t3-code'* && "$output" == *'Sloth Note'* && "$output" == *'Claude'* && "$output" == *'ChatGPT'* ]]
done
DRY_RUN=false
GNOME_SETTINGS_MODIFIED=false
# State is stored in files because gsettings get runs in command substitutions.
printf "['unrelated@example', 'dock@example']" > "$sandbox/enabled-extensions"
printf "['dock@example', 'other-disabled@example']" > "$sandbox/disabled-extensions"
gsettings() {
  if [[ "$1" == get ]]; then cat "$sandbox/$3"; else printf '%s' "$4" > "$sandbox/$3"; fi
}
gnome-extensions() { return 1; } # First Wayland login cannot discover new extensions yet.
persist_gnome_extension dock@example >/dev/null
persist_gnome_extension dock@example >/dev/null
python3 - "$sandbox" <<'PY'
import ast, pathlib, sys
root = pathlib.Path(sys.argv[1])
assert ast.literal_eval((root/'enabled-extensions').read_text()) == ['unrelated@example', 'dock@example']
assert ast.literal_eval((root/'disabled-extensions').read_text()) == ['other-disabled@example']
assert (root/'disable-user-extensions').read_text() == 'false'
PY
# Configure the GNOME 50 workaround before extension activation, leaving older
# GNOME versions' overview settings and all versions' additional panels intact.
for version in 49 50; do
  (
    calls="$sandbox/multimonitor-$version"
    gnome-shell() { printf 'GNOME Shell %s.1\n' "$version"; }
    install_ego_extension() { :; }
    set_gsettings_if_different() {
      [[ "$GSETTINGS_SCHEMA_DIR" == "$TARGET_HOME/.local/share/gnome-shell/extensions/multi-monitors-bar@frederykabryan/schemas" ]]
      printf '%s %s\n' "$2" "$3" >> "$calls"
    }
    persist_gnome_extension() { echo enabled >> "$calls"; }
    configure_multimonitor_panels
    [[ "$(tail -1 "$calls")" == enabled ]]
    for key in show-panel show-date-time show-app-indicators; do grep -Fxq "$key true" "$calls"; done
    if ((version >= 50)); then
      [[ "$(head -1 "$calls")" == 'show-overview-on-extended-monitors false' ]]
    else
      ! grep -q show-overview-on-extended-monitors "$calls"
    fi
  )
done

# A rejected/incompatible download must never disable the working dock.
script="$ROOT_DIR/install-common/desktop/20-gnome-settings.sh"
python3 - "$script" > "$sandbox/dock.sh" <<'PY'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text()
a = s.index('if enable_gnome_extension dash-to-dock@')
b = s.index('\ninstall_ai_quota_pulse', a)
assert s.index('run_app "Multi Monitor Bar" configure_multimonitor_panels') < a
print(s[a:b])
PY
enable_gnome_extension() { return 1; }
disable_gnome_extension() { touch "$sandbox/disabled-working-dock"; }
if source "$sandbox/dock.sh" >/dev/null; then echo 'Failed dock reported success' >&2; exit 1; fi
[[ ! -e "$sandbox/disabled-working-dock" ]]
# Web launchers quote HOME paths containing spaces and use installed Chrome.
TARGET_HOME="$sandbox/home with spaces"
install_web_app chatgpt ChatGPT https://chatgpt.com
grep -Fq 'Exec=google-chrome --app=https://chatgpt.com' "$TARGET_HOME/.local/share/applications/chatgpt.desktop"
# Existing non-Git directories must survive dotagents setup untouched.
mkdir -p "$sandbox/existing"
echo preserve > "$sandbox/existing/memory"
if install_source_checkout dougkusanagi/dotagents "$sandbox/existing" >/dev/null; then exit 1; fi
[[ "$(cat "$sandbox/existing/memory")" == preserve ]]
echo 'Application and GNOME persistence checks passed'
