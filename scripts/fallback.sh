#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profiles=""
mode=""
distro="auto"
jobs=4
theme=""
network_interface=""
network_address=""
network_gateway=""
network_dns=""
plan=false
dry_run=false
yes=false

usage() {
  cat <<'HELP'
Usage: ./install.sh --profiles=cli,dev,web,desktop,games,fonts,network|all [--plan|--dry-run] [--yes]
Options: --distro=auto|ubuntu|fedora|nobara --jobs=1..8 --theme=NAME --mode=full|basic|games|wsl
HELP
}

select_profiles_interactive() {
  local -a names=('CLI e servidor' 'Desenvolvimento' 'Stack web' 'Desktop' 'Jogos' 'Fontes' 'Rede IPv4' 'Todos')
  local -a keys=(cli dev web desktop games fonts network)
  local -a checked=(0 0 0 0 0 0 0)
  local active=0 key sequence direction i count all mark cursor
  trap 'printf "\033[?25h\033[?1049l"; exit 130' INT
  trap 'printf "\033[?25h\033[?1049l"; exit 143' TERM
  printf '\033[?1049h\033[?25l'
  while true; do
    printf '\033[H\033[2J  GUEPARDO  /  Escolha os perfis\n'
    printf '  ↑↓ navegar  ·  Espaço ou 1–8 marcar  ·  Enter continuar\n\n'
    count=0
    all=1
    for ((i=0; i<7; i++)); do
      ((checked[i])) && ((count+=1)) || all=0
    done
    for ((i=0; i<8; i++)); do
      mark=' '; cursor=' '
      if ((i==7)); then
        ((all)) && mark=x
      elif ((checked[i])); then
        mark=x
      fi
      ((i==active)) && cursor='>'
      printf '  %s [%s] %d  %s\n' "$cursor" "$mark" "$((i+1))" "${names[i]}"
    done
    printf '\n  %d perfis selecionados · 8 marca todos · Q cancela\n' "$count"
    if ((checked[6])); then
      printf '  Rede altera a conexão; os dados IPv4 serão solicitados.\n'
    else
      printf '  Rede altera a conexão; escolha apenas se precisar.\n'
    fi
    if ! IFS= read -rsn1 key; then
      printf '\033[?25h\033[?1049l'
      trap - INT TERM
      return 1
    fi
    case "$key" in
      '')
        if ((count>0)); then break; fi
        ;;
      ' ')
        if ((active==7)); then
          for ((i=0; i<7; i++)); do checked[i]=$((1-all)); done
        else
          checked[active]=$((1-checked[active]))
        fi ;;
      [1-8])
        active=$((key-1))
        if ((active==7)); then
          for ((i=0; i<7; i++)); do checked[i]=$((1-all)); done
        else
          checked[active]=$((1-checked[active]))
        fi ;;
      [aA])
        active=7
        for ((i=0; i<7; i++)); do checked[i]=$((1-all)); done ;;
      [qQ])
        printf '\033[?25h\033[?1049l'
        trap - INT TERM
        return 1 ;;
      $'\e')
        IFS= read -rsn2 sequence || true
        if [[ "$sequence" == '[' ]]; then
          IFS= read -rsn1 direction || true
        else
          direction="${sequence:1:1}"
        fi
        case "$direction" in
          A) active=$(((active+7)%8)) ;;
          B) active=$(((active+1)%8)) ;;
        esac ;;
    esac
  done
  printf '\033[?25h\033[?1049l'
  trap - INT TERM
  profiles=''
  for ((i=0; i<7; i++)); do
    if ((checked[i])); then profiles+="${profiles:+,}${keys[i]}"; fi
  done
}

for arg in "$@"; do
  case "$arg" in
    --profiles=*) profiles="${arg#*=}" ;;
    --mode=*) mode="${arg#*=}" ;;
    --distro=*) distro="${arg#*=}" ;;
    --jobs=*) jobs="${arg#*=}" ;;
    --theme=*) theme="${arg#*=}" ;;
    --network-interface=*) network_interface="${arg#*=}" ;;
    --network-address=*) network_address="${arg#*=}" ;;
    --network-gateway=*) network_gateway="${arg#*=}" ;;
    --network-dns=*) network_dns="${arg#*=}" ;;
    --plan) plan=true ;;
    --dry-run) dry_run=true ;;
    --yes) yes=true ;;
    --list-profiles) printf '%s\n' cli dev web desktop games fonts network; exit 0 ;;
    --list-themes)
      sed -n '/^SUPPORTED_THEMES=(/,/^)/p' "$ROOT_DIR/install-common/lib.sh" | sed -n 's/^  "\(.*\)"/\1/p'
      exit 0 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -z "$profiles" || -z "$mode" ]] || { echo 'Use --profiles or --mode, not both.' >&2; exit 1; }
if [[ -n "$mode" ]]; then profiles="$mode"; fi
if [[ -z "$profiles" ]]; then
  if [[ -t 0 ]]; then
    select_profiles_interactive || { echo 'Seleção cancelada.' >&2; exit 1; }
  else
    echo 'Use --profiles=cli or another profile in non-interactive mode.' >&2
    exit 1
  fi
fi
case "$profiles" in
  server) profiles=cli ;;
  basic|wsl) profiles=cli,dev,web ;;
  full) profiles=cli,dev,web,desktop,games,fonts ;;
  all|todos) profiles=cli,dev,web,desktop,games,fonts,network ;;
esac
[[ "$jobs" =~ ^[1-8]$ ]] || { echo '--jobs must be between 1 and 8.' >&2; exit 1; }

case "$distro" in
  ubuntu|debian) distro=ubuntu ;;
  fedora|nobara) distro=fedora ;;
  auto)
    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ "${ID:-}" == ubuntu || "${ID:-}" == debian || " ${ID_LIKE:-} " == *' debian '* ]]; then
      distro=ubuntu
    elif [[ "${ID:-}" == fedora || "${ID:-}" == nobara || " ${ID_LIKE:-} " == *' fedora '* ]]; then
      distro=fedora
    else
      echo "Unsupported distro: ${ID:-unknown}" >&2
      exit 1
    fi ;;
  *) echo "Unsupported distro: $distro" >&2; exit 1 ;;
esac

selected=()
for candidate in cli dev web desktop games fonts network; do
  if [[ ",$profiles," == *",$candidate,"* ]]; then selected+=("$candidate"); fi
done
# Catch typos rather than silently omitting unknown profiles.
IFS=, read -r -a requested <<< "$profiles"
for candidate in "${requested[@]}"; do
  case "$candidate" in cli|dev|web|desktop|games|fonts|network) ;; *) echo "Unknown profile: $candidate" >&2; exit 1 ;; esac
done
((${#selected[@]} > 0)) || { echo 'Select at least one profile.' >&2; exit 1; }
if [[ -n "$theme" && ",$profiles," != *',desktop,'* ]]; then
  echo '--theme requires desktop.' >&2
  exit 1
fi
if [[ ",$profiles," == *',network,'* && "$plan" == false && "$dry_run" == false ]]; then
  if [[ -t 0 ]]; then
    [[ -n "$network_interface" ]] || read -r -p 'Interface de rede (ex.: enp1s0): ' network_interface
    [[ -n "$network_address" ]] || read -r -p 'Endereço IPv4/CIDR (ex.: 192.168.1.77/24): ' network_address
    [[ -n "$network_gateway" ]] || read -r -p 'Gateway IPv4 (ex.: 192.168.1.1): ' network_gateway
    [[ -n "$network_dns" ]] || read -r -p 'DNS IPv4 [1.1.1.1]: ' network_dns
    network_dns="${network_dns:-1.1.1.1}"
  fi
  [[ -n "$network_interface" && -n "$network_address" && -n "$network_gateway" ]] || {
    echo 'network requires --network-interface, --network-address and --network-gateway.' >&2
    exit 1
  }
fi

printf '\nGUEPARDO  /  %s  /  %s\n' "$distro" "$profiles"
for candidate in "${selected[@]}"; do printf '  • %s\n' "$candidate"; done
if [[ ",$profiles," == *',network,'* ]]; then
  printf '  Network: %s %s via %s DNS %s\n' "${network_interface:-<required>}" "${network_address:-<required>}" "${network_gateway:-<required>}" "${network_dns:-1.1.1.1}"
fi
if $plan; then
  printf '\nActions planned (no changes):\n'
  for candidate in "${selected[@]}"; do
    printf '\n[%s] %s\n' "$distro" "$candidate"
    GUEPARDO_ROOT="$ROOT_DIR" GUEPARDO_DRY_RUN=true GUEPARDO_SUDO_NONINTERACTIVE=1 GUEPARDO_JOBS="$jobs" SELECTED_THEME="$theme" \
      STATIC_NETWORK_INTERFACE="$network_interface" STATIC_NETWORK_ADDRESS="$network_address" STATIC_NETWORK_GATEWAY="$network_gateway" STATIC_NETWORK_DNS="$network_dns" \
      bash "$ROOT_DIR/scripts/run-profile.sh" "$distro" "$candidate"
  done
  exit 0
fi
if (( EUID == 0 )); then echo 'Run as a regular user, without sudo.' >&2; exit 1; fi
if [[ -t 0 && "$yes" == false && "$dry_run" == false ]]; then
  read -r -p 'Start installation? [s/N]: ' answer
  [[ "${answer,,}" == s ]] || exit 0
fi

keepalive_pid=""
index_cache_dir="$(mktemp -d)"
cleanup() {
  if [[ -n "$keepalive_pid" ]]; then
    kill "$keepalive_pid" 2>/dev/null || true
    wait "$keepalive_pid" 2>/dev/null || true
  fi
  rm -rf "$index_cache_dir"
}
trap cleanup EXIT
if ! $dry_run; then
  if [[ -t 0 ]]; then
    sudo -v
  elif [[ -n "${SUDO_ASKPASS:-}" ]]; then
    sudo -A -v
  else
    sudo -n -v || { echo 'sudo needs a TTY, passwordless access, or SUDO_ASKPASS.' >&2; exit 1; }
  fi
  parent_pid="$$"
  (
    while kill -0 "$parent_pid" 2>/dev/null; do
      sleep 25
      sudo -n -v || { echo 'sudo credential expired; stopping.' >&2; kill -TERM "$parent_pid"; exit 1; }
    done
  ) &
  keepalive_pid="$!"
fi
for candidate in "${selected[@]}"; do
  printf '\n[%s] %s\n' "$distro" "$candidate"
  GUEPARDO_ROOT="$ROOT_DIR" GUEPARDO_DRY_RUN="$dry_run" GUEPARDO_SUDO_NONINTERACTIVE=1 GUEPARDO_JOBS="$jobs" GUEPARDO_INDEX_MARKER="$index_cache_dir/updated" SELECTED_THEME="$theme" \
    STATIC_NETWORK_INTERFACE="$network_interface" STATIC_NETWORK_ADDRESS="$network_address" STATIC_NETWORK_GATEWAY="$network_gateway" STATIC_NETWORK_DNS="$network_dns" \
    bash "$ROOT_DIR/scripts/run-profile.sh" "$distro" "$candidate"
done
printf '\nInstallation complete.\n'
