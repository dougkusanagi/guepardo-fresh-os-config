#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUESTED_DISTRO="auto"
DRY_RUN="false"
INSTALL_MODE="full"
MODE_EXPLICITLY_SET=false
INSTALL_FAMILY=""
INSTALL_ROOT=""
LOG_DIR="$ROOT_DIR/logs"
SELECTED_THEME=""
export SELECTED_THEME

if [[ -t 1 ]]; then
  COLOR_RESET=$'\033[0m'
  COLOR_BOLD=$'\033[1m'
  COLOR_DIM=$'\033[2m'
  COLOR_CYAN=$'\033[36m'
  COLOR_GREEN=$'\033[32m'
  COLOR_YELLOW=$'\033[33m'
else
  COLOR_RESET=""
  COLOR_BOLD=""
  COLOR_DIM=""
  COLOR_CYAN=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
fi

usage() {
  cat <<'EOF'
Usage:
  ./install.sh [--distro=auto|ubuntu|fedora|nobara] [--mode=full|basic] [--theme=NAME] [--list-themes] [--help]

Options:
  --distro=NAME
      Select installer family. Default: auto.

  --mode=MODE
      Installation scope: full (dev + desktop + games) or basic (dev only). Default: full.

  --dry-run
      Show what would be installed without making any changes.

  --theme=NAME
      Apply one of the Omakub-inspired themes after desktop installation.

  --list-themes
      List supported themes and exit.

  --help
      Show this help.
EOF
}

normalize_local_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

preparse_args() {
  for arg in "$@"; do
    case "$arg" in
      --distro=*)
        REQUESTED_DISTRO="$(normalize_local_name "${arg#*=}")"
        ;;
      --dry-run)
        DRY_RUN="true"
        ;;
      --mode=*)
        INSTALL_MODE="${arg#*=}"
        MODE_EXPLICITLY_SET=true
        ;;
      --help)
        usage
        exit 0
        ;;
    esac
  done
}

detect_install_family() {
  local requested="$1"

  case "$requested" in
    auto)
      ;;
    ubuntu)
      INSTALL_FAMILY="ubuntu"
      INSTALL_ROOT="$ROOT_DIR/install-ubuntu"
      return
      ;;
    fedora|nobara)
      INSTALL_FAMILY="fedora"
      INSTALL_ROOT="$ROOT_DIR/install-fedora"
      return
      ;;
    *)
      echo "Unsupported distro: $requested" >&2
      echo "Supported values: auto, ubuntu, fedora, nobara" >&2
      exit 1
      ;;
  esac

  if [[ ! -r /etc/os-release ]]; then
    echo "Could not detect distro because /etc/os-release is not readable." >&2
    echo "Retry with --distro=ubuntu, --distro=fedora, or --distro=nobara." >&2
    exit 1
  fi

  # shellcheck source=/dev/null
  source /etc/os-release

  case "${ID:-}" in
    ubuntu)
      INSTALL_FAMILY="ubuntu"
      INSTALL_ROOT="$ROOT_DIR/install-ubuntu"
      ;;
    fedora|nobara)
      INSTALL_FAMILY="fedora"
      INSTALL_ROOT="$ROOT_DIR/install-fedora"
      ;;
    *)
      if [[ " ${ID_LIKE:-} " == *" debian "* ]]; then
        INSTALL_FAMILY="ubuntu"
        INSTALL_ROOT="$ROOT_DIR/install-ubuntu"
      elif [[ " ${ID_LIKE:-} " == *" fedora "* ]]; then
        INSTALL_FAMILY="fedora"
        INSTALL_ROOT="$ROOT_DIR/install-fedora"
      else
        echo "Unsupported distro: ${PRETTY_NAME:-${ID:-unknown}}" >&2
        echo "Retry with --distro=ubuntu, --distro=fedora, or --distro=nobara if you know it is compatible." >&2
        exit 1
      fi
      ;;
  esac
}

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --distro=*)
        ;;
      --dry-run)
        ;;
      --mode=*)
        ;;
      --theme=*)
        SELECTED_THEME="$(normalize_theme_name "${arg#*=}")"
        ;;
      --list-themes)
        list_supported_themes
        exit 0
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        error "Unknown option: $arg"
        echo
        usage
        exit 1
        ;;
    esac
  done
}

show_install_intro() {
  printf "\n%s" "${COLOR_BOLD}${COLOR_CYAN}"
  cat <<'EOF'
     _   __                 __    _                      
    / | / /__ _      __    / /   (_)___  __  ___  __     
   /  |/ / _ \ | /| / /   / /   / / __ \/ / / / |/_/     
  / /|  /  __/ |/ |/ /   / /___/ / / / / /_/ />  <       
 /_/ |_/\___/|__/|__/   /_____/_/_/ /_/\__,_/_/|_|       
EOF
  printf "%s\n" "$COLOR_RESET"
  printf "%sFresh Config Installer%s\n" "${COLOR_BOLD}${COLOR_GREEN}" "$COLOR_RESET"
  printf "%sDistro target:%s %s\n" "$COLOR_YELLOW" "$COLOR_RESET" "$INSTALL_FAMILY"
  printf "%sMode:%s %s\n" "$COLOR_YELLOW" "$COLOR_RESET" "$INSTALL_MODE"
  printf "%sScope:%s terminal tools, dev stack, desktop apps and GNOME polish\n" "$COLOR_YELLOW" "$COLOR_RESET"
  printf "%sLog:%s %s\n\n" "$COLOR_DIM" "$COLOR_RESET" "$INSTALL_LOG"
}

trap 'echo "A instalacao falhou. Voce pode tentar novamente com: ./install.sh"' ERR

preparse_args "$@"
detect_install_family "$REQUESTED_DISTRO"

log_to_file() {
  local level="$1"
  local message="$2"
  if [[ -n "${INSTALL_LOG:-}" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$INSTALL_LOG"
  fi
}

export DRY_RUN
export INSTALL_MODE

# shellcheck source=/dev/null
source "$INSTALL_ROOT/lib.sh"

trap cleanup EXIT

main() {
  parse_args "$@"

  if [[ "${EUID}" -eq 0 ]]; then
    error "Execute este script com seu usuario normal, sem sudo."
    exit 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "Running in DRY-RUN mode - no changes will be made"
    echo
  fi

  mkdir -p "$LOG_DIR"
  export INSTALL_LOG="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S)-$$.log"
  log_to_file "INFO" "Installation started - $INSTALL_FAMILY"

  show_install_intro

  case "$INSTALL_MODE" in
    full|basic) ;;
    *)
      error "Invalid mode: $INSTALL_MODE. Use full or basic."
      exit 1
      ;;
  esac

  if [[ -t 0 && "$MODE_EXPLICITLY_SET" == "false" ]]; then
    local selected
    selected="$(interactive_select "Installation mode (use arrows, enter to confirm):" \
      "Full (dev + desktop + jogos)" \
      "Basic (dev tools only)")"
    case "$selected" in
      *"Basic"*) INSTALL_MODE="basic" ;;
    esac
  fi

  echo "This is a very opinionated basic dev environment with PHP, Composer, Node and many desktop apps"
  log "Selected installer family: $INSTALL_MODE"
  echo
  echo "Begin installation (or abort with ctrl+c)..."

  require_sudo
  detect_desktop

  if [[ "$RUNNING_GNOME" == "true" ]]; then
    configure_gnome_for_install
    log "Installing terminal and desktop tools..."
  else
    log "Only installing terminal tools..."
  fi

  # shellcheck source=/dev/null
  source "$INSTALL_ROOT/terminal.sh"

  if [[ "$RUNNING_GNOME" == "true" ]]; then
    # shellcheck source=/dev/null
    source "$INSTALL_ROOT/desktop.sh"
  fi

  finish_installation
}

main "$@"
