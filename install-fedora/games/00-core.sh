#!/usr/bin/env bash

section "Gaming prerequisites"
dnf_update
dnf_install curl ca-certificates
dnf_install flatpak
run_quiet sudo flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
