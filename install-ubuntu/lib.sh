#!/usr/bin/env bash

RUNNING_GNOME="false"
GNOME_SETTINGS_CHANGED="false"
REQUIRES_REBOOT="false"
DRY_RUN="${DRY_RUN:-false}"
TARGET_USER="${USER}"
TARGET_HOME="${HOME}"
STATIC_NETWORK_INTERFACE="${STATIC_NETWORK_INTERFACE:-enp5s0}"
STATIC_NETWORK_CONNECTION="${STATIC_NETWORK_CONNECTION:-static-${STATIC_NETWORK_INTERFACE}}"
STATIC_NETWORK_ADDRESS="${STATIC_NETWORK_ADDRESS:-192.168.1.77/24}"
STATIC_NETWORK_GATEWAY="${STATIC_NETWORK_GATEWAY:-192.168.1.1}"
STATIC_NETWORK_DNS="${STATIC_NETWORK_DNS:-1.1.1.1}"

runUnlessDry() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would run: $*"
    return
  fi
  "$@"
}
export TARGET_USER TARGET_HOME
OMAKUB_THEME_REPO="https://raw.githubusercontent.com/basecamp/omakub/master"
SUPPORTED_THEMES=(
  "tokyo-night"
  "catppuccin"
  "nord"
  "everforest"
  "gruvbox"
  "kanagawa"
  "ristretto"
  "rose-pine"
  "matte-black"
  "osaka-jade"
)

if [[ -t 1 ]]; then
  COLOR_RESET=$'\033[0m'
  COLOR_BOLD=$'\033[1m'
  COLOR_DIM=$'\033[2m'
  COLOR_BLUE=$'\033[34m'
  COLOR_GREEN=$'\033[32m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_RED=$'\033[31m'
else
  COLOR_RESET=""
  COLOR_BOLD=""
  COLOR_DIM=""
  COLOR_BLUE=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_RED=""
fi

section() {
  printf "\n%s%s%s\n" "${COLOR_BOLD}${COLOR_BLUE}" "$*" "${COLOR_RESET}"
}

log() {
  printf "%s->%s %s\n" "${COLOR_DIM}" "${COLOR_RESET}" "$*"
  log_to_file "INFO" "$*"
}

success() {
  printf "%sOK%s %s\n" "${COLOR_GREEN}" "${COLOR_RESET}" "$*"
  log_to_file "OK" "$*"
}

warn() {
  printf "%sWARN%s %s\n" "${COLOR_YELLOW}" "${COLOR_RESET}" "$*" >&2
  log_to_file "WARN" "$*"
}

error() {
  printf "%sERROR%s %s\n" "${COLOR_RED}" "${COLOR_RESET}" "$*" >&2
  log_to_file "ERROR" "$*"
}

log_to_file() {
  local level="$1"
  local message="$2"
  if [[ -n "${INSTALL_LOG:-}" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$INSTALL_LOG"
  fi
}

join_by() {
  local delimiter="$1"
  shift

  local first="true"
  local item
  for item in "$@"; do
    if [[ "$first" == "true" ]]; then
      printf "%s" "$item"
      first="false"
    else
      printf "%s%s" "$delimiter" "$item"
    fi
  done
}

run_quiet() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would run: $*"
    return 0
  fi

  local log_file exit_code
  log_file="$(mktemp)"

  if "$@" >"$log_file" 2>&1; then
    rm -f "$log_file"
    return 0
  else
    exit_code=$?
  fi

  error "Command failed: $*"
  sed -n '1,120p' "$log_file" >&2 || true
  rm -f "$log_file"
  return "$exit_code"
}

require_sudo() {
  if [[ "$DRY_RUN" == "true" ]]; then
    return
  fi

  if sudo -n true 2>/dev/null; then
    return
  fi

  if [[ ! -t 0 ]]; then
    error "sudo needs a password, but no interactive TTY is available."
    exit 1
  fi

  sudo -v
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
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

configure_static_ipv4_network() {
  local interface="$STATIC_NETWORK_INTERFACE"
  local connection="$STATIC_NETWORK_CONNECTION"
  local previous_connections=()
  local active_connection active_device

  section "Network"
  log "Configuring static IPv4 for $interface..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would configure $interface with $STATIC_NETWORK_ADDRESS, gateway $STATIC_NETWORK_GATEWAY, DNS $STATIC_NETWORK_DNS"
    return
  fi

  if ! command_exists nmcli; then
    warn "NetworkManager nmcli is not available; skipping static IPv4 configuration"
    return
  fi

  if ! nmcli -t -f DEVICE device status | grep -Fxq "$interface"; then
    warn "Network interface $interface was not found; skipping static IPv4 configuration"
    return
  fi

  while IFS=: read -r active_connection active_device; do
    if [[ "$active_device" == "$interface" && "$active_connection" != "$connection" ]]; then
      previous_connections+=("$active_connection")
    fi
  done < <(nmcli -t -f NAME,DEVICE connection show --active)

  if nmcli -t -f NAME connection show | grep -Fxq "$connection"; then
    run_quiet nmcli connection modify "$connection" connection.interface-name "$interface"
  else
    run_quiet nmcli connection add type ethernet ifname "$interface" con-name "$connection"
  fi

  run_quiet nmcli connection modify "$connection" \
    connection.autoconnect yes \
    ipv4.method manual \
    ipv4.addresses "$STATIC_NETWORK_ADDRESS" \
    ipv4.gateway "$STATIC_NETWORK_GATEWAY" \
    ipv4.dns "$STATIC_NETWORK_DNS" \
    ipv4.ignore-auto-dns yes \
    ipv6.ignore-auto-dns yes

  for active_connection in "${previous_connections[@]}"; do
    nmcli connection modify "$active_connection" connection.autoconnect no >/dev/null 2>&1 || true
  done

  run_quiet nmcli connection up "$connection"
  success "Static IPv4 configured on $interface"
}

normalize_theme_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

theme_supported() {
  local candidate
  candidate="$(normalize_theme_name "$1")"

  local theme
  for theme in "${SUPPORTED_THEMES[@]}"; do
    if [[ "$theme" == "$candidate" ]]; then
      return 0
    fi
  done

  return 1
}

list_supported_themes() {
  printf '%s\n' "${SUPPORTED_THEMES[@]}"
}

add_line_if_missing() {
  local line="$1"
  local file="$2"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would ensure line exists in $file: $line"
    return
  fi

  touch "$file"

  if ! grep -Fqx "$line" "$file"; then
    echo "$line" >> "$file"
  fi
}

comment_line_if_present() {
  local line="$1"
  local file="$2"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would comment line in $file if present: $line"
    return
  fi

  touch "$file"

  if grep -Fqx "$line" "$file"; then
    local escaped_line
    escaped_line="$(printf '%s\n' "$line" | sed 's/[\/&]/\\&/g')"
    sed -i "s/^${escaped_line}$/# ${escaped_line}/" "$file"
  fi
}

flatpak_install_app() {
  local app_id="$1"
  shift

  local check
  for check in "$@"; do
    case "$check" in
      apt:*)
        if apt_package_installed "${check#apt:}"; then
          log "$app_id is already installed via APT (${check#apt:})."
          return
        fi
        ;;
      desktop:*)
        if [[ -f "/usr/share/applications/${check#desktop:}" || -f "$TARGET_HOME/.local/share/applications/${check#desktop:}" ]]; then
          log "$app_id desktop entry found (${check#desktop:})."
          return
        fi
        ;;
      *)
        if command_exists "$check"; then
          log "$app_id is already available ($check in PATH)."
          return
        fi
        ;;
    esac
  done

  if [[ "$DRY_RUN" == "true" ]]; then
    if flatpak info "$app_id" >/dev/null 2>&1; then
      log "[DRY-RUN] Would update flatpak: $app_id"
    else
      log "[DRY-RUN] Would install flatpak: $app_id"
    fi
    return
  fi

  if flatpak info "$app_id" >/dev/null 2>&1; then
    run_quiet flatpak update -y "$app_id"
    success "Flatpak updated: $app_id"
  else
    run_quiet flatpak install -y flathub "$app_id"
    success "Flatpak installed: $app_id"
  fi
}

download_file() {
  local url="$1"
  local destination="$2"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would download $url to $destination"
    return
  fi

  mkdir -p "$(dirname "$destination")"
  curl -fsSL "$url" -o "$destination"
}

github_latest_asset_url() {
  local repo="$1"
  local pattern="$2"

  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
    | jq -r --arg pattern "$pattern" '.assets[] | select(.name | test($pattern)) | .browser_download_url' \
    | head -n 1
}

install_npm_global_package() {
  local command_name="$1"
  local package_name="$2"

  if command_exists "$command_name"; then
    log "$command_name is already available."
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install npm package globally: $package_name"
    return
  fi

  if ! command_exists npm; then
    error "npm is required to install $package_name."
    return 1
  fi

  run_quiet sudo npm install -g "$package_name"
  success "$command_name installed"
}

install_dust() {
  if command_exists dust; then
    log "dust is already available."
    return
  fi

  run_quiet bash -lc 'curl -sSfL https://raw.githubusercontent.com/bootandy/dust/refs/heads/master/install.sh | sh'
  success "dust installed"
}

install_lazygit() {
  if command_exists lazygit; then
    log "lazygit is already available."
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install lazygit from GitHub releases"
    return
  fi

  local asset_arch tmpdir url
  case "$(uname -m)" in
    x86_64|amd64)
      asset_arch="x86_64"
      ;;
    aarch64|arm64)
      asset_arch="arm64"
      ;;
    *)
      error "Unsupported lazygit architecture: $(uname -m)"
      return 1
      ;;
  esac

  url="$(github_latest_asset_url "jesseduffield/lazygit" "linux_${asset_arch}\\.tar\\.gz$")"
  if [[ -z "$url" ]]; then
    error "Could not find a lazygit release asset for linux_${asset_arch}."
    return 1
  fi

  tmpdir="$(mktemp -d)"
  run_quiet bash -lc "curl -sSfL '$url' | tar xz -C '$tmpdir' lazygit && sudo install -m 0755 '$tmpdir/lazygit' /usr/local/bin/lazygit"
  rm -rf "$tmpdir"
  success "lazygit installed"
}

install_yazi() {
  if command_exists yazi && command_exists ya; then
    log "yazi is already available."
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install yazi from GitHub releases"
    return
  fi

  local target tmpdir url yazi_binary ya_binary
  case "$(uname -m)" in
    x86_64|amd64)
      target="x86_64-unknown-linux-gnu"
      ;;
    aarch64|arm64)
      target="aarch64-unknown-linux-gnu"
      ;;
    *)
      error "Unsupported yazi architecture: $(uname -m)"
      return 1
      ;;
  esac

  url="$(github_latest_asset_url "sxyazi/yazi" "yazi-${target}\\.zip$")"
  if [[ -z "$url" ]]; then
    error "Could not find a yazi release asset for $target."
    return 1
  fi

  tmpdir="$(mktemp -d)"
  run_quiet bash -lc "curl -sSfL '$url' -o '$tmpdir/yazi.zip' && unzip -q '$tmpdir/yazi.zip' -d '$tmpdir'"
  yazi_binary="$(find "$tmpdir" -type f -name yazi -perm /111 | head -n 1)"
  ya_binary="$(find "$tmpdir" -type f -name ya -perm /111 | head -n 1)"
  if [[ -z "$yazi_binary" || -z "$ya_binary" ]]; then
    rm -rf "$tmpdir"
    error "Could not find yazi and ya binaries in the release archive."
    return 1
  fi
  run_quiet sudo install -m 0755 "$yazi_binary" /usr/local/bin/yazi
  run_quiet sudo install -m 0755 "$ya_binary" /usr/local/bin/ya
  rm -rf "$tmpdir"
  success "yazi installed"
}

install_lm_studio() {
  if flatpak run it.mijorus.gearlever --list-installed 2>/dev/null | grep -Fqi "LM Studio"; then
    log "LM Studio is already integrated with Gear Lever."
    return
  fi

  local url
  case "$(uname -m)" in
    x86_64|amd64)
      url="https://lmstudio.ai/download/latest/linux/x64?format=AppImage"
      ;;
    aarch64|arm64)
      url="https://lmstudio.ai/download/latest/linux/arm64?format=AppImage"
      ;;
    *)
      error "Unsupported LM Studio architecture: $(uname -m)"
      return 1
      ;;
  esac

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would download LM Studio AppImage from $url and integrate it with Gear Lever"
    return
  fi

  if ! flatpak info it.mijorus.gearlever >/dev/null 2>&1; then
    error "Gear Lever must be installed before integrating LM Studio."
    return 1
  fi

  local package_file
  package_file="$TARGET_HOME/Downloads/LM_Studio.AppImage"

  sudo rm -rf /opt/lm-studio
  sudo rm -f /usr/local/bin/lm-studio /usr/local/share/applications/lm-studio.desktop
  mkdir -p "$(dirname "$package_file")"
  download_file "$url" "$package_file"
  chmod 0755 "$package_file"
  run_quiet flatpak run it.mijorus.gearlever --integrate --replace --yes "$package_file"
  success "LM Studio integrated with Gear Lever"
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

install_antigravity_desktop() {
  if command_exists antigravity || [[ -x /opt/antigravity/antigravity ]]; then
    log "Antigravity is already available."
    return
  fi

  local platform
  case "$(uname -m)" in
    x86_64|amd64)
      platform="linux-x64"
      ;;
    aarch64|arm64)
      platform="linux-arm"
      ;;
    *)
      error "Unsupported Antigravity architecture: $(uname -m)"
      return 1
      ;;
  esac

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would fetch the latest Antigravity release and install the ${platform} tarball"
    return
  fi

  local release_json version execution_id url
  release_json="$(curl -fsSL https://antigravity-auto-updater-974169037036.us-central1.run.app/releases)"
  version="$(jq -r '.[0].version' <<<"$release_json")"
  execution_id="$(jq -r '.[0].execution_id' <<<"$release_json")"
  url="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${version}-${execution_id}/${platform}/Antigravity.tar.gz"

  local archive app_dir bin_path desktop_file desktop_tmp extract_dir icon_path
  archive="/tmp/Antigravity.tar.gz"
  app_dir="/opt/antigravity"
  bin_path="/usr/local/bin/antigravity"
  desktop_file="/usr/local/share/applications/antigravity.desktop"
  desktop_tmp="$(mktemp)"
  extract_dir="$(mktemp -d)"
  icon_path="$app_dir/resources/app/resources/linux/code.png"

  download_file "$url" "$archive"
  run_quiet tar -xzf "$archive" -C "$extract_dir"
  run_quiet sudo install -d /opt /usr/local/share/applications
  sudo rm -rf "$app_dir"
  run_quiet sudo mv "$extract_dir/Antigravity" "$app_dir"
  run_quiet sudo ln -sf "$app_dir/antigravity" "$bin_path"

  cat > "$desktop_tmp" <<EOF
[Desktop Entry]
Type=Application
Name=Antigravity
Comment=Google Antigravity IDE
Exec=$bin_path %F
Icon=$icon_path
Terminal=false
Categories=Development;IDE;
EOF
  run_quiet sudo install -m 0644 "$desktop_tmp" "$desktop_file"

  rm -rf "$archive" "$desktop_tmp" "$extract_dir"
  success "Antigravity installed"
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
    log "[DRY-RUN] Would install Lutris via PPA"
    return
  fi
  run_quiet sudo add-apt-repository -y ppa:lutris-team/lutris
  apt_update
  apt_install lutris
  success "Lutris installed"
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

detect_desktop() {
  if [[ "${XDG_CURRENT_DESKTOP:-}" == *"GNOME"* ]]; then
    RUNNING_GNOME="true"
  fi
}

configure_gnome_for_install() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would disable GNOME auto-lock and suspend"
    GNOME_SETTINGS_CHANGED="false"
    return
  fi
  log "Disabling GNOME auto-lock and suspend while installation runs..."
  gsettings set org.gnome.desktop.screensaver lock-enabled false
  gsettings set org.gnome.desktop.session idle-delay 0
  GNOME_SETTINGS_CHANGED="true"
}

cleanup() {
  if [[ "$RUNNING_GNOME" == "true" && "$GNOME_SETTINGS_CHANGED" == "true" ]]; then
    log "Restoring GNOME lock and idle settings..."
    gsettings set org.gnome.desktop.screensaver lock-enabled true || true
    gsettings set org.gnome.desktop.session idle-delay 300 || true
  fi
}

mark_reboot_required() {
  REQUIRES_REBOOT="true"
}

apply_selected_theme() {
  local theme="${1:-}"

  if [[ -z "$theme" ]]; then
    return
  fi

  if [[ "$RUNNING_GNOME" != "true" ]]; then
    warn "Skipping theme '$theme' because GNOME was not detected."
    return
  fi

  if ! theme_supported "$theme"; then
    error "Unsupported theme: $theme"
    warn "Supported themes:"
    list_supported_themes >&2
    exit 1
  fi

  local omakub_root="$TARGET_HOME/.local/share/omakub"
  local theme_dir="$omakub_root/themes/$theme"

  log "Applying theme: $theme"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would download and apply theme: $theme"
    return
  fi

  download_file "$OMAKUB_THEME_REPO/themes/$theme/background.jpg" "$theme_dir/background.jpg"
  download_file "$OMAKUB_THEME_REPO/themes/$theme/gnome.sh" "$theme_dir/gnome.sh"
  download_file "$OMAKUB_THEME_REPO/themes/set-gnome-theme.sh" "$omakub_root/themes/set-gnome-theme.sh"

  export OMAKUB_PATH="$omakub_root"

  # shellcheck source=/dev/null
  source "$theme_dir/gnome.sh"
  success "Theme applied: $theme"
}

interactive_select() {
  local prompt="$1"
  shift
  local options=("$@")
  local selected=0
  local key

  printf "\n%s\n" "$prompt"
  for i in "${!options[@]}"; do
    printf "   %s\n" "${options[$i]}"
  done

  printf '\033[?25l'
  local saved_stty
  saved_stty=$(stty -g 2>/dev/null || echo "")
  stty raw -echo 2>/dev/null || true

  redraw() {
    local sel=$1
    printf '\033[%dA' "${#options[@]}"
    for i in "${!options[@]}"; do
      if [[ $i -eq $sel ]]; then
        printf "\r\033[7m > %s \033[27m\n" "${options[$i]}"
      else
        printf "\r   %s\n" "${options[$i]}"
      fi
    done
  }

  while true; do
    IFS= read -r -n1 key 2>/dev/null || true
    if [[ $key == $'\033' ]]; then
      IFS= read -r -t 0.001 -n1 next 2>/dev/null || true
      if [[ $next == '[' ]]; then
        IFS= read -r -t 0.001 -n1 dir 2>/dev/null || true
        case "$dir" in
          A)
            ((selected > 0)) && ((selected--))
            redraw $selected
            ;;
          B)
            ((selected < ${#options[@]} - 1)) && ((selected++))
            redraw $selected
            ;;
        esac
      fi
    elif [[ -z $key || $key == $'\n' || $key == $'\r' ]]; then
      break
    elif [[ $key == $'\x03' ]]; then
      printf '\033[?25h'
      [[ -n "$saved_stty" ]] && stty "$saved_stty" 2>/dev/null || true
      exit 1
    fi
  done

  printf '\033[?25h'
  [[ -n "$saved_stty" ]] && stty "$saved_stty" 2>/dev/null || true
  printf '\033[%dB' "$(( ${#options[@]} - selected - 1 ))"
  echo "${options[$selected]}"
  return $selected
}

finish_installation() {
  log "Installation complete."
  warn "Open a new terminal to load the updated PATH and aliases."

  if [[ "$REQUIRES_REBOOT" == "true" ]]; then
    warn "Reboot the computer before using Samba/Nautilus Share. Logoff/login is not enough."
  fi
}
