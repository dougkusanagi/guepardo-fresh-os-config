#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf "ERROR %s\n" "$*" >&2
  exit 1
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

COMMON_LIB="$ROOT_DIR/install-common/lib.sh"

for distro in ubuntu fedora; do
  base_script="$ROOT_DIR/install-$distro/terminal/00-base.sh"
  web_stack_script="$ROOT_DIR/install-$distro/terminal/10-web-stack.sh"
  desktop_script="$ROOT_DIR/install-$distro/desktop/10-apps.sh"
  lib_script="$ROOT_DIR/install-$distro/lib.sh"

  assert_contains "$base_script" "fzf"
  assert_contains "$base_script" "ripgrep"
  assert_contains "$base_script" "nodejs"
  assert_contains "$base_script" "npm"
  assert_contains "$base_script" "desktop_install_enabled"
  assert_contains "$base_script" "install_lazygit"
  assert_contains "$base_script" "install_yazi"
  assert_contains "$base_script" "install_npm_global_package opencode opencode-ai"
  assert_contains "$base_script" "install_npm_global_package codex @openai/codex"
  assert_contains "$base_script" "podman-docker"
  assert_not_contains "$base_script" "alias docker='podman'"
  assert_contains "$base_script" "docker-compose='podman-compose'"
  assert_contains "$base_script" "pwfeedback"
  assert_not_contains "$base_script" "install_atuin"
  assert_contains "$base_script" 'comment_line_if_present '\''eval "$(atuin init bash)"'\'''
  assert_not_contains "$base_script" 'add_line_if_missing '\''eval "$(atuin init bash)"'\'''
  assert_contains "$base_script" "configure_static_ipv4_network"
  assert_contains "$base_script" "comment_line_if_present"
  assert_contains "$base_script" "alias ls='eza'"
  assert_contains "$base_script" "alias ll='ls -alF'"
  assert_contains "$base_script" "alias la='ls -A'"
  assert_contains "$base_script" "alias l='ls -CF'"
  assert_contains "$base_script" "alias l='ls -l'"

  assert_contains "$desktop_script" "install_vscode_desktop"
  assert_contains "$desktop_script" "install_google_chrome"
  assert_contains "$desktop_script" "install_opencode_desktop"
  assert_contains "$desktop_script" "gnome-shell-extension-dash-to-dock"
  assert_contains "$desktop_script" '"$INSTALL_MODE" == "games"'
  assert_contains "$desktop_script" "install_antigravity_desktop"
  assert_contains "$desktop_script" "install_steam"
  assert_contains "$desktop_script" "install_lutris"
  assert_contains "$desktop_script" "install_qbittorrent"
  assert_contains "$desktop_script" "install_discord"
  case "$distro" in
    ubuntu) assert_contains "$desktop_script" "install_obsidian" ;;
    fedora) assert_contains "$desktop_script" "md.obsidian.Obsidian" ;;
  esac
  assert_contains "$desktop_script" 'flatpak_install_app "com.github.dynobo.normcap"'
  assert_not_contains "$desktop_script" 'flatpak_install_app "com.visualstudio.code"'
  assert_not_contains "$desktop_script" 'flatpak_install_app "com.google.Chrome"'
  assert_contains "$desktop_script" 'flatpak_install_app "io.podman_desktop.PodmanDesktop"'
  assert_contains "$desktop_script" 'flatpak_install_app "it.mijorus.gearlever"'
  assert_contains "$desktop_script" "install_lm_studio"
  assert_not_contains "$desktop_script" 'flatpak_install_app "ai.lmstudio.LMStudio"'
  assert_contains "$desktop_script" 'flatpak_install_app "io.github.zen_browser.zen"'
  assert_contains "$desktop_script" 'flatpak_install_app "io.missioncenter.MissionCenter"'
  assert_contains "$desktop_script" 'flatpak_install_app "com.ktechpit.whatsie"'
  assert_not_contains "$desktop_script" 'flatpak_install_app "com.valvesoftware.Steam"'
  assert_not_contains "$desktop_script" 'flatpak_install_app "net.lutris.Lutris"'
  assert_not_contains "$desktop_script" 'flatpak_install_app "com.discordapp.Discord"'
  assert_contains "$desktop_script" 'flatpak_install_app "com.vysp3r.ProtonPlus"'
  assert_contains "$desktop_script" 'flatpak_install_app "com.heroicgameslauncher.hgl"'
  assert_contains "$desktop_script" 'flatpak_install_app "com.usebottles.bottles"'

  assert_contains "$web_stack_script" "php-opcache"
  assert_contains "$web_stack_script" 'export PATH="$HOME/.config/composer/vendor/bin:$HOME/.bun/bin:$PATH"'

  assert_contains "$lib_script" "install_steam()"
  assert_contains "$lib_script" "install_lutris()"
  assert_contains "$lib_script" "install_qbittorrent()"
  assert_contains "$lib_script" "install_discord()"
  assert_contains "$lib_script" "install_obsidian()"
  assert_contains "$lib_script" "install_vscode_desktop()"
  assert_contains "$lib_script" "https://packages.microsoft.com/keys/microsoft.asc"
  assert_contains "$lib_script" "code"
  assert_contains "$lib_script" "install_google_chrome()"
  assert_contains "$lib_script" "google-chrome-stable"
  assert_contains "$lib_script" "install_opencode_desktop()"
  assert_not_contains "$lib_script" "install_atuin()"

  assert_not_contains "$COMMON_LIB" "install_atuin()"
  assert_contains "$COMMON_LIB" "github_latest_asset_url"
  assert_contains "$COMMON_LIB" "comment_line_if_present()"
  assert_contains "$COMMON_LIB" "install_npm_global_package()"
  assert_contains "$COMMON_LIB" "install_lazygit()"
  assert_contains "$COMMON_LIB" "install_yazi()"
  assert_contains "$COMMON_LIB" "install_lm_studio()"
  assert_contains "$COMMON_LIB" "https://lmstudio.ai/download/latest/linux/x64?format=AppImage"
  assert_contains "$COMMON_LIB" "flatpak run it.mijorus.gearlever --integrate --replace --yes"
  assert_contains "$COMMON_LIB" 'package_file="$TARGET_HOME/Downloads/LM_Studio.AppImage"'
  assert_contains "$COMMON_LIB" "sudo rm -rf /opt/lm-studio"
  assert_not_contains "$COMMON_LIB" 'LM_Studio.AppImage" "$appimage"'
  assert_contains "$COMMON_LIB" "install_antigravity_desktop()"
  assert_contains "$COMMON_LIB" "storage.googleapis.com/storage/v1/b/antigravity-public/o"
  assert_contains "$COMMON_LIB" "Antigravity.tar.gz"
  assert_contains "$COMMON_LIB" "configure_static_ipv4_network()"
  assert_contains "$COMMON_LIB" 'STATIC_NETWORK_ADDRESS="${STATIC_NETWORK_ADDRESS:-192.168.1.77/24}"'
  assert_contains "$COMMON_LIB" 'STATIC_NETWORK_GATEWAY="${STATIC_NETWORK_GATEWAY:-192.168.1.1}"'
  assert_contains "$COMMON_LIB" 'STATIC_NETWORK_DNS="${STATIC_NETWORK_DNS:-1.1.1.1}"'
done

assert_contains "$ROOT_DIR/install-ubuntu/lib.sh" "apt_install_optional()"
assert_contains "$ROOT_DIR/install-ubuntu/lib.sh" "apt_keyring_exists()"
assert_contains "$ROOT_DIR/install-ubuntu/lib.sh" "install_apt_keyring_file()"
assert_contains "$ROOT_DIR/install-ubuntu/lib.sh" "install_apt_dearmored_keyring()"
assert_contains "$ROOT_DIR/install-ubuntu/terminal/00-base.sh" "install_apt_keyring_file"
assert_contains "$ROOT_DIR/install-ubuntu/terminal/00-base.sh" "install_apt_dearmored_keyring"
assert_not_contains "$ROOT_DIR/install-ubuntu/terminal/00-base.sh" "sudo gpg --dearmor -o /etc/apt/keyrings"
assert_contains "$ROOT_DIR/install-ubuntu/desktop/00-core.sh" "add-apt-repository -y multiverse"
assert_contains "$ROOT_DIR/install-ubuntu/desktop/10-apps.sh" "apt_install_optional steam-devices joystick jstest-gtk gamemode mangohud goverlay"
assert_not_contains "$ROOT_DIR/install-ubuntu/desktop/10-apps.sh" "gamescope"
assert_contains "$ROOT_DIR/install-fedora/desktop/10-apps.sh" "dnf_install_optional steam-devices joystick-support gamemode mangohud gamescope goverlay"
assert_contains "$ROOT_DIR/install.sh" "wsl (non-desktop apps only)"
assert_contains "$ROOT_DIR/install.sh" "full|basic|games|wsl"
assert_contains "$ROOT_DIR/install-ubuntu/terminal/00-base.sh" "if desktop_install_enabled; then"
assert_contains "$ROOT_DIR/install-fedora/terminal/00-base.sh" "if desktop_install_enabled; then"
assert_contains "$ROOT_DIR/install-common/desktop/20-gnome-settings.sh" "set_gsettings_if_different org.gnome.settings-daemon.plugins.media-keys screenshot"
assert_contains "$ROOT_DIR/install-common/desktop/20-gnome-settings.sh" "Flameshot configured as the primary Print Screen tool"
assert_contains "$ROOT_DIR/install-common/desktop/20-gnome-settings.sh" "dash-to-dock show-apps-at-top true"
assert_contains "$ROOT_DIR/install-common/desktop/20-gnome-settings.sh" "dash-to-dock dash-max-icon-size 28"
assert_contains "$ROOT_DIR/install-common/desktop/20-gnome-settings.sh" "dash-to-dock dock-fixed true"
assert_contains "$ROOT_DIR/install-common/desktop/20-gnome-settings.sh" "disable_gnome_extension ubuntu-dock@ubuntu.com"
assert_contains "$ROOT_DIR/install-ubuntu/lib.sh" "apt_install_first_available()"
assert_contains "$ROOT_DIR/install-ubuntu/terminal/10-web-stack.sh" "PHP_OPCACHE_PACKAGES=(php-opcache)"
assert_contains "$ROOT_DIR/install-ubuntu/terminal/10-web-stack.sh" "Zend OPcache"
assert_contains "$ROOT_DIR/install-ubuntu/terminal/10-web-stack.sh" "apt-cache search --names-only"
assert_contains "$ROOT_DIR/install-ubuntu/terminal/10-web-stack.sh" 'apt_install_first_available "${PHP_OPCACHE_PACKAGES[@]}"'
assert_contains "$ROOT_DIR/install-ubuntu/lib.sh" "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
assert_contains "$ROOT_DIR/install-fedora/lib.sh" "https://dl.google.com/linux/chrome/rpm/stable/x86_64"
assert_contains "$ROOT_DIR/install-ubuntu/lib.sh" "https://opencode.ai/download/stable/linux-x64-deb"
assert_contains "$ROOT_DIR/install-fedora/lib.sh" "https://opencode.ai/download/stable/linux-x64-rpm"

# --- Regression guards for the Ubuntu 25.04 (resolute) installation run ---

# The `steam` package was replaced by `steam-installer`, and steam-libs-i386
# needs the i386 foreign architecture enabled first.
assert_contains "$ROOT_DIR/install-ubuntu/lib.sh" "apt_install_first_available steam steam-installer"
# `apt_install steam` on its own line is the call that broke the 25.04 run.
assert_not_contains "$ROOT_DIR/install-ubuntu/lib.sh" "$(printf '  apt_install steam\n')"
assert_contains "$ROOT_DIR/install-ubuntu/lib.sh" "dpkg --add-architecture i386"
assert_contains "$ROOT_DIR/install-ubuntu/lib.sh" "steam_command_exists()"
assert_contains "$ROOT_DIR/install-ubuntu/lib.sh" "/usr/games/steam"

# Obsidian must degrade to Flatpak instead of aborting the whole run.
assert_contains "$ROOT_DIR/install-ubuntu/lib.sh" "flatpak_install_app \"md.obsidian.Obsidian\""

# require_sudo has to accept a non-interactive SUDO_ASKPASS session.
assert_contains "$COMMON_LIB" "sudo_supports_passwordless()"
assert_contains "$COMMON_LIB" "sudo -A -v"
assert_contains "$COMMON_LIB" "SUDO_ASKPASS"

# The GitHub helper must be authenticated and must reject error payloads.
assert_contains "$COMMON_LIB" "github_api_get()"
assert_contains "$COMMON_LIB" "gh api"
assert_contains "$COMMON_LIB" 'has("message")'
assert_contains "$COMMON_LIB" "GITHUB_TOKEN"

# A root-owned log directory must not abort the installer.
assert_contains "$COMMON_LIB" "ensure_log_dir_writable()"
assert_contains "$ROOT_DIR/install.sh" "ensure_log_dir_writable"

# Flameshot only spans every monitor through XWayland.
assert_contains "$COMMON_LIB" 'FLAMESHOT_ENV="QT_QPA_PLATFORM=xcb"'
assert_contains "$COMMON_LIB" "install_user_autostart_entry()"
assert_contains "$COMMON_LIB" "session_is_wayland()"
assert_contains "$ROOT_DIR/install-common/desktop/20-gnome-settings.sh" "env \$FLAMESHOT_ENV flameshot gui"
assert_contains "$ROOT_DIR/install-common/desktop/20-gnome-settings.sh" "install_user_autostart_entry"
# GNOME 45+ owns Print itself, so the shell binding has to be cleared.
assert_contains "$ROOT_DIR/install-common/desktop/20-gnome-settings.sh" "org.gnome.shell.keybindings show-screenshot-ui"
# Meta.restart is a no-op on Wayland, so the restart must be skipped there.
assert_contains "$ROOT_DIR/install-common/desktop/20-gnome-settings.sh" "GNOME Shell cannot be restarted in place on Wayland"

# Antigravity: the bucket listing is no longer public and the extract dir is
# named after the architecture.
assert_contains "$COMMON_LIB" 'extract_dir_name="Antigravity-x64"'
assert_contains "$COMMON_LIB" 'extract_dir_name="Antigravity-arm"'
assert_not_contains "$COMMON_LIB" 'mv "$extract_dir/Antigravity-x64"'
assert_contains "$COMMON_LIB" "no longer public"

printf "Developer tool checks passed\n"
