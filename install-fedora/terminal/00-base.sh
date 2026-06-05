#!/usr/bin/env bash

section "Base Tools"
dnf_update

dnf_install \
  bat \
  bottom \
  fd-find \
  fzf \
  git \
  curl \
  wget \
  gnupg2 \
  ca-certificates \
  ripgrep \
  tealdeer \
  jq \
  nodejs \
  npm \
  xsel \
  unzip \
  dnf-plugins-core \
  NetworkManager

configure_static_ipv4_network

if ! command_exists gh; then
  log "Configuring GitHub CLI repository..."
  run_quiet sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
  dnf_update
  dnf_install gh
else
  log "gh is already installed."
fi

log "Installing eza..."
dnf_install eza
comment_line_if_present 'alias ls="eza"' "$TARGET_HOME/.bashrc"
comment_line_if_present "alias l='ls -CF'" "$TARGET_HOME/.bashrc"
comment_line_if_present 'alias l="ls -CF"' "$TARGET_HOME/.bashrc"
add_line_if_missing "alias ls='eza'" "$TARGET_HOME/.bashrc"
add_line_if_missing "alias ll='ls -alF'" "$TARGET_HOME/.bashrc"
add_line_if_missing "alias la='ls -A'" "$TARGET_HOME/.bashrc"
add_line_if_missing "alias l='ls -l'" "$TARGET_HOME/.bashrc"
add_line_if_missing 'alias bottom="btm"' "$TARGET_HOME/.bashrc"
success "Shell aliases configured: ls, ll, la, l, bottom"

install_sd
install_dust
install_lazygit
install_yazi
install_npm_global_package opencode opencode-ai
install_npm_global_package codex @openai/codex
comment_line_if_present 'eval "$(atuin init bash)"' "$TARGET_HOME/.bashrc"

dnf_install podman
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
      sudo dnf makecache
    fi
  fi
  dnf_install warp-terminal
fi
