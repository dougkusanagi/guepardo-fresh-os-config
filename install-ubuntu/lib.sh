#!/usr/bin/env bash

runUnlessDry() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would run: $*"
    return
  fi
  "$@"
}

apt_package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

apt_package_available() {
  local package="$1"
  local candidate

  candidate="$(
    apt-cache policy "$package" 2>/dev/null \
      | awk '/Candidate:/ {print $2; exit}'
  )"

  [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

apt_update() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would update package index"
    return
  fi
  run_quiet sudo apt-get update -y
  success "Package index updated"
}

apt_install() {
  local packages=("$@")
  local missing_packages=()
  local package

  for package in "${packages[@]}"; do
    if apt_package_installed "$package"; then
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

  run_quiet sudo apt-get install -y "${missing_packages[@]}"

  for package in "${missing_packages[@]}"; do
    success "$package installed"
  done
}

apt_install_first_available() {
  local package

  if [[ "$#" -eq 0 ]]; then
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install first available package from: $*"
    return
  fi

  for package in "$@"; do
    if apt_package_available "$package"; then
      apt_install "$package"
      return
    fi

    log "Skipping unavailable package: $package"
  done

  warn "No available apt package found among: $*"
}

apt_install_optional() {
  local available_packages=()
  local package

  if [[ "$#" -eq 0 ]]; then
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install optional packages when available: $*"
    return
  fi

  for package in "$@"; do
    if apt_package_available "$package"; then
      available_packages+=("$package")
    else
      log "Skipping unavailable optional package: $package"
    fi
  done

  if [[ "${#available_packages[@]}" -gt 0 ]]; then
    apt_install "${available_packages[@]}"
  fi
}

apt_keyring_exists() {
  local keyring_path="$1"

  sudo test -s "$keyring_path"
}

install_apt_keyring_file() {
  local url="$1"
  local keyring_path="$2"
  local keyring_name

  keyring_name="$(basename "$keyring_path")"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would ensure apt keyring exists: $keyring_path"
    return
  fi

  sudo mkdir -p -m 755 "$(dirname "$keyring_path")"

  if apt_keyring_exists "$keyring_path"; then
    log "Apt keyring already exists: $keyring_path"
    sudo chmod go+r "$keyring_path"
    return
  fi

  local tmpdir keyring_tmp
  tmpdir="$(mktemp -d)"
  keyring_tmp="$tmpdir/$keyring_name"

  download_file "$url" "$keyring_tmp"
  sudo install -m 0644 "$keyring_tmp" "$keyring_path"
  rm -rf "$tmpdir"
  success "Apt keyring installed: $keyring_path"
}

install_apt_dearmored_keyring() {
  local url="$1"
  local keyring_path="$2"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would ensure apt keyring exists: $keyring_path"
    return
  fi

  sudo mkdir -p -m 755 "$(dirname "$keyring_path")"

  if apt_keyring_exists "$keyring_path"; then
    log "Apt keyring already exists: $keyring_path"
    sudo chmod go+r "$keyring_path"
    return
  fi

  curl -fsSL "$url" | gpg --dearmor | sudo tee "$keyring_path" > /dev/null
  sudo chmod go+r "$keyring_path"
  success "Apt keyring installed: $keyring_path"
}

install_opencode_desktop() {
  if apt_package_installed opencode-desktop || command_exists opencode-desktop; then
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

  local package_file="/tmp/opencode-desktop.deb"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install OpenCode Desktop from https://opencode.ai/download/stable/linux-x64-deb"
    return
  fi

  download_file "https://opencode.ai/download/stable/linux-x64-deb" "$package_file"
  run_quiet sudo apt-get install -y "$package_file"
  rm -f "$package_file"
  success "OpenCode Desktop installed"
}

install_vscode_desktop() {
  if apt_package_installed code && command_exists code; then
    log "Visual Studio Code is already installed."
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would configure the official Visual Studio Code APT repository and install code"
    return
  fi

  local key_file sources_file tmp_key
  key_file="/usr/share/keyrings/microsoft.gpg"
  sources_file="/etc/apt/sources.list.d/vscode.sources"
  tmp_key="$(mktemp)"

  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > "$tmp_key"
  run_quiet sudo install -D -o root -g root -m 0644 "$tmp_key" "$key_file"
  rm -f "$tmp_key"

  sudo tee "$sources_file" > /dev/null <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: $key_file
EOF

  apt_update
  apt_install code
  success "Visual Studio Code installed with the code CLI"
}

install_google_chrome() {
  if apt_package_installed google-chrome-stable && command_exists google-chrome; then
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

  local package_file="/tmp/google-chrome-stable_current_amd64.deb"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install Google Chrome from https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
    return
  fi

  download_file "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" "$package_file"
  run_quiet sudo apt-get install -y "$package_file"
  rm -f "$package_file"
  success "Google Chrome installed from the official deb package"
}

install_steam() {
  if command_exists steam; then
    log "Steam is already installed."
    return
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install Steam via apt (multiverse)"
    return
  fi
  run_quiet sudo add-apt-repository -y multiverse
  apt_update
  apt_install steam
  success "Steam installed"
}

install_lutris() {
  if command_exists lutris; then
    log "Lutris is already installed."
    return
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install Lutris via PPA or Flatpak fallback"
    return
  fi

  local ubuntu_codename
  ubuntu_codename="$(lsb_release -sc 2>/dev/null || true)"

  if [[ -n "$ubuntu_codename" ]] && curl -fsSL -o /dev/null "https://ppa.launchpadcontent.net/lutris-team/lutris/ubuntu/dists/$ubuntu_codename/Release" 2>/dev/null; then
    run_quiet sudo add-apt-repository -y ppa:lutris-team/lutris
    apt_update
    apt_install lutris
    success "Lutris installed"
  else
    warn "Lutris PPA does not support Ubuntu ${ubuntu_codename:-unknown}. Installing via Flatpak instead."
    flatpak_install_app "net.lutris.Lutris"
  fi
}

install_qbittorrent() {
  if command_exists qbittorrent; then
    log "qBittorrent is already installed."
    return
  fi
  apt_install qbittorrent
  success "qBittorrent installed"
}

install_discord() {
  if command_exists discord; then
    log "Discord is already installed."
    return
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install Discord from official .deb"
    return
  fi
  local package_file="/tmp/discord.deb"
  download_file "https://discord.com/api/download?platform=linux&format=deb" "$package_file"
  run_quiet sudo apt-get install -y "$package_file"
  rm -f "$package_file"
  success "Discord installed"
}

install_obsidian() {
  if command_exists obsidian; then
    log "Obsidian is already installed."
    return
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install Obsidian from official .deb"
    return
  fi
  local url package_file
  url="$(github_latest_asset_url "obsidianmd/obsidian-releases" "obsidian_.*_amd64\\.deb$")"
  if [[ -z "$url" ]]; then
    error "Could not find Obsidian .deb URL."
    return 1
  fi
  package_file="/tmp/obsidian.deb"
  download_file "$url" "$package_file"
  run_quiet sudo apt-get install -y "$package_file"
  rm -f "$package_file"
  success "Obsidian installed"
}
