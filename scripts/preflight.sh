#!/usr/bin/env bash
set -Eeuo pipefail
distro="${1:?missing distro}"
profiles="${2:?missing profiles}"
root="${3:?missing repository root}"

failed=0
require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'ERROR Ferramenta necessária ausente: %s\n' "$1" >&2
    failed=1
  fi
}
for tool in bash curl tar sha256sum sha384sum mktemp awk sort find uname tee; do require_command "$tool"; done
if [[ "$profiles" != fonts ]]; then
  require_command sudo
  case "$distro" in
    ubuntu) for tool in apt-get apt-cache dpkg-query; do require_command "$tool"; done ;;
    fedora) for tool in dnf rpm; do require_command "$tool"; done ;;
    *) printf 'ERROR Distribuição não suportada: %s\n' "$distro" >&2; exit 1 ;;
  esac
fi
case "$(uname -m)" in
  x86_64|amd64) ;;
  aarch64|arm64)
    if [[ ",$profiles," == *',desktop,'* || ",$profiles," == *',games,'* ]]; then
      printf 'ERROR Os perfis desktop e games incluem apps disponíveis apenas para x86_64. Use cli,dev,web,fonts em ARM64.\n' >&2
      failed=1
    fi ;;
  *) printf 'ERROR Arquitetura não suportada: %s\n' "$(uname -m)" >&2; failed=1 ;;
esac
if [[ ! -d "$HOME" || ! -w "$HOME" ]]; then
  printf 'ERROR Diretório pessoal sem permissão de escrita: %s\n' "$HOME" >&2
  failed=1
fi
files=(scripts/run-profile.sh install-common/lib.sh "install-$distro/lib.sh")
IFS=, read -r -a selected <<< "$profiles"
for profile in "${selected[@]}"; do
  case "$profile" in
    cli) files+=("install-$distro/terminal/00-cli.sh") ;;
    dev) files+=("install-$distro/terminal/05-dev-tools.sh") ;;
    web) files+=("install-$distro/terminal/10-web-stack.sh") ;;
    desktop) files+=("install-$distro/desktop/00-core.sh" "install-$distro/desktop/05-warp.sh" "install-$distro/desktop/10-apps.sh" install-common/desktop/20-gnome-settings.sh) ;;
    games) files+=("install-$distro/games/00-core.sh" "install-$distro/games/10-apps.sh") ;;
    fonts) files+=(install-common/desktop/05-fonts.sh) ;;
    network) files+=("install-$distro/network.sh") ;;
  esac
done
for file in "${files[@]}"; do
  if [[ ! -r "$root/$file" ]]; then
    printf 'ERROR Arquivo do instalador ausente: %s\n' "$root/$file" >&2
    failed=1
  fi
done
(( failed == 0 )) || exit 1
printf 'OK Verificação inicial concluída: %s / %s. Nenhum pacote foi instalado.\n' "$distro" "$profiles"
