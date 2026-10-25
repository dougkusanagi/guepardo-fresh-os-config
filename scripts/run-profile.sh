#!/usr/bin/env bash
set -Eeuo pipefail

DISTRO="${1:?missing distro}"
PROFILE="${2:?missing profile}"
export GUEPARDO_CURRENT_PROFILE="$PROFILE"
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

# Every profile must work on a clean machine without selecting CLI first.
PROFILE_RECIPE="${GUEPARDO_PROFILE_RECIPE:-}"
if [[ "$DISTRO" == "ubuntu" ]]; then
  apt_update
  apt_install curl ca-certificates tar unzip jq gpg xz-utils
else
  dnf_update
  dnf_install curl ca-certificates tar unzip jq gnupg2 xz
fi
if [[ -z "$PROFILE_RECIPE" ]] && command_exists jq; then
  PROFILE_RECIPE="$(jq -er --arg id "$PROFILE" '.profiles[] | select(.id == $id) | .linuxRecipe // empty' "$ROOT_DIR/catalog/apps.json")"
fi
# Dry-run can precede jq installation; its compatibility mapping is validated in tests.
if [[ -z "$PROFILE_RECIPE" ]]; then
  case "$PROFILE" in
    cli) PROFILE_RECIPE=terminal/00-cli.sh ;;
    dev) PROFILE_RECIPE=terminal/05-dev-tools.sh ;;
    web) PROFILE_RECIPE=terminal/10-web-stack.sh ;;
    desktop) PROFILE_RECIPE=desktop/10-apps.sh ;;
    games) PROFILE_RECIPE=games/10-apps.sh ;;
    network) PROFILE_RECIPE=network.sh ;;
    *) echo "Unknown profile: $PROFILE" >&2; exit 1 ;;
  esac
fi
[[ "$PROFILE_RECIPE" != /* && "$PROFILE_RECIPE" != *..* && "$PROFILE_RECIPE" != *\\* && -f "$INSTALL_ROOT/$PROFILE_RECIPE" ]] || { echo 'Invalid catalog recipe' >&2; exit 1; }

case "$PROFILE" in
  cli)
    configure_user_path
    source "$INSTALL_ROOT/$PROFILE_RECIPE"
    ;;
  dev)
    configure_user_path
    source "$INSTALL_ROOT/$PROFILE_RECIPE"
    ;;
  web)
    source "$INSTALL_ROOT/$PROFILE_RECIPE"
    ;;
  desktop)
    detect_desktop
    if [[ "$RUNNING_GNOME" == "true" ]]; then
      configure_gnome_for_install
    fi
    source "$INSTALL_ROOT/desktop/00-core.sh"
    run_app "Warp" source "$INSTALL_ROOT/desktop/05-warp.sh"
    source "$INSTALL_ROOT/$PROFILE_RECIPE"
    run_app "AI desktop apps" install_ai_desktop_apps
    if [[ "$DISTRO" == ubuntu ]]; then apt_install python3; else dnf_install python3; fi
    configure_flameshot_notifications
    if [[ "$RUNNING_GNOME" == "true" ]]; then
      if [[ "$DISTRO" == ubuntu ]]; then apt_install python3; else dnf_install python3; fi
      source "$ROOT_DIR/install-common/desktop/20-gnome-settings.sh"
      if [[ -n "$SELECTED_THEME" ]]; then
        apply_selected_theme "$SELECTED_THEME"
      fi
    elif [[ -n "$SELECTED_THEME" ]]; then
      warn "GNOME is not active; skipping theme $SELECTED_THEME"
    fi
    run_app "dotagents" install_dotagents
    ;;
  games)
    source "$INSTALL_ROOT/games/00-core.sh"
    source "$INSTALL_ROOT/$PROFILE_RECIPE"
    ;;
  network)
    source "$INSTALL_ROOT/$PROFILE_RECIPE"
    ;;
  *)
    echo "Unknown profile: $PROFILE" >&2
    exit 1
    ;;
esac

if [[ "$PROFILE" == "cli" || "$PROFILE" == "dev" || "$PROFILE" == "web" ]]; then
  warn "Open a new terminal to load the updated PATH and aliases."
fi
if [[ "$REQUIRES_REBOOT" == "true" ]]; then
  warn "Reboot before using Samba/Nautilus Share; log out and back in for desktop changes."
fi
