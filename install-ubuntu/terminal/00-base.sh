#!/usr/bin/env bash

section "Base Tools"
apt_update

apt_install \
  bat \
  btm \
  fd-find \
  fzf \
  git \
  curl \
  wget \
  gpg \
  ca-certificates \
  ripgrep \
  sd \
  software-properties-common \
  tealdeer \
  apt-transport-https \
  jq \
  nodejs \
  npm \
  xsel \
  unzip \
  network-manager

configure_static_ipv4_network

if ! command_exists gh; then
  log "Configuring GitHub CLI repository..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would configure GitHub CLI repository"
  else
    install_apt_keyring_file \
      https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    apt_update
  fi
  apt_install gh
else
  log "gh is already installed."
fi

if ! command_exists eza; then
  log "Configuring eza repository..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would configure eza repository"
  else
    install_apt_dearmored_keyring \
      https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
      /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
      | sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null
    sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    apt_update
  fi
  apt_install eza
else
  log "eza is already installed."
fi
comment_line_if_present 'alias ls="eza"' "$TARGET_HOME/.bashrc"
comment_line_if_present "alias l='ls -CF'" "$TARGET_HOME/.bashrc"
comment_line_if_present 'alias l="ls -CF"' "$TARGET_HOME/.bashrc"
add_line_if_missing "alias ls='eza'" "$TARGET_HOME/.bashrc"
add_line_if_missing "alias ll='ls -alF'" "$TARGET_HOME/.bashrc"
add_line_if_missing "alias la='ls -A'" "$TARGET_HOME/.bashrc"
add_line_if_missing "alias l='ls -l'" "$TARGET_HOME/.bashrc"
add_line_if_missing 'alias bat="batcat"' "$TARGET_HOME/.bashrc"
add_line_if_missing 'alias fd="fdfind"' "$TARGET_HOME/.bashrc"
add_line_if_missing 'alias bottom="btm"' "$TARGET_HOME/.bashrc"
success "Shell aliases configured: ls, ll, la, l, bat, fd, bottom"

install_dust
install_lazygit
install_yazi
install_npm_global_package opencode opencode-ai
install_npm_global_package codex @openai/codex
comment_line_if_present 'eval "$(atuin init bash)"' "$TARGET_HOME/.bashrc"

apt_install podman
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
      apt_update
    fi
  fi
  apt_install warp-terminal
fi
