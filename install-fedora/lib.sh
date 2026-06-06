#!/usr/bin/env bash

dnf_package_installed() {
  rpm -q "$1" >/dev/null 2>&1 || rpm -q --whatprovides "$1" >/dev/null 2>&1
}

dnf_update() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would update package index"
    return
  fi
  run_quiet sudo dnf makecache -y
  success "Package index updated"
}

dnf_install() {
  local allow_skip="${DNF_ALLOW_SKIP_UNAVAILABLE:-false}"
  local packages=("$@")
  local missing_packages=()
  local package

  for package in "${packages[@]}"; do
    if dnf_package_installed "$package"; then
      log "$package is already installed."
    else
      log "Installing $package..."
      missing_packages+=("$package")
    fi
  done

  if [[ "${#missing_packages[@]}" -eq 0 ]]; then
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install: ${missing_packages[*]}"
    return
  fi

  if [[ "$allow_skip" == "true" ]]; then
    run_quiet sudo dnf install -y --skip-unavailable "${missing_packages[@]}"
  else
    run_quiet sudo dnf install -y "${missing_packages[@]}"
  fi

  for package in "${missing_packages[@]}"; do
    if dnf_package_installed "$package"; then
      success "$package installed"
    elif [[ "$allow_skip" == "true" ]]; then
      warn "$package was not available and was skipped"
    else
      error "$package was not installed"
      return 1
    fi
  done
}

dnf_install_optional() {
  DNF_ALLOW_SKIP_UNAVAILABLE=true dnf_install "$@"
}

install_sd() {
  if command_exists sd; then
    log "sd is already available."
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install sd"
    return
  fi

  local tmpdir url
  tmpdir="$(mktemp -d)"
  url="$(curl -sL https://api.github.com/repos/chmln/sd/releases/latest | jq -r '.assets[] | select(.name | test("x86_64.*linux-gnu\\.tar\\.gz$")) | .browser_download_url')"
  run_quiet bash -lc "curl -sSfL '$url' | tar xz -C '$tmpdir' && sudo mv '$tmpdir'/*/sd /usr/local/bin/sd"
  rm -rf "$tmpdir"
  success "sd installed"
}

install_opencode_desktop() {
  if dnf_package_installed opencode-desktop || command_exists opencode-desktop; then
    log "OpenCode Desktop is already installed."
    return
  fi

  case "$(uname -m)" in
    x86_64|amd64)
      ;;
    *)
      error "OpenCode Desktop Linux package is only available for x86_64 from opencode.ai."
      return 1
      ;;
  esac

  local package_file="/tmp/opencode-desktop.rpm"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install OpenCode Desktop from https://opencode.ai/download/stable/linux-x64-rpm"
    return
  fi

  download_file "https://opencode.ai/download/stable/linux-x64-rpm" "$package_file"
  run_quiet sudo dnf install -y "$package_file"
  rm -f "$package_file"
  success "OpenCode Desktop installed"
}

install_vscode_desktop() {
  if dnf_package_installed code && command_exists code; then
    log "Visual Studio Code is already installed."
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would configure the official Visual Studio Code RPM repository and install code"
    return
  fi

  run_quiet sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  sudo tee /etc/yum.repos.d/vscode.repo > /dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

  dnf_update
  dnf_install code
  success "Visual Studio Code installed with the code CLI"
}

install_google_chrome() {
  if dnf_package_installed google-chrome-stable && command_exists google-chrome; then
    log "Google Chrome is already installed."
    return
  fi

  case "$(uname -m)" in
    x86_64|amd64)
      ;;
    *)
      error "Google Chrome official Linux package is only available for x86_64."
      return 1
      ;;
  esac

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would configure the official Google Chrome RPM repository and install google-chrome-stable"
    return
  fi

  sudo tee /etc/yum.repos.d/google-chrome.repo > /dev/null <<'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF

  dnf_update
  dnf_install google-chrome-stable
  success "Google Chrome installed from the official rpm repository"
}

install_steam() {
  if command_exists steam; then
    log "Steam is already installed."
    return
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install Steam via RPM Fusion"
    return
  fi
  local release
  release="$(rpm -E %fedora)"
  if ! dnf_package_installed rpmfusion-nonfree-release; then
    run_quiet sudo dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${release}.noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${release}.noarch.rpm"
  fi
  dnf_install steam
  success "Steam installed"
}

install_lutris() {
  if command_exists lutris; then
    log "Lutris is already installed."
    return
  fi
  dnf_install lutris
  success "Lutris installed"
}

install_qbittorrent() {
  if command_exists qbittorrent; then
    log "qBittorrent is already installed."
    return
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install qBittorrent via RPM Fusion"
    return
  fi
  local release
  release="$(rpm -E %fedora)"
  if ! dnf_package_installed rpmfusion-free-release; then
    run_quiet sudo dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${release}.noarch.rpm"
  fi
  dnf_install qbittorrent
  success "qBittorrent installed"
}

install_discord() {
  if command_exists discord; then
    log "Discord is already installed."
    return
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install Discord via RPM Fusion"
    return
  fi
  local release
  release="$(rpm -E %fedora)"
  if ! dnf_package_installed rpmfusion-nonfree-release; then
    run_quiet sudo dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${release}.noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${release}.noarch.rpm"
  fi
  dnf_install discord
  success "Discord installed"
}

install_obsidian() {
  if command_exists obsidian; then
    log "Obsidian is already installed."
    return
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install Obsidian from official .rpm"
    return
  fi
  local url package_file
  url="$(github_latest_asset_url "obsidianmd/obsidian-releases" "obsidian-[0-9].*\\.rpm$")"
  if [[ -z "$url" ]]; then
    error "Could not find Obsidian .rpm URL."
    return 1
  fi
  package_file="/tmp/obsidian.rpm"
  download_file "$url" "$package_file"
  dnf_install "$package_file"
  rm -f "$package_file"
  success "Obsidian installed"
}
