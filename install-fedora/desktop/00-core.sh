#!/usr/bin/env bash

section "Desktop Core"

dnf_update
dnf_install curl ca-certificates jq gnupg2 unzip tar dnf-plugins-core
dnf_install_optional fuse

dnf_install flatpak
run_quiet sudo flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
success "Flathub configured"

dnf_install gnome-tweaks flameshot
dnf_install_optional timeshift

dnf_install samba samba-client
getent group sambashare >/dev/null 2>&1 || run_quiet sudo groupadd -r sambashare
run_quiet sudo usermod -aG sambashare "$TARGET_USER"
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
    log "[DRY-RUN] Would restart smb"
  else
    sudo systemctl restart smb
  fi
  success "smb restarted"
else
  warn "systemctl is not available. Restart smb manually if needed."
fi

# Ensure proper RAR support in file-roller (unrar-free is limited)
if rpm -q unrar-free >/dev/null 2>&1; then
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would swap unrar-free with unrar"
  else
    run_quiet sudo dnf swap unrar-free unrar -y
    success "unrar installed (replaced unrar-free)"
  fi
else
  dnf_install_optional unrar
fi

mark_reboot_required
