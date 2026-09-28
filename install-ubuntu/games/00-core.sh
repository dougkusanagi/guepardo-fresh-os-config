#!/usr/bin/env bash

section "Gaming prerequisites"
if [[ "$DRY_RUN" != "true" ]]; then
  sudo rm -f /etc/apt/sources.list.d/lutris-team-ubuntu-lutris-*.list /etc/apt/sources.list.d/lutris-team-ubuntu-lutris-*.sources 2>/dev/null || true
fi
apt_update
apt_install curl ca-certificates software-properties-common
apt_install flatpak
run_quiet sudo flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
