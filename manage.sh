#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null || { printf 'Instale python3 para consultar e selecionar aplicativos.\n' >&2; exit 1; }
exec python3 "$root/scripts/manage-linux.py" "$@"
