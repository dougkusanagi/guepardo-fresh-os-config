#!/usr/bin/env bash

section "Desktop Apps"

install_vscode_desktop
install_google_chrome
flatpak_install_app "io.podman_desktop.PodmanDesktop"
flatpak_install_app "it.mijorus.gearlever"
install_obsidian
flatpak_install_app "io.github.zen_browser.zen"
flatpak_install_app "io.missioncenter.MissionCenter"
flatpak_install_app "com.ktechpit.whatsie"
flatpak_install_app "com.github.dynobo.normcap"
install_lm_studio
install_opencode_desktop
install_antigravity_desktop

# Gaming extras (only in full mode)
if [[ "$INSTALL_MODE" == "full" ]]; then
  dnf_install_optional steam-devices joystick-support gamemode mangohud gamescope goverlay xone xpadneo gnome-shell-extension-dash-to-dock
  install_steam
  install_lutris
  install_qbittorrent
  install_discord
  flatpak_install_app "com.stremio.Stremio"
  flatpak_install_app "com.vysp3r.ProtonPlus"
  flatpak_install_app "com.heroicgameslauncher.hgl"
  flatpak_install_app "com.usebottles.bottles"
fi

if command -v zed >/dev/null 2>&1; then
  log "Zed is already available."
else
  run_quiet bash -lc 'curl -fsSL https://zed.dev/install.sh | bash'
  success "Zed installed"
fi
