#!/usr/bin/env bash

section "Games"
dnf_install_optional steam-devices joystick-support gamemode mangohud gamescope goverlay
install_steam
install_lutris
install_qbittorrent
install_discord
flatpak_install_app "com.stremio.Stremio"
flatpak_install_app "com.vysp3r.ProtonPlus"
flatpak_install_app "com.heroicgameslauncher.hgl"
flatpak_install_app "com.usebottles.bottles"
