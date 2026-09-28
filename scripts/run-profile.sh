#!/usr/bin/env bash
set -Eeuo pipefail

DISTRO="${1:?missing distro}"
PROFILE="${2:?missing profile}"
ROOT_DIR="${GUEPARDO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
INSTALL_ROOT="$ROOT_DIR/install-$DISTRO"
DRY_RUN="${GUEPARDO_DRY_RUN:-false}"
INSTALL_LOG=""
SELECTED_THEME="${SELECTED_THEME:-}"
export DRY_RUN SELECTED_THEME

[[ -f "$INSTALL_ROOT/lib.sh" ]] || { echo "Unsupported distro: $DISTRO" >&2; exit 1; }

# The Go process owns authentication and refreshes it throughout the run.
# Put a non-interactive sudo shim on PATH so even downloaded sh installers
# cannot open a second password prompt. Bash functions cover nested bash too.
sudo_shim_dir=""
if [[ "${GUEPARDO_SUDO_NONINTERACTIVE:-false}" == "1" ]]; then
  sudo_binary="$(command -v sudo || true)"
  if [[ -n "$sudo_binary" ]]; then
    sudo_shim_dir="$(mktemp -d)"
    cat > "$sudo_shim_dir/sudo" <<EOF
#!/bin/sh
exec "$sudo_binary" -n "\$@"
EOF
    chmod 0700 "$sudo_shim_dir/sudo"
    PATH="$sudo_shim_dir:$PATH"
    export PATH
  fi
  sudo() { command sudo "$@"; }
  export -f sudo
fi

# shellcheck source=/dev/null
source "$ROOT_DIR/install-common/lib.sh"
# shellcheck source=/dev/null
source "$INSTALL_ROOT/lib.sh"
finish_runner() {
  cleanup
  if [[ -n "$sudo_shim_dir" ]]; then
    rm -rf "$sudo_shim_dir"
  fi
}
trap finish_runner EXIT

case "$PROFILE" in
  cli)
    source "$INSTALL_ROOT/terminal/00-cli.sh"
    ;;
  dev)
    source "$INSTALL_ROOT/terminal/05-dev-tools.sh"
    ;;
  web)
    source "$INSTALL_ROOT/terminal/10-web-stack.sh"
    ;;
  desktop)
    detect_desktop
    if [[ "$RUNNING_GNOME" == "true" ]]; then
      configure_gnome_for_install
    fi
    source "$INSTALL_ROOT/desktop/00-core.sh"
    source "$INSTALL_ROOT/desktop/05-warp.sh"
    source "$INSTALL_ROOT/desktop/10-apps.sh"
    if [[ "$RUNNING_GNOME" == "true" ]]; then
      source "$ROOT_DIR/install-common/desktop/20-gnome-settings.sh"
      if [[ -n "$SELECTED_THEME" ]]; then
        apply_selected_theme "$SELECTED_THEME"
      fi
    elif [[ -n "$SELECTED_THEME" ]]; then
      warn "GNOME is not active; skipping theme $SELECTED_THEME"
    fi
    ;;
  games)
    source "$INSTALL_ROOT/games/00-core.sh"
    source "$INSTALL_ROOT/games/10-apps.sh"
    ;;
  fonts)
    source "$ROOT_DIR/install-common/desktop/05-fonts.sh"
    ;;
  network)
    source "$INSTALL_ROOT/network.sh"
    ;;
  *)
    echo "Unknown profile: $PROFILE" >&2
    exit 1
    ;;
esac
