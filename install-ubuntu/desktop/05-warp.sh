#!/usr/bin/env bash

section "Warp Terminal"
  if command_exists warp-terminal; then
    log "Warp Terminal is already installed."
  else
    if ! grep -q "warpdotdev" /etc/apt/sources.list.d/*.list 2>/dev/null; then
      log "Adding Warp repository..."
      if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would configure Warp repository"
      else
        install_apt_dearmored_keyring \
          https://releases.warp.dev/linux/keys/warp.asc \
          /etc/apt/keyrings/warpdotdev.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/warpdotdev.gpg] https://releases.warp.dev/linux/deb stable main" \
          | sudo tee /etc/apt/sources.list.d/warpdotdev.list > /dev/null
        sudo chmod 644 /etc/apt/keyrings/warpdotdev.gpg /etc/apt/sources.list.d/warpdotdev.list
        apt_update --force
      fi
    fi
    apt_install warp-terminal
  fi
