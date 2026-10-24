#!/usr/bin/env bash

section "Games"
apt_install_optional steam-devices joystick jstest-gtk gamemode mangohud gamescope goverlay
run_app "steam" install_steam
install_gpu_drivers
run_app "lutris" install_lutris
run_app "qbittorrent" install_qbittorrent
run_app "discord" install_discord
run_app "com.stremio.Stremio" flatpak_install_app "com.stremio.Stremio"
run_app "com.vysp3r.ProtonPlus" flatpak_install_app "com.vysp3r.ProtonPlus"
run_app "com.heroicgameslauncher.hgl" flatpak_install_app "com.heroicgameslauncher.hgl"
run_app "com.usebottles.bottles" flatpak_install_app "com.usebottles.bottles"
