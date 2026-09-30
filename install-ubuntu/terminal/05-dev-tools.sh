#!/usr/bin/env bash

section "Developer Tools"
apt_install xsel podman
install_node_lts
install_npm_global_package opencode opencode-ai
install_npm_global_package codex @openai/codex
if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY-RUN] Would configure podman registries"
else
  sudo mkdir -p /etc/containers/registries.conf.d
  sudo tee /etc/containers/registries.conf.d/00-shortnames.conf > /dev/null <<'EOF'
unqualified-search-registries = ["docker.io", "quay.io"]
short-name-mode = "permissive"
EOF
fi
success "Podman short-name registries configured"

apt_install_optional podman-compose podman-docker
add_line_if_missing "alias docker-compose='podman-compose'" "$TARGET_HOME/.bashrc"
success "Docker compatibility via podman-docker: /usr/bin/docker, alias docker-compose"

if command -v bun >/dev/null 2>&1; then
  log "Bun is already available."
else
  install_remote_script https://bun.sh/install
  success "Bun installed"
fi

if command -v uv >/dev/null 2>&1; then
  log "uv is already available."
else
  install_remote_script https://astral.sh/uv/install.sh sh
  success "uv installed"
fi
