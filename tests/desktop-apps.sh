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
grep -Fq "Exec=\"$TARGET_HOME/.local/bin/onedrive-gui\"" "$TARGET_HOME/.config/autostart/OneDriveGUI.desktop"
[[ "$(find "$TARGET_HOME/.config/autostart" -type f | wc -l)" == 1 ]]
grep -Fq autostart_enabled=True "$TARGET_HOME/.config/onedrive-gui/gui_settings"
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
echo 'Desktop application configuration checks passed'
