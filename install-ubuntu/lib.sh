#!/usr/bin/env bash

runUnlessDry() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would run: $*"
    return
  fi
  "$@"
}

apt_install_local_package() {
  run_quiet sudo env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 install -y "$1"
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
  local force="${1:-}"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would update package index"
    return
  fi
  if [[ "$force" != "--force" && -n "${GUEPARDO_INDEX_MARKER:-}" && -f "$GUEPARDO_INDEX_MARKER" ]]; then
    log "APT package index already refreshed in this run."
    return
  fi
  run_quiet sudo env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 update || return 1
  if [[ -n "${GUEPARDO_INDEX_MARKER:-}" ]]; then
    touch "$GUEPARDO_INDEX_MARKER"
  fi
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

  run_quiet sudo env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 install -y "${missing_packages[@]}" || return 1

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

  error "No available apt package found among: $*"
  return 1
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
  apt_install_local_package "$package_file"
  rm -f "$package_file"
  success "OpenCode Desktop installed"
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
  apt_install_local_package "$package_file"
  rm -f "$package_file"
  success "Google Chrome installed from the official deb package"
}

steam_command_exists() {
  # steam-installer ships /usr/games/steam, which is not in the default PATH.
  command_exists steam || [[ -x /usr/games/steam ]]
}

install_steam() {
  if steam_command_exists; then
    log "Steam is already installed."
    return
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install Steam via apt (multiverse)"
    return
  fi

  run_quiet sudo add-apt-repository -y multiverse

  # steam-libs-i386 lives in the i386 architecture, so the foreign arch has to
  # exist before apt can resolve the dependency chain.
  if ! dpkg --print-foreign-architectures | grep -Fxq i386; then
    log "Enabling the i386 architecture required by Steam..."
    run_quiet sudo dpkg --add-architecture i386
  fi

  apt_update --force
  # Ubuntu 25.04 (and newer) dropped the transitional "steam" package in favour
  # of "steam-installer", so accept whichever name this release provides.
  apt_install_first_available steam steam-installer
  success "Steam installed"
}

# Newest NVIDIA driver Ubuntu offers for this GPU, as "<driver package>
# <kernel modules package>" (e.g. "nvidia-driver-615-open linux-modules-...").
# Server builds are skipped; for the same branch the -open build wins, since
# Ubuntu lists it only for GPUs that support it. Empty when none is listed.
latest_nvidia_driver() {
  ubuntu-drivers list 2>/dev/null \
    | sed -nE 's/^(nvidia-driver-([0-9]+)(-open)?), \(kernel modules provided by ([^)]+)\).*/\2 \3 \1 \4/p' \
    | sort -k1,1n -k2,2 | tail -n 1 | awk '{print $(NF-1), $NF}' || true
}

install_gpu_drivers() {
  # Vulkan/Mesa userspace (including 32-bit for Proton) plus, on NVIDIA
  # hardware, the newest driver branch Ubuntu offers. ubuntu-drivers itself
  # does nothing once any NVIDIA driver is installed, so apt installs it.
  apt_install_optional pciutils mesa-vulkan-drivers libvulkan1 mesa-vulkan-drivers:i386 libvulkan1:i386

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install the newest NVIDIA driver when an NVIDIA GPU is detected"
    return
  fi
  if ! command_exists lspci || ! lspci 2>/dev/null | grep -Ei 'vga|3d|display' | grep -qi nvidia; then
    log "No NVIDIA GPU detected; keeping the open-source graphics stack."
    return
  fi

  apt_install ubuntu-drivers-common
  local latest driver modules branch current=""
  latest="$(latest_nvidia_driver)"
  read -r driver modules <<< "$latest" || true
  branch="$(grep -oE '[0-9]+' <<< "${driver:-}" | head -n 1 || true)"
  if command_exists nvidia-smi && nvidia-smi >/dev/null 2>&1; then
    current="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n 1 | cut -d. -f1)"
    if [[ -z "$branch" || ( -n "$current" && "$current" -ge "$branch" ) ]]; then
      log "NVIDIA driver ${current:-?} is already working and up to date."
      return
    fi
  fi

  if [[ -n "$branch" ]]; then
    log "Installing $driver${current:+ (replacing $current)}."
    apt_install "$driver" "$modules"
    apt_install_optional "libnvidia-gl-$branch:i386"
  else
    run_quiet sudo ubuntu-drivers install
  fi
  REQUIRES_REBOOT="true"
  warn "NVIDIA driver installed. Reboot to load it; with Secure Boot enabled, enroll the MOK key when prompted."
  success "NVIDIA driver installed"
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
    apt_update --force
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
  apt_install_local_package "$package_file"
  rm -f "$package_file"
  success "Discord installed"
}

install_obsidian() {
  if command_exists obsidian; then
    log "Obsidian is already installed."
    return
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install Obsidian from official .deb, with a Flatpak fallback"
    return
  fi
  local url package_file
  if ! url="$(github_latest_asset_url "obsidianmd/obsidian-releases" "obsidian_.*_amd64\\.deb$")"; then
    warn "Could not resolve the Obsidian .deb URL from GitHub; falling back to Flatpak."
    flatpak_install_app "md.obsidian.Obsidian"
    return
  fi
  package_file="/tmp/obsidian.deb"
  if ! download_file "$url" "$package_file"; then
    warn "Could not download the Obsidian .deb; falling back to Flatpak."
    rm -f "$package_file"
    flatpak_install_app "md.obsidian.Obsidian"
    return
  fi
  if ! apt_install_local_package "$package_file"; then
    warn "Could not install the Obsidian .deb; falling back to Flatpak."
    rm -f "$package_file"
    flatpak_install_app "md.obsidian.Obsidian"
    return
  fi
  rm -f "$package_file"
  success "Obsidian installed"
}
