#!/usr/bin/env bash

RUNNING_GNOME="false"
GNOME_SETTINGS_CHANGED="false"
GNOME_LOCK_PREVIOUS=""
GNOME_IDLE_PREVIOUS=""
REQUIRES_REBOOT="false"
DRY_RUN="${DRY_RUN:-false}"
TARGET_USER="${USER}"
TARGET_HOME="${HOME}"
export PATH="$TARGET_HOME/.local/bin:$TARGET_HOME/.bun/bin:$PATH"
STATIC_NETWORK_INTERFACE="${STATIC_NETWORK_INTERFACE:-enp5s0}"
STATIC_NETWORK_CONNECTION="${STATIC_NETWORK_CONNECTION:-static-${STATIC_NETWORK_INTERFACE}}"
STATIC_NETWORK_ADDRESS="${STATIC_NETWORK_ADDRESS:-192.168.1.77/24}"
STATIC_NETWORK_GATEWAY="${STATIC_NETWORK_GATEWAY:-192.168.1.1}"
STATIC_NETWORK_DNS="${STATIC_NETWORK_DNS:-1.1.1.1}"
export TARGET_USER TARGET_HOME

# Qt applications that need to enumerate every monitor under a Wayland session
# have to go through XWayland. Flameshot is the one we ship, and without this
# variable its grab window is confined to the monitor that spawned it.
FLAMESHOT_ENV="QT_QPA_PLATFORM=xcb"
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

# The log directory can be left behind by a privileged run (for example the
# wrapper script calling `sudo chown`/`mkdir`), which makes every later
# `log_to_file` call fail with "Permission denied" and aborts the installer.
# Repair ownership when possible, otherwise fall back to a private log path.
ensure_log_dir_writable() {
  local log_dir="$1"

  if mkdir -p "$log_dir" 2>/dev/null && [[ -w "$log_dir" ]]; then
    return 0
  fi

  if sudo -n true 2>/dev/null || [[ -n "${SUDO_ASKPASS:-}" ]]; then
    if sudo -n chown "$(id -u):$(id -g)" "$log_dir" 2>/dev/null && [[ -w "$log_dir" ]]; then
      return 0
    fi
  fi

  local fallback="${XDG_STATE_HOME:-$HOME/.local/state}/guepardo-fresh-os-config/logs"
  if mkdir -p "$fallback" 2>/dev/null && [[ -w "$fallback" ]]; then
    warn "Log directory $log_dir is not writable; using $fallback instead."
    LOG_DIR="$fallback"
    return 0
  fi

  warn "Could not create a writable log directory; file logging is disabled."
  LOG_DIR=""
  return 1
}

session_is_wayland() {
  [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]]
}

# Registers a per-user autostart entry so an app always starts with the
# environment it needs, regardless of how the session was launched.
install_user_autostart_entry() {
  local entry_name="$1"
  local exec_line="$2"
  local icon_name="${3:-}"
  local comment="${4:-}"

  local autostart_dir="$TARGET_HOME/.config/autostart"
  local entry_file="$autostart_dir/${entry_name}.desktop"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would write autostart entry $entry_file with Exec=$exec_line"
    return 0
  fi

  if ! mkdir -p "$autostart_dir" 2>/dev/null; then
    warn "Could not create $autostart_dir; skipping autostart entry for $entry_name."
    return 1
  fi

  {
    printf '[Desktop Entry]\n'
    printf 'Type=Application\n'
    printf 'Name=%s\n' "$entry_name"
    [[ -n "$comment" ]] && printf 'Comment=%s\n' "$comment"
    printf 'Exec=%s\n' "$exec_line"
    [[ -n "$icon_name" ]] && printf 'Icon=%s\n' "$icon_name"
    printf 'Terminal=false\n'
    printf 'Hidden=false\n'
    printf 'NoDisplay=false\n'
    printf 'X-GNOME-Autostart-enabled=true\n'
  } > "$entry_file" 2>/dev/null || {
    warn "Could not write $entry_file; skipping autostart entry for $entry_name."
    return 1
  }

  return 0
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

desktop_install_enabled() {
  [[ "${INSTALL_MODE:-}" != "wsl" ]]
}

run_quiet() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would run: $*"
    return 0
  fi

  local log_file exit_code
  log_file="$(mktemp)"

  if "$@" >"$log_file" 2>&1; then
    cat "$log_file"
    rm -f "$log_file"
    return 0
  else
    exit_code=$?
  fi

  error "Command failed: $*"
  # Prefix diagnostics so the interactive UI shows the actual cause, while
  # successful package-manager output stays in the complete installation log.
  tail -n 120 "$log_file" | while IFS= read -r line; do
    printf 'ERROR %s\n' "$line" >&2
  done || true
  rm -f "$log_file"
  return "$exit_code"
}

# Run independent direct-download installers with bounded concurrency. Package
# manager operations are intentionally excluded because apt/dnf hold a lock.
run_independent() {
  local limit="${GUEPARDO_JOBS:-1}"
  local -a pids=()
  local task pid result=0
  if ! [[ "$limit" =~ ^[1-8]$ ]]; then
    limit=1
  fi
  for task in "$@"; do
    if (( limit == 1 )); then
      # Keep errexit enabled inside the installer: calling a function on the
      # left side of || disables it throughout the function body.
      "$task" &
      pid="$!"
      wait "$pid" || return 1
      continue
    fi
    "$task" &
    pids+=("$!")
    if (( ${#pids[@]} >= limit )); then
      wait "${pids[0]}" || result=1
      pids=("${pids[@]:1}")
    fi
  done
  for pid in "${pids[@]}"; do
    wait "$pid" || result=1
  done
  return "$result"
}

sudo_supports_passwordless() {
  if sudo -n true 2>/dev/null; then
    return 0
  fi

  # Non-interactive sessions can still authenticate through an askpass helper.
  if [[ -n "${SUDO_ASKPASS:-}" ]] && command -v sudo-askpass >/dev/null 2>&1; then
    if sudo -A -n true 2>/dev/null; then
      return 0
    fi
  fi

  return 1
}

require_sudo() {
  if [[ "$DRY_RUN" == "true" ]]; then
    return
  fi

  if sudo_supports_passwordless; then
    return
  fi

  if [[ -n "${SUDO_ASKPASS:-}" ]] && command -v sudo-askpass >/dev/null 2>&1; then
    if sudo -A -v; then
      return
    fi
  fi

  if [[ ! -t 0 ]]; then
    error "sudo needs a password, but no interactive TTY is available."
    error "Re-run from a terminal, or export SUDO_ASKPASS=/path/to/helper to authenticate non-interactively."
    exit 1
  fi

  sudo -v
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
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

ensure_dbus_session() {
  if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    return 0
  fi
  if command -v dbus-launch &>/dev/null; then
    eval "$(dbus-launch --auto-syntax 2>/dev/null)" && return 0
  fi
  return 1
}

flatpak_install_app() {
  local app_id="$1"
  shift

  local check
  for check in "$@"; do
    case "$check" in
      apt:*)
        if type apt_package_installed &>/dev/null && apt_package_installed "${check#apt:}"; then
          log "$app_id is already installed via APT (${check#apt:})."
          return
        fi
        ;;
      dnf:*)
        if type dnf_package_installed &>/dev/null && dnf_package_installed "${check#dnf:}"; then
          log "$app_id is already installed via RPM (${check#dnf:})."
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

  if flatpak info "$app_id" >/dev/null 2>&1; then
    log "$app_id is already installed."
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install flatpak: $app_id"
    return
  fi

  # System Flatpak installation works without a graphical user bus (SSH/VM).
  ensure_dbus_session || true
  run_quiet sudo flatpak install -y --system flathub "$app_id" || return 1
  success "Flatpak installed: $app_id"
}

download_file() {
  local url="$1"
  local destination="$2"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would download $url to $destination"
    return
  fi

  local temporary
  mkdir -p "$(dirname "$destination")" || return 1
  temporary="$(mktemp "${destination}.part.XXXXXX")" || return 1
  if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 600 "$url" -o "$temporary"; then
    mv -f "$temporary" "$destination" || { rm -f "$temporary"; return 1; }
  else
    rm -f "$temporary"
    error "Download failed: $url. Check your connection and run the installer again."
    return 1
  fi
}

install_remote_script() (
  local url="$1" shell_name="${2:-bash}" tmpdir
  tmpdir="$(mktemp -d)" || return 1
  trap 'rm -rf "$tmpdir"' EXIT
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would download and execute: $url ($shell_name)"
    return 0
  fi
  download_file "$url" "$tmpdir/install.sh" || return 1
  run_quiet "$shell_name" "$tmpdir/install.sh" || return 1
)

configure_user_path() {
  add_line_if_missing 'export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"' "$TARGET_HOME/.bashrc"
}

install_node_lts() (
  local version
  version="$(node --version 2>/dev/null || true)"
  if [[ "$version" =~ ^v(22|24)\. ]] && command_exists npm; then
    log "Node $version and npm are already available."
    return
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install Node 24 LTS and npm with SHA-256 verification"
    return
  fi
  local architecture tmpdir archive checksum node_dir staging_dir=""
  case "$(uname -m)" in
    x86_64|amd64) architecture=x64 ;;
    aarch64|arm64) architecture=arm64 ;;
    *) error "Unsupported Node architecture: $(uname -m)"; return 1 ;;
  esac
  tmpdir="$(mktemp -d)" || return 1
  trap 'rm -rf "$tmpdir"; if [[ -n "$staging_dir" ]]; then rm -rf "$staging_dir"; fi' EXIT
  download_file https://nodejs.org/dist/latest-v24.x/SHASUMS256.txt "$tmpdir/SHASUMS256.txt" || return 1
  archive="$(awk -v arch="$architecture" '$2 ~ ("^node-v24\\.[0-9]+\\.[0-9]+-linux-" arch "\\.tar\\.xz$") {print $2; exit}' "$tmpdir/SHASUMS256.txt")"
  [[ -n "$archive" ]] || { error "Node LTS archive not found for $architecture."; return 1; }
  download_file "https://nodejs.org/dist/latest-v24.x/$archive" "$tmpdir/$archive" || return 1
  checksum="$(awk -v name="$archive" '$2 == name {print; exit}' "$tmpdir/SHASUMS256.txt")"
  (cd "$tmpdir" && printf '%s\n' "$checksum" | sha256sum -c -) || return 1
  node_dir="$TARGET_HOME/.local/share/guepardo/${archive%.tar.xz}"
  mkdir -p "$TARGET_HOME/.local/bin" "$(dirname "$node_dir")" || return 1
  staging_dir="$(mktemp -d "$(dirname "$node_dir")/.node.XXXXXX")" || return 1
  run_quiet tar -xJf "$tmpdir/$archive" --strip-components=1 -C "$staging_dir" || return 1
  run_quiet "$staging_dir/bin/node" --version || return 1
  if [[ ! -x "$node_dir/bin/node" || ! -x "$node_dir/bin/npm" ]]; then
    rm -rf "$node_dir"
    mv "$staging_dir" "$node_dir" || return 1
    staging_dir=""
  fi
  local binary
  for binary in node npm npx; do
    ln -sfn "$node_dir/bin/$binary" "$TARGET_HOME/.local/bin/$binary" || return 1
  done
  success "Node 24 LTS and npm installed for the current user"
)

systemd_is_running() {
  command_exists systemctl && [[ -d /run/systemd/system ]]
}

enable_system_service() {
  local service="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would enable and start $service"
    return
  fi
  if ! systemd_is_running; then
    warn "$service installed; systemd is not running here. Start the service in your normal system session."
    return
  fi
  run_quiet sudo systemctl enable --now "$service" || return 1
  success "$service service enabled and started"
}

install_composer() (
  if command_exists composer; then
    log "Composer is already available."
    return
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would verify and install Composer"
    return
  fi
  local tmpdir expected actual
  tmpdir="$(mktemp -d)" || return 1
  trap 'rm -rf "$tmpdir"' EXIT
  download_file https://composer.github.io/installer.sig "$tmpdir/installer.sig" || return 1
  download_file https://getcomposer.org/installer "$tmpdir/composer-setup.php" || return 1
  expected="$(tr -d '\r\n' < "$tmpdir/installer.sig")"
  actual="$(sha384sum "$tmpdir/composer-setup.php")"
  if [[ ! "$expected" =~ ^[a-f0-9]{96}$ || "${actual%% *}" != "$expected" ]]; then
    error "Composer installer checksum mismatch; nothing was executed."
    return 1
  fi
  run_quiet php "$tmpdir/composer-setup.php" --install-dir="$tmpdir" --filename=composer || return 1
  run_quiet sudo install -m 0755 "$tmpdir/composer" /usr/local/bin/composer || return 1
  success "Composer installed"
)

github_api_get() {
  local endpoint="$1"
  local response

  # An authenticated gh session raises the rate limit from 60 to 5000 req/h and
  # works for private or renamed repositories, so prefer it when available.
  if command_exists gh && gh auth status >/dev/null 2>&1; then
    if response="$(gh api "$endpoint" 2>/dev/null)" && [[ -n "$response" ]]; then
      printf '%s\n' "$response"
      return 0
    fi
  fi

  local -a curl_args=(-fsSL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 60 -H "Accept: application/vnd.github+json")
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args+=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi

  response="$(curl "${curl_args[@]}" "https://api.github.com/$endpoint" 2>/dev/null)" || return 1
  [[ -n "$response" ]] || return 1
  printf '%s\n' "$response"
}

github_latest_asset_url() {
  local repo="$1"
  local pattern="$2"

  local response
  if ! response="$(github_api_get "repos/$repo/releases/latest")"; then
    return 1
  fi

  # The API answers 200 with an error object when the token is invalid or the
  # rate limit is exhausted, so reject those payloads before parsing.
  if printf '%s' "$response" | jq -e 'has("message")' >/dev/null 2>&1; then
    return 1
  fi

  local url
  url="$(printf '%s' "$response" \
    | jq -r --arg pattern "$pattern" '.assets[]? | select(.name | test($pattern)) | .browser_download_url' \
    2>/dev/null | head -n 1)"

  [[ -n "$url" && "$url" != "null" ]] || return 1
  printf '%s\n' "$url"
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

  run_quiet npm install -g --prefix "$TARGET_HOME/.local" "$package_name" || return 1
  success "$command_name installed"
}

install_dust() {
  if command_exists dust; then
    log "dust is already available."
    return
  fi

  install_remote_script https://raw.githubusercontent.com/bootandy/dust/refs/heads/master/install.sh || return 1
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
  if ! download_file "$url" "$tmpdir/lazygit.tar.gz" \
    || ! run_quiet tar -xzf "$tmpdir/lazygit.tar.gz" -C "$tmpdir" lazygit \
    || ! run_quiet sudo install -m 0755 "$tmpdir/lazygit" /usr/local/bin/lazygit; then
    rm -rf "$tmpdir"
    return 1
  fi
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
  if ! download_file "$url" "$tmpdir/yazi.zip" || ! run_quiet unzip -q "$tmpdir/yazi.zip" -d "$tmpdir"; then
    rm -rf "$tmpdir"
    return 1
  fi
  yazi_binary="$(find "$tmpdir" -type f -name yazi -perm /111 | head -n 1)"
  ya_binary="$(find "$tmpdir" -type f -name ya -perm /111 | head -n 1)"
  if [[ -z "$yazi_binary" || -z "$ya_binary" ]]; then
    rm -rf "$tmpdir"
    error "Could not find yazi and ya binaries in the release archive."
    return 1
  fi
  if ! run_quiet sudo install -m 0755 "$yazi_binary" /usr/local/bin/yazi \
    || ! run_quiet sudo install -m 0755 "$ya_binary" /usr/local/bin/ya; then
    rm -rf "$tmpdir"
    return 1
  fi
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

install_antigravity_desktop() {
  if command_exists antigravity || [[ -x /opt/antigravity/antigravity ]]; then
    log "Antigravity is already available."
    return
  fi

  local platform extract_dir_name
  case "$(uname -m)" in
    x86_64|amd64)
      platform="linux-x64"
      extract_dir_name="Antigravity-x64"
      ;;
    aarch64|arm64)
      platform="linux-arm"
      extract_dir_name="Antigravity-arm"
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

  local latest_prefix version execution_id url
  latest_prefix=""
  latest_prefix="$(
    curl -fsSL "https://storage.googleapis.com/storage/v1/b/antigravity-public/o?prefix=antigravity-hub/&delimiter=/" 2>/dev/null \
    | jq -r '.prefixes[]?' \
    | sort -V \
    | tail -n 1
  )" || true

  if [[ -z "$latest_prefix" ]]; then
    warn "Antigravity release info not available (upstream listing is no longer public), skipping."
    return
  fi

  local version_spec
  version_spec="${latest_prefix#antigravity-hub/}"
  version_spec="${version_spec%/}"
  version="${version_spec%-*}"
  execution_id="${version_spec#*-}"

  url="https://storage.googleapis.com/antigravity-public/antigravity-hub/${version}-${execution_id}/${platform}/Antigravity.tar.gz"

  local archive app_dir bin_path desktop_file desktop_tmp extract_dir
  archive="/tmp/Antigravity.tar.gz"
  app_dir="/opt/antigravity"
  bin_path="/usr/local/bin/antigravity"
  desktop_file="/usr/local/share/applications/antigravity.desktop"
  desktop_tmp="$(mktemp)"
  extract_dir="$(mktemp -d)"

  download_file "$url" "$archive" || {
    warn "Antigravity download failed (404?), skipping."
    rm -rf "$archive" "$desktop_tmp" "$extract_dir"
    return
  }
  run_quiet tar -xzf "$archive" -C "$extract_dir"
  run_quiet sudo install -d /opt /usr/local/share/applications
  sudo rm -rf "$app_dir"
  run_quiet sudo mv "$extract_dir/$extract_dir_name" "$app_dir"
  run_quiet sudo ln -sf "$app_dir/antigravity" "$bin_path"

  local icon_file="/usr/local/share/pixmaps/antigravity.webp"
  run_quiet sudo install -d /usr/local/share/pixmaps
  run_quiet sudo install -m 0644 "$ROOT_DIR/antigravity.webp" "$icon_file"

  cat > "$desktop_tmp" <<EOF
[Desktop Entry]
Type=Application
Name=Antigravity
Comment=Google Antigravity IDE
Exec=$bin_path %F
Icon=$icon_file
Terminal=false
Categories=Development;IDE;
EOF
  run_quiet sudo install -m 0644 "$desktop_tmp" "$desktop_file"

  rm -rf "$archive" "$desktop_tmp" "$extract_dir"
  success "Antigravity installed"
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
  GNOME_LOCK_PREVIOUS="$(gsettings get org.gnome.desktop.screensaver lock-enabled 2>/dev/null || true)"
  GNOME_IDLE_PREVIOUS="$(gsettings get org.gnome.desktop.session idle-delay 2>/dev/null || true)"
  GNOME_SETTINGS_CHANGED="true"
  gsettings set org.gnome.desktop.screensaver lock-enabled false
  gsettings set org.gnome.desktop.session idle-delay 0
}

cleanup() {
  if [[ "$RUNNING_GNOME" == "true" && "$GNOME_SETTINGS_CHANGED" == "true" ]]; then
    log "Restoring GNOME lock and idle settings..."
    if [[ -n "$GNOME_LOCK_PREVIOUS" ]]; then
      gsettings set org.gnome.desktop.screensaver lock-enabled "$GNOME_LOCK_PREVIOUS" || true
    fi
    if [[ -n "$GNOME_IDLE_PREVIOUS" ]]; then
      gsettings set org.gnome.desktop.session idle-delay "$GNOME_IDLE_PREVIOUS" || true
    fi
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

finish_installation() {
  log "Installation complete."
  warn "Open a new terminal to load the updated PATH and aliases."

  if [[ "$REQUIRES_REBOOT" == "true" ]]; then
    warn "Reboot the computer before using Samba/Nautilus Share. Logoff/login is not enough."
  fi
}
