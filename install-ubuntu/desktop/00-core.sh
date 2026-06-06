#!/usr/bin/env bash

section "Desktop Core"

apt_install snapd

run_quiet sudo add-apt-repository -y universe
run_quiet sudo add-apt-repository -y multiverse
success "Universe and multiverse repositories enabled"
apt_update
apt_install libfuse2t64 || warn "libfuse2t64 is not available on this distribution."

apt_install flatpak gnome-software-plugin-flatpak
run_quiet flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
success "Flathub configured"

apt_install gnome-tweaks timeshift flameshot

apt_install samba smbclient nautilus-share
run_quiet sudo adduser "$TARGET_USER" sambashare
success "User added to sambashare: $TARGET_USER"
if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY-RUN] Would configure Samba usershare directory"
else
  sudo mkdir -p /var/lib/samba/usershares
  sudo chown root:sambashare /var/lib/samba/usershares
  sudo chmod 1770 /var/lib/samba/usershares
fi
success "Samba usershare directory configured"

if command -v systemctl >/dev/null 2>&1; then
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would restart smbd"
  else
    sudo systemctl restart smbd
  fi
  success "smbd restarted"
else
  warn "systemctl is not available. Restart smbd manually if needed."
fi

# Ensure proper RAR support in file-roller
apt_install unrar

mark_reboot_required
