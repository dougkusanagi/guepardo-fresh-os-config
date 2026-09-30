#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export HOME="$sandbox/home" USER=guepardo-test
mkdir -p "$HOME" "$sandbox/bin"
source "$ROOT_DIR/install-common/lib.sh"
fail() { printf 'ERROR %s\n' "$*" >&2; exit 1; }

# The Bash fallback must offer the same WSL preset and preserve Linux choices.
picker_function="$(sed -n '/^select_profiles_interactive() {/,/^for arg in /p' "$ROOT_DIR/scripts/fallback.sh" | sed '$d')"
for keys in w $'\t'; do
  picker_output="$(printf '%s\n' "$keys" | env -u WSL_DISTRO_NAME -u WSL_INTEROP NO_COLOR=1 bash -c "$picker_function"$'\nselect_profiles_interactive; printf "RESULT:%s\n" "$profiles"')"
  [[ "$picker_output" == *'RESULT:cli,dev,web'* ]] || fail 'Bash WSL preset did not select terminal tools'
  [[ "$picker_output" == *'Tab / W trocar'* ]] || fail 'Bash picker does not explain environment switching'
done
picker_output="$(printf '4ww\n' | env -u WSL_DISTRO_NAME -u WSL_INTEROP bash -c "$picker_function"$'\nselect_profiles_interactive; printf "RESULT:%s\n" "$profiles"')"
[[ "$picker_output" == *'RESULT:desktop'* ]] || fail 'Returning from WSL lost the Linux selection'
picker_output="$(printf 'w2ww\n' | env -u WSL_DISTRO_NAME -u WSL_INTEROP bash -c "$picker_function"$'\nselect_profiles_interactive; printf "RESULT:%s\n" "$profiles"')"
[[ "$picker_output" == *'RESULT:cli,web'* ]] || fail 'Returning to WSL lost the customized selection'
picker_output="$(printf '\n' | WSL_DISTRO_NAME=Ubuntu bash -c "$picker_function"$'\nselect_profiles_interactive; printf "RESULT:%s\n" "$profiles"')"
[[ "$picker_output" == *'RESULT:cli,dev,web'* ]] || fail 'Bash picker did not detect WSL'
for hidden in Desktop Jogos Fontes 'Rede IPv4' '1–8'; do
  [[ "$picker_output" != *"$hidden"* ]] || fail "Bash WSL picker still shows $hidden"
done
picker_output="$(printf '584a\n' | WSL_DISTRO_NAME=Ubuntu bash -c "$picker_function"$'\nselect_profiles_interactive; printf "RESULT:%s\n" "$profiles"')"
[[ "$picker_output" == *'RESULT:cli,dev,web'* ]] || fail 'Bash WSL Todos selected unsupported modules'


# Failed transfers must preserve an existing download and remove partial data.
curl() {
  local destination
  while (($#)); do
    if [[ "$1" == -o ]]; then destination="$2"; shift; fi
    shift
  done
  printf 'partial' > "$destination"
  return 22
}
printf 'original' > "$sandbox/download"
if download_file https://example.test/app "$sandbox/download" >/dev/null 2>&1; then fail 'Failed download was accepted'; fi
[[ "$(cat "$sandbox/download")" == original ]] || fail 'Failed download overwrote the previous file'
[[ -z "$(find "$sandbox" -name '*.part.*')" ]] || fail 'Partial download was left behind'

# A failed download must not execute an empty/truncated installer or report OK.
run_quiet() { touch "$sandbox/executed"; }
if install_remote_script https://example.test/install.sh >/dev/null 2>&1; then fail 'Failed script download was accepted'; fi
[[ ! -e "$sandbox/executed" ]] || fail 'A failed script download was executed'

# Real Bash processes test errexit instead of inheriting suppression from if.
for jobs in 1 2; do
  if GUEPARDO_TEST_MARKER="$sandbox/masked-$jobs" GUEPARDO_TEST_ROOT="$ROOT_DIR" GUEPARDO_JOBS="$jobs" bash -c '
    set -Eeuo pipefail
    source "$GUEPARDO_TEST_ROOT/install-common/lib.sh"
    broken() { false; touch "$GUEPARDO_TEST_MARKER"; }
    run_independent broken
  '; then fail "Installer failure was masked with jobs=$jobs"; fi
  [[ ! -e "$sandbox/masked-$jobs" ]] || fail "Installer continued after failure with jobs=$jobs"
done

# Composer must reject a checksum mismatch before invoking PHP or sudo.
download_file() {
  case "$1" in
    *installer.sig) printf '%096d' 0 > "$2" ;;
    *) printf '<?php echo "wrong";' > "$2" ;;
  esac
}
command_exists() { return 1; }
if install_composer >/dev/null 2>&1; then fail 'Composer checksum mismatch was accepted'; fi
[[ ! -e "$sandbox/executed" ]] || fail 'Unverified Composer installer was executed'

# Package-manager failure must be returned even when called as an if condition.
source "$ROOT_DIR/install-ubuntu/lib.sh"
apt_package_installed() { return 1; }
run_quiet() { return 42; }
if apt_install missing >/dev/null 2>&1; then fail 'APT failure was reported as success'; fi
apt_package_available() { return 1; }
if apt_install_first_available missing >/dev/null 2>&1; then fail 'Missing required APT package was reported as success'; fi

# System Flatpak installation must also work on a server without a session bus.
flatpak() { return 1; }
ensure_dbus_session() { return 1; }
run_quiet() { printf '%s\n' "$*" > "$sandbox/flatpak-calls"; }
flatpak_install_app org.example.App >/dev/null
[[ "$(cat "$sandbox/flatpak-calls")" == 'sudo flatpak install -y --system flathub org.example.App' ]] || fail 'Headless Flatpak install was skipped'

# Each isolated profile prepares the package index and download dependencies.
fake_root="$sandbox/profiles"
mkdir -p "$fake_root/install-common" "$fake_root/install-ubuntu/terminal"
cat > "$fake_root/install-common/lib.sh" <<'SH'
cleanup() { :; }
configure_user_path() { :; }
warn() { :; }
REQUIRES_REBOOT=false
SH
cat > "$fake_root/install-ubuntu/lib.sh" <<'SH'
apt_update() { echo update >> "$GUEPARDO_TEST_CALLS"; }
apt_install() { echo "install $*" >> "$GUEPARDO_TEST_CALLS"; }
SH
printf 'echo dev >> "$GUEPARDO_TEST_CALLS"\n' > "$fake_root/install-ubuntu/terminal/05-dev-tools.sh"
GUEPARDO_ROOT="$fake_root" GUEPARDO_TEST_CALLS="$sandbox/profile-calls" bash "$ROOT_DIR/scripts/run-profile.sh" ubuntu dev
[[ "$(head -n 1 "$sandbox/profile-calls")" == update ]] || fail 'Dev profile does not refresh its index'
[[ "$(sed -n '2p' "$sandbox/profile-calls")" == *'curl ca-certificates tar unzip jq gpg xz-utils'* ]] || fail 'Dev profile lacks download prerequisites'

# Preflight must explain missing prerequisites, without attempting sudo/install.
for tool in bash tar sha256sum mktemp awk sort find uname; do
  ln -s "$(command -v "$tool")" "$sandbox/bin/$tool"
done
if PATH="$sandbox/bin" /bin/bash "$ROOT_DIR/scripts/preflight.sh" ubuntu fonts "$fake_root" > "$sandbox/preflight" 2>&1; then
  fail 'Preflight accepted missing curl'
fi
[[ "$(cat "$sandbox/preflight")" == *'Ferramenta necessária ausente: curl'* ]] || fail 'Preflight did not explain the missing prerequisite'

# Bash rejects invalid network values and themes before preflight or sudo.
for argument in --network-address=999.1.1.1/24 --network-address=192.168.1.2/33 --network-gateway=bad --network-dns=bad; do
  if bash "$ROOT_DIR/scripts/fallback.sh" --distro=ubuntu --profiles=network --yes \
    --network-interface=enp1s0 --network-address=192.168.1.2/24 --network-gateway=192.168.1.1 "$argument" > "$sandbox/invalid" 2>&1; then
    fail "Invalid network option was accepted: $argument"
  fi
  [[ "$(cat "$sandbox/invalid")" == *'valid IPv4'* ]] || fail "Network validation happened too late: $argument"
done
if bash "$ROOT_DIR/scripts/fallback.sh" --distro=ubuntu --profiles=desktop --theme=unknown --plan >/dev/null 2>&1; then fail 'Unknown theme was accepted'; fi

# Node downloads must be verified before extraction, execution or PATH changes.
source "$ROOT_DIR/install-common/lib.sh"
node() { printf 'v18.0.0\n'; }
download_file() {
  mkdir -p "$(dirname "$2")"
  if [[ "$1" == *SHASUMS256.txt ]]; then
    printf '%064d  node-v24.1.0-linux-x64.tar.xz\n' 0 > "$2"
  else
    printf 'corrupt' > "$2"
  fi
}
uname() { printf 'x86_64\n'; }
if install_node_lts >/dev/null 2>&1; then fail 'Node checksum mismatch was accepted'; fi
[[ ! -e "$HOME/.local/bin/node" ]] || fail 'Node was linked before checksum verification'

# Repeating the fonts profile repairs an interrupted copy and picks up updates.
font_root="$sandbox/fonts-test"
mkdir -p "$font_root/fonts" "$HOME/.local/share/fonts/guepardo-fresh-os-config"
printf 'new font' > "$font_root/fonts/My Font.ttf"
printf 'partial font' > "$HOME/.local/share/fonts/guepardo-fresh-os-config/My Font.ttf"
ROOT_DIR="$font_root"
fc-cache() { :; }
run_quiet() { "$@"; }
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install-common/desktop/05-fonts.sh" >/dev/null
[[ "$(cat "$HOME/.local/share/fonts/guepardo-fresh-os-config/My Font.ttf")" == 'new font' ]] || fail 'Interrupted font copy was not repaired'

# Verified Node installation repairs an incomplete directory and is reused.
node_archive="$sandbox/node-v24.1.0-linux-x64.tar.xz"
mkdir -p "$sandbox/node-release/bin" "$HOME/.local/share/guepardo/node-v24.1.0-linux-x64"
printf '#!/bin/sh\necho v24.1.0\n' > "$sandbox/node-release/bin/node"
printf '#!/bin/sh\necho 11.0.0\n' > "$sandbox/node-release/bin/npm"
cp "$sandbox/node-release/bin/npm" "$sandbox/node-release/bin/npx"
chmod +x "$sandbox/node-release/bin/"*
tar -cJf "$node_archive" -C "$sandbox" node-release
download_file() {
  printf 'download\n' >> "$sandbox/node-downloads"
  if [[ "$1" == *SHASUMS256.txt ]]; then
    printf '%s  node-v24.1.0-linux-x64.tar.xz\n' "$(sha256sum "$node_archive" | cut -d ' ' -f 1)" > "$2"
  else
    cp "$node_archive" "$2"
  fi
}
install_node_lts >/dev/null
unset -f node
[[ "$(node --version)" == v24.1.0 ]] || fail 'Node installation did not repair the incomplete directory'
[[ "$(npm --version)" == 11.0.0 ]] || fail 'npm is missing after Node installation'
install_node_lts >/dev/null
[[ "$(wc -l < "$sandbox/node-downloads")" == 2 ]] || fail 'Existing supported Node was downloaded again'

# Global npm tools belong to the user and are skipped on the next run.
npm() {
  printf '%s\n' "$*" >> "$sandbox/npm-calls"
  printf '#!/bin/sh\n' > "$HOME/.local/bin/guepardo-test-cli"
  chmod +x "$HOME/.local/bin/guepardo-test-cli"
}
install_npm_global_package guepardo-test-cli @example/cli >/dev/null
install_npm_global_package guepardo-test-cli @example/cli >/dev/null
[[ "$(cat "$sandbox/npm-calls")" == "install -g --prefix $HOME/.local @example/cli" ]] || fail 'Global npm install requires root or repeats installed tools'

# A database service failure must not be presented as a running database.
systemd_is_running() { return 0; }
run_quiet() { return 1; }
if enable_system_service mysql > "$sandbox/service-output" 2>&1; then fail 'Service startup failure was reported as success'; fi
[[ "$(cat "$sandbox/service-output")" != *'enabled and started'* ]] || fail 'Service failure printed a success message'
systemd_is_running() { return 1; }
enable_system_service mysql > "$sandbox/service-output" 2>&1
[[ "$(cat "$sandbox/service-output")" == *'systemd is not running'* ]] || fail 'Container service limitation was not explained'
printf 'Reliability checks passed\n'
