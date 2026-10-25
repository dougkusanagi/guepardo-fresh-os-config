#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
source "$ROOT_DIR/install-common/lib.sh"
TARGET_HOME="$sandbox/home with spaces"
DRY_RUN=false
mkdir -p "$TARGET_HOME/.config/flameshot"
printf '[General]\nshowDesktopNotification=true\nshowAbortNotification=true\nfilenamePattern=shot-%%Y\n' > "$TARGET_HOME/.config/flameshot/flameshot.ini"
configure_flameshot_notifications
configure_flameshot_notifications
python3 - "$TARGET_HOME" <<'PY'
import configparser, pathlib, sys
p=configparser.ConfigParser(interpolation=None)
p.read(pathlib.Path(sys.argv[1])/'.config/flameshot/flameshot.ini')
assert not p.getboolean('General','showDesktopNotification')
assert not p.getboolean('General','showAbortNotification')
assert p.get('General','filenamePattern') == 'shot-%Y'
PY
# Install the GUI with a mocked client and verify a single persistent autostart.
DISTRO=fedora
dnf_install() { :; }
run_quiet() { if [[ "$*" == *'dnf upgrade'* ]]; then return; fi; "$@"; }
onedrive() { echo 'onedrive v2.5.12'; }
install_release_appimage() { mkdir -p "$TARGET_HOME/.local/bin"; touch "$TARGET_HOME/.local/bin/$2"; }
install_onedrive_gui >/dev/null
install_onedrive_gui >/dev/null
grep -Fq "Exec=\"$TARGET_HOME/.local/bin/onedrive-gui-autosync\"" "$TARGET_HOME/.config/autostart/GuepardoOneDrive.desktop"
[[ "$(find "$TARGET_HOME/.config/autostart" -type f | wc -l)" == 1 ]]
grep -Fq autostart_enabled=False "$TARGET_HOME/.config/onedrive-gui/gui_settings"
# Each login enables sync for every profile, including ones added later.
printf '[a@x]\nauto_sync = False\n\n[b@x]\nauto_sync = True\n' > "$TARGET_HOME/.config/onedrive-gui/profiles"
printf '#!/bin/sh\necho launched "$@"\n' > "$TARGET_HOME/.local/bin/onedrive-gui"
chmod +x "$TARGET_HOME/.local/bin/onedrive-gui"
[[ "$(HOME="$TARGET_HOME" XDG_CONFIG_HOME= "$TARGET_HOME/.local/bin/onedrive-gui-autosync" x)" == 'launched x' ]]
[[ "$(grep -c '^auto_sync = True$' "$TARGET_HOME/.config/onedrive-gui/profiles")" == 2 ]]
# Cargo is installed and verified before any source build may begin.
(
  command_exists() { [[ "$1" == cargo || "$1" == rustc ]] && [[ -f "$sandbox/rust-installed" ]]; }
  install_remote_script() { printf '%s\n' "$*" > "$sandbox/rust-call"; touch "$sandbox/rust-installed"; }
  cargo() { [[ -f "$sandbox/rust-installed" ]]; }
  rustc() { [[ -f "$sandbox/rust-installed" ]]; }
  run_quiet() { "$@"; }
  ensure_cargo
  grep -Fq 'https://sh.rustup.rs sh -y --profile minimal' "$sandbox/rust-call"
)
# A failed Cargo bootstrap must not continue as though the compiler existed.
(
  command_exists() { return 1; }
  install_remote_script() { return 1; }
  if ensure_cargo; then echo 'Cargo failure swallowed' >&2; exit 1; fi
)
# The explicit upstream sync runs immediately after dotagents installation.
(
  dnf_install() { :; }
  install_source_checkout() { :; }
  run_quiet() { printf '%s\n' "$*" >> "$sandbox/agents-calls"; }
  install_dotagents
  [[ "$(sed -n '1p' "$sandbox/agents-calls")" == *'/dotagents/install.sh' ]]
  [[ "$(sed -n '2p' "$sandbox/agents-calls")" == *'/dotagents/bin/sync' ]]
)
# A missing document portal must not block Gear Lever's CLI or cause reinstallations.
(
  sudo() { :; }
  download_file() { printf '%s\n' "$*" >> "$sandbox/lm-downloads"; printf 'AppImage' > "$2"; }
  run_quiet() { "$@"; }
  flatpak() {
    if [[ "$1" == info ]]; then return 0; fi
    if [[ "$1" != run || "$2" != --no-documents-portal ]]; then
      echo "bwrap: Can't find source path /run/user/1000/doc/by-app/it.mijorus.gearlever" >&2
      return 1
    fi
    [[ "$3" == it.mijorus.gearlever ]] || return 1
    case "$4" in
      --list-installed) printf '%s\n' "${lm_installed:-}" ;;
      --integrate)
        [[ "$5" == --replace && "$6" == --yes && "$7" == "$TARGET_HOME/Downloads/LM_Studio.AppImage" && -x "$7" ]] || return 1
        printf '%s\n' "$*" >> "$sandbox/lm-integrations"
        return "${lm_integrate_status:-0}" ;;
      *) return 1 ;;
    esac
  }
  for lm_installed in 'LM-Studio [0.4.26+4]' 'LM Studio [0.4.26+4]'; do
    install_lm_studio >/dev/null
  done
  [[ ! -f "$sandbox/lm-downloads" && ! -f "$sandbox/lm-integrations" ]]
  lm_installed=''
  install_lm_studio > "$sandbox/lm-output"
  [[ -f "$sandbox/lm-downloads" && -f "$sandbox/lm-integrations" ]]
  grep -Fq 'LM Studio integrated' "$sandbox/lm-output"
  lm_integrate_status=1
  if install_lm_studio > "$sandbox/lm-output"; then echo 'Gear Lever failure swallowed' >&2; exit 1; fi
  ! grep -Fq 'LM Studio integrated' "$sandbox/lm-output"
)
# Failures inside an app stop that app without skipping the next independent app.
(
  set -Eeuo pipefail
  GUEPARDO_FAILURES_FILE="$sandbox/pending-apps"
  broken_app() { echo 'bwrap: missing document portal' >&2; false; touch "$sandbox/false-success"; }
  healthy_app() { touch "$sandbox/next-app-installed"; }
  run_app 'Broken Flatpak' broken_app
  run_app 'Healthy app' healthy_app
  [[ ! -f "$sandbox/false-success" && -f "$sandbox/next-app-installed" ]]
  grep -Fxq 'Broken Flatpak (exit 1)' "$GUEPARDO_FAILURES_FILE"
  [[ "$(wc -l < "$GUEPARDO_FAILURES_FILE")" == 1 ]]
)
# The actual desktop app lists continue after LM Studio fails on both distributions.
for distro in ubuntu fedora; do
  (
    GUEPARDO_FAILURES_FILE="$sandbox/$distro-pending"
    apt_install_optional() { :; }
    dnf_install_optional() { :; }
    flatpak_install_app() { :; }
    for installer in install_vscode_desktop install_google_chrome install_obsidian install_zapfast install_antigravity_desktop install_remote_script; do
      eval "$installer() { :; }"
    done
    install_lm_studio() { return 1; }
    install_opencode_desktop() { touch "$sandbox/$distro-opencode"; }
    source "$ROOT_DIR/install-$distro/desktop/10-apps.sh"
    [[ -f "$sandbox/$distro-opencode" ]]
    grep -Fq 'lm studio (exit 1)' "$GUEPARDO_FAILURES_FILE"
  )
done
echo 'Desktop application configuration checks passed'
