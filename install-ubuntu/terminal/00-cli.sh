#!/usr/bin/env bash

section "Base Tools"

apt_update

base_packages=(
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
  unzip
)

apt_install "${base_packages[@]}"

repos_changed=false

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
    repos_changed=true
  fi
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
    repos_changed=true
  fi
else
  log "eza is already installed."
fi
if [[ "$repos_changed" == "true" ]]; then
  apt_update --force
fi
apt_install gh eza
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

run_independent install_dust install_lazygit install_yazi
comment_line_if_present 'eval "$(atuin init bash)"' "$TARGET_HOME/.bashrc"
