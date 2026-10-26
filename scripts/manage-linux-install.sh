#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
distro="${1:?Distribuição ausente}"; shift
[[ "$distro" == ubuntu || "$distro" == fedora ]] || exit 64
[[ "$(id -u)" != 0 ]] || { echo 'Execute manage.sh como usuário normal, sem sudo.' >&2; exit 1; }
state="${XDG_STATE_HOME:-$HOME/.local/state}/guepardo"
mkdir -p "$state/logs"
exec 9> "$state/manage.lock"
flock -n 9 || { echo 'Outro gerenciador está instalando aplicativos. Aguarde a conclusão.' >&2; exit 1; }
logfile="$state/logs/manage-$(date +%Y%m%d-%H%M%S)-$$.log"
echo "Log: $logfile"
exec > >(tee -a "$logfile") 2>&1
export DRY_RUN=false GUEPARDO_CURRENT_PROFILE=manage
source "$root/install-common/lib.sh"
source "$root/install-$distro/lib.sh"
trap cleanup EXIT
sudo -v
export GUEPARDO_FAILURES_FILE="$state/manage-failures-$$.txt"
: > "$GUEPARDO_FAILURES_FILE"
argv_file="$(mktemp)"
trap 'rm -f -- "$argv_file"; cleanup' EXIT
# A normal user session is retained for all per-user installers.
if [[ "$distro" == ubuntu ]]; then apt_update; apt_install curl ca-certificates tar unzip jq gpg xz-utils
else dnf_update; dnf_install curl ca-certificates tar unzip jq gnupg2 xz; fi
for id in "$@"; do
  python3 "$root/scripts/manage-linux.py" --recipe "$distro" "$id" > "$argv_file"
  mapfile -d '' -t action < "$argv_file"
  [[ ${#action[@]} -gt 1 ]] || exit 64
  IFS=',' read -r -a dependencies <<< "${action[0]}"
  action=("${action[@]:1}")
  blocked=false
  for dependency in "${dependencies[@]}"; do
    if grep -Fq "$dependency (" "$GUEPARDO_FAILURES_FILE"; then blocked=true; fi
  done
  if [[ "$blocked" == true ]]; then echo "$id (dependência com falha)" >> "$GUEPARDO_FAILURES_FILE"; continue; fi
  if [[ "${action[0]}" =~ ^(flatpak_install_app|install_obsidian|install_lutris)$ ]] && ! command -v flatpak >/dev/null; then
    if [[ "$distro" == ubuntu ]]; then apt_install flatpak; else dnf_install flatpak; fi
  fi
  if [[ "${action[0]}" =~ ^(flatpak_install_app|install_obsidian|install_lutris)$ ]]; then
    sudo flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
  run_app "$id" "${action[@]}"
done
if [[ -s "$GUEPARDO_FAILURES_FILE" ]]; then
  echo 'Aplicativos com falha:'; cat "$GUEPARDO_FAILURES_FILE"; exit 1
fi
echo 'Etapas executadas. Conferindo os aplicativos instalados...'
