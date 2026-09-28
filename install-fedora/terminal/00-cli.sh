#!/usr/bin/env bash

section "Base Tools"
dnf_update

base_packages=(
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
  unzip \
  dnf-plugins-core
)


dnf_install "${base_packages[@]}"

if ! command_exists gh; then
  log "Configuring GitHub CLI repository..."
  run_quiet sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
  dnf_update --force
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

run_independent install_sd install_dust install_lazygit install_yazi
comment_line_if_present 'eval "$(atuin init bash)"' "$TARGET_HOME/.bashrc"
