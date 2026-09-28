#!/usr/bin/env bash

section "Developer Tools"
dnf_install nodejs npm xsel podman
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

dnf_install_optional podman-compose podman-docker
add_line_if_missing "alias docker-compose='podman-compose'" "$TARGET_HOME/.bashrc"
success "Docker compatibility via podman-docker: /usr/bin/docker, alias docker-compose"

if command -v bun >/dev/null 2>&1; then
  log "Bun is already available."
else
  run_quiet bash -lc 'curl -fsSL https://bun.sh/install | bash'
  success "Bun installed"
fi

if command -v uv >/dev/null 2>&1; then
  log "uv is already available."
else
  run_quiet sh -lc 'curl -LsSf https://astral.sh/uv/install.sh | sh'
  success "uv installed"
fi
