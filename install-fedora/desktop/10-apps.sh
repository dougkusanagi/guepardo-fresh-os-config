#!/usr/bin/env bash

section "Desktop Apps"

run_app "google chrome" install_google_chrome
run_app "io.podman_desktop.PodmanDesktop" flatpak_install_app "io.podman_desktop.PodmanDesktop"
run_app "it.mijorus.gearlever" flatpak_install_app "it.mijorus.gearlever"
run_app "md.obsidian.Obsidian" flatpak_install_app "md.obsidian.Obsidian"
run_app "io.github.zen_browser.zen" flatpak_install_app "io.github.zen_browser.zen"
run_app "io.missioncenter.MissionCenter" flatpak_install_app "io.missioncenter.MissionCenter"
run_app "zapfast" install_zapfast
run_app "com.brave.Browser" flatpak_install_app "com.brave.Browser"
run_app "com.obsproject.Studio" flatpak_install_app "com.obsproject.Studio"
run_app "org.videolan.VLC" flatpak_install_app "org.videolan.VLC"
run_app "com.github.dynobo.normcap" flatpak_install_app "com.github.dynobo.normcap"
run_app "lm studio" install_lm_studio
run_app "opencode desktop" install_opencode_desktop
run_app "antigravity desktop" install_antigravity_desktop

dnf_install_optional gnome-shell-extension-dash-to-dock

if command -v zed >/dev/null 2>&1; then
  log "Zed is already available."
else
  run_app "Zed" install_remote_script https://zed.dev/install.sh
fi
