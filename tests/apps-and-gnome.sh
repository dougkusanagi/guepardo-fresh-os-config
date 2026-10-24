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
export XDG_DATA_DIRS="$sandbox/system"
install_web_app chatgpt ChatGPT https://chatgpt.com
grep -Fq 'Exec=google-chrome --app=https://chatgpt.com --class=chatgpt' "$TARGET_HOME/.local/share/applications/chatgpt.desktop"
# Existing non-Git directories must survive dotagents setup untouched.
mkdir -p "$sandbox/existing"
echo preserve > "$sandbox/existing/memory"
if install_source_checkout dougkusanagi/dotagents "$sandbox/existing" >/dev/null; then exit 1; fi
[[ "$(cat "$sandbox/existing/memory")" == preserve ]]
# Local notch sources take priority without pulling over uncommitted work.
# Old remote sources must not overwrite an installed notch.
(
  TARGET_HOME="$sandbox/notch-home"
  source_dir="$TARGET_HOME/dev/ai-quota-pulse-gnome"
  uuid=ai-usage@guepardosys
  mkdir -p "$source_dir/$uuid/ui"
  printf '{"shell-version":["50"]}' > "$source_dir/$uuid/metadata.json"
  touch "$source_dir/$uuid/ui/notch.js"
  unset GUEPARDO_AI_QUOTA_SOURCE
  apt_install() { :; }
  gnome-shell() { echo 'GNOME Shell 50.1'; }
  install_source_checkout() { echo pulled >> "$sandbox/notch-calls"; }
  run_quiet() { printf '%s\n' "$*" >> "$sandbox/notch-calls"; }
  persist_gnome_extension() { echo enabled >> "$sandbox/notch-calls"; }
  install_ai_quota_pulse
  grep -Fq "make -C $source_dir install EXTENSIONS_DIR=$TARGET_HOME/.local/share/gnome-shell/extensions" "$sandbox/notch-calls"
  ! grep -q pulled "$sandbox/notch-calls"
  [[ "$(tail -1 "$sandbox/notch-calls")" == enabled ]]
  export GUEPARDO_AI_QUOTA_SOURCE="$source_dir"
  install_ai_quota_pulse
  export GUEPARDO_AI_QUOTA_SOURCE="$sandbox/missing-source"
  : > "$sandbox/notch-calls"
  if install_ai_quota_pulse; then echo 'Missing explicit source accepted' >&2; exit 1; fi
  [[ ! -s "$sandbox/notch-calls" ]]
  unset GUEPARDO_AI_QUOTA_SOURCE
  rm "$source_dir/$uuid/ui/notch.js"
  if install_ai_quota_pulse; then echo 'Legacy source accepted' >&2; exit 1; fi
  [[ ! -s "$sandbox/notch-calls" ]]
  rm -rf "$source_dir"
  install_source_checkout() {
    mkdir -p "$2/$uuid/ui"
    printf '{"shell-version":["50"]}' > "$2/$uuid/metadata.json"
  }
  if install_ai_quota_pulse; then echo 'Legacy remote source accepted' >&2; exit 1; fi
  [[ ! -s "$sandbox/notch-calls" ]]
  touch "$TARGET_HOME/.local/share/guepardo/sources/ai-quota-pulse-gnome/$uuid/ui/notch.js"
  install_ai_quota_pulse
  [[ "$(tail -1 "$sandbox/notch-calls")" == enabled ]]
)
echo 'Application and GNOME persistence checks passed'
