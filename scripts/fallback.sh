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
doctor=false
yes=false

usage() {
  cat <<'HELP'
Usage: ./install.sh --profiles=cli,dev,web,desktop,games,fonts,network|all [--plan|--dry-run|--doctor] [--yes]
Options: --distro=auto|ubuntu|fedora|nobara --jobs=1..8 --theme=NAME --mode=full|basic|games|wsl
HELP
}

select_profiles_interactive() {
  local -a names=('CLI e servidor' 'Desenvolvimento' 'Stack web' 'Desktop' 'Jogos' 'Fontes' 'Rede IPv4' 'Todos')
  local -a keys=(cli dev web desktop games fonts network)
  local -a checked=(0 0 0 0 0 0 0)
  local active=0 key sequence direction i count all mark cursor wsl=0 total=7
  local -a linux_checked=(0 0 0 0 0 0 0) wsl_checked=(1 1 1 0 0 0 0)
  local accent='' muted='' reset='' focused='' selected_color=''
  if [[ -z "${NO_COLOR:-}" ]]; then
    accent=$'\e[1;38;2;167;139;250m'; muted=$'\e[38;2;148;163;184m'; reset=$'\e[0m'
    focused=$'\e[1;38;2;237;233;254;48;2;49;41;70m'; selected_color=$'\e[38;2;110;231;183m'
  fi
  if [[ -n "${WSL_DISTRO_NAME:-}${WSL_INTEROP:-}" ]] || [[ "$(cat /proc/sys/kernel/osrelease 2>/dev/null)" == *[Mm]icrosoft* ]]; then
    wsl=1; checked=(1 1 1 0 0 0 0)
  fi
  trap 'printf "\033[?25h\033[?1049l"; exit 130' INT
  trap 'printf "\033[?25h\033[?1049l"; exit 143' TERM
  printf '\033[?1049h\033[?25l'
  while true; do
    printf '\033[H\033[2J\n   %sguepardo%s  /  prepare seu próximo ambiente\n\n' "$accent" "$reset"
    if ((wsl)); then
      printf '   %sLinux%s     %s[ WSL ]%s     Tab / W trocar\n' "$muted" "$reset" "$accent" "$reset"
      printf '   Ferramentas para o Ubuntu dentro do Windows.\n\n'
    else
      printf '   %s[ Linux ]%s     %sWSL%s     Tab / W trocar\n' "$accent" "$reset" "$muted" "$reset"
      printf '   Escolha o que quer ter pronto neste computador.\n\n'
    fi
    total=7
    ((wsl)) && total=3
    count=0
    all=1
    for ((i=0; i<total; i++)); do
      ((checked[i])) && ((count+=1)) || all=0
    done
    for ((i=0; i<=total; i++)); do
      mark='○'; cursor=' '
      if ((i==total)); then
        ((all)) && mark=●
      elif ((checked[i])); then
        mark=●
      fi
      ((i==active)) && cursor='▸'
      local style="$reset"
      [[ "$mark" == ● ]] && style="$selected_color"
      ((i==active)) && style="$focused"
      printf '   %s %s  %d  %s  %-23s %s\n' "$style" "$cursor" "$((i+1))" "$mark" "$([[ "$i" == "$total" ]] && printf Todos || printf '%s' "${names[i]}")" "$reset"
    done
    printf '\n   %s%d módulos selecionados%s   Enter continuar\n' "$accent" "$count" "$reset"
    printf '   ↑↓ navegar · Espaço / 1–%d selecionar · Q sair\n' "$((total+1))"
    if ((wsl)); then
      printf '   Todos inclui apenas CLI, desenvolvimento e stack web.\n'
    elif ((checked[6])); then
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
      [wW]|$'\t')
        if ((wsl)); then
          wsl_checked=("${checked[@]}"); checked=("${linux_checked[@]}"); wsl=0
        else
          linux_checked=("${checked[@]}"); checked=("${wsl_checked[@]}"); wsl=1
        fi
        active=0 ;;
      ' ')
        if ((active==total)); then
          for ((i=0; i<total; i++)); do checked[i]=$((1-all)); done
        else
          checked[active]=$((1-checked[active]))
        fi ;;
      [1-8])
        ((key <= total+1)) || continue
        active=$((key-1))
        if ((active==total)); then
          for ((i=0; i<total; i++)); do checked[i]=$((1-all)); done
        else
          checked[active]=$((1-checked[active]))
        fi ;;
      [aA])
        active=$total
        for ((i=0; i<total; i++)); do checked[i]=$((1-all)); done ;;
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
          A) active=$(((active+total)%(total+1))) ;;
          B) active=$(((active+1)%(total+1))) ;;
        esac ;;
    esac
  done
  printf '\033[?25h\033[?1049l'
  trap - INT TERM
  profiles=''
  for ((i=0; i<total; i++)); do
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
    --doctor) doctor=true ;;
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
if [[ -z "$profiles" && "$doctor" == true ]]; then profiles=cli; fi
if [[ -z "$profiles" ]]; then
  if [[ -t 0 && "$yes" == false ]]; then
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

# Normalize, validate, expand aliases and deduplicate in the same order as Go.
profiles="${profiles,,}"
IFS=, read -r -a requested <<< "$profiles"
expanded=''
for candidate in "${requested[@]}"; do
  candidate="${candidate#"${candidate%%[![:space:]]*}"}"
  candidate="${candidate%"${candidate##*[![:space:]]}"}"
  case "$candidate" in
    cli|dev|web|desktop|games|fonts|network) ;;
    server) candidate=cli ;;
    basic|wsl) candidate=cli,dev,web ;;
    full) candidate=cli,dev,web,desktop,games,fonts ;;
    all|todos) candidate=cli,dev,web,desktop,games,fonts,network ;;
    dev-web) candidate=dev,web ;;
    *) echo "Unknown profile: $candidate" >&2; exit 1 ;;
  esac
  expanded+="${expanded:+,}$candidate"
done
selected=()
profiles=''
for candidate in cli dev web desktop games fonts network; do
  if [[ ",$expanded," == *",$candidate,"* ]]; then
    selected+=("$candidate")
    profiles+="${profiles:+,}$candidate"
  fi
done
((${#selected[@]} > 0)) || { echo 'Select at least one profile.' >&2; exit 1; }
if [[ -n "$theme" && ",$profiles," != *',desktop,'* ]]; then
  echo '--theme requires desktop.' >&2
  exit 1
fi
if [[ -n "$theme" ]]; then
  supported="$(sed -n '/^SUPPORTED_THEMES=(/,/^)/p' "$ROOT_DIR/install-common/lib.sh" | sed -n 's/^  "\(.*\)"/\1/p')"
  printf '%s\n' "$supported" | grep -Fxq "$theme" || { echo "Unknown theme: $theme" >&2; exit 1; }
fi
valid_ipv4() {
  local value="$1" octet
  [[ "$value" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  local -a octets
  IFS=. read -r -a octets <<< "$value"
  for octet in "${octets[@]}"; do
    [[ "$octet" == 0 || "$octet" != 0* ]] || return 1
    ((10#$octet <= 255)) || return 1
  done
}
if [[ ",$profiles," == *',network,'* && "$plan" == false && "$dry_run" == false && "$doctor" == false ]]; then
  if [[ -t 0 && "$yes" == false ]]; then
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
  [[ "$network_address" == */* ]] && valid_ipv4 "${network_address%/*}" \
    && [[ "${network_address##*/}" =~ ^([0-9]|[12][0-9]|3[0-2])$ ]] \
    || { echo '--network-address must be a valid IPv4/CIDR.' >&2; exit 1; }
  valid_ipv4 "$network_gateway" || { echo '--network-gateway must be a valid IPv4.' >&2; exit 1; }
  [[ -z "$network_dns" ]] || valid_ipv4 "$network_dns" || { echo '--network-dns must be a valid IPv4.' >&2; exit 1; }
fi

if $doctor || { ! $plan && ! $dry_run; }; then
  bash "$ROOT_DIR/scripts/preflight.sh" "$distro" "$(IFS=,; echo "${selected[*]}")" "$ROOT_DIR"
  if $doctor; then exit 0; fi
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
if [[ ! -t 0 && "$yes" == false && "$dry_run" == false ]]; then
  echo 'Use --yes to authorize a non-interactive installation.' >&2
  exit 1
fi
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
trap 'exit 130' INT
trap 'exit 143' TERM
log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/guepardo/logs"
mkdir -p "$log_dir"
log_file="$log_dir/install-$(date +%Y%m%d-%H%M%S)-$$.log"
(umask 077; touch "$log_file")
printf '\nLog: %s\n' "$log_file"
if ! $dry_run && [[ "${selected[*]}" != fonts ]]; then
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
  if GUEPARDO_ROOT="$ROOT_DIR" GUEPARDO_DRY_RUN="$dry_run" GUEPARDO_SUDO_NONINTERACTIVE=1 GUEPARDO_JOBS="$jobs" GUEPARDO_INDEX_MARKER="$index_cache_dir/updated" SELECTED_THEME="$theme" \
    STATIC_NETWORK_INTERFACE="$network_interface" STATIC_NETWORK_ADDRESS="$network_address" STATIC_NETWORK_GATEWAY="$network_gateway" STATIC_NETWORK_DNS="$network_dns" \
      bash "$ROOT_DIR/scripts/run-profile.sh" "$distro" "$candidate" 2>&1 | tee -a "$log_file"; then
    :
  else
    printf '\nERROR Profile %s failed. Log: %s\nRepeat the same command after fixing the error; installed apps are reused.\n' "$candidate" "$log_file" >&2
    exit 1
  fi
done
printf '\nInstallation complete. Log: %s\n' "$log_file"
