#!/usr/bin/env bash

section "Warp Terminal"
  if command_exists warp-terminal; then
    log "Warp Terminal is already installed."
  else
    if [[ ! -f /etc/yum.repos.d/warpdotdev.repo ]]; then
      log "Adding Warp repository..."
      if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would configure Warp repository"
      else
        sudo tee /etc/yum.repos.d/warpdotdev.repo > /dev/null <<'EOF'
[warpdotdev]
name=Warp Repository
baseurl=https://releases.warp.dev/linux/rpm/stable
enabled=1
gpgcheck=1
gpgkey=https://releases.warp.dev/linux/keys/warp.asc
EOF
        dnf_update --force
      fi
    fi
    dnf_install warp-terminal
  fi
