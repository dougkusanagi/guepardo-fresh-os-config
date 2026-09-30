#!/usr/bin/env bash

section "Desktop Apps"

apt_install_optional gnome-shell-extension-dash-to-dock gnome-shell-extension-ubuntu-dock

install_vscode_desktop
install_google_chrome
install_obsidian
flatpak_install_app "io.podman_desktop.PodmanDesktop"
flatpak_install_app "it.mijorus.gearlever"
flatpak_install_app "io.github.zen_browser.zen"
flatpak_install_app "io.missioncenter.MissionCenter"
flatpak_install_app "com.ktechpit.whatsie"
flatpak_install_app "com.github.dynobo.normcap"
install_lm_studio
install_opencode_desktop
install_antigravity_desktop

if command -v zed >/dev/null 2>&1; then
  log "Zed is already available."
else
  install_remote_script https://zed.dev/install.sh
  success "Zed installed"
fi
