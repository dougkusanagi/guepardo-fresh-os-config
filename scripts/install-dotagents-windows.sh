#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/bin:/bin:$PATH"

case "${1:-}" in
  runtime)
    pacman -Syu --noconfirm
    ;;
  dependencies)
    pacman -Syu --noconfirm
    pacman -S --noconfirm --needed util-linux git
    ;;
  install)
    : "${GUEPARDO_DOTAGENTS_SOURCE:?dotagents source is required}"
    : "${GUEPARDO_DOTAGENTS_USER_HOME:?Windows user profile is required}"
    source_dir="$(cygpath -u -- "$GUEPARDO_DOTAGENTS_SOURCE")"
    user_home="$(cygpath -u -- "$GUEPARDO_DOTAGENTS_USER_HOME")"
    [[ -d "$user_home" && -f "$source_dir/install.sh" && -f "$source_dir/bin/sync" ]] || {
      printf 'dotagents: source checkout or Windows user profile is missing\n' >&2
      exit 64
    }
    export HOME="$user_home"
    cd -- "$source_dir"
    bash ./install.sh
    bash ./bin/sync
    ;;
  *)
    printf 'Usage: install-dotagents-windows.sh runtime|dependencies|install\n' >&2
    exit 64
    ;;
esac
