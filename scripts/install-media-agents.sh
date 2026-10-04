#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
usage() { printf 'Uso: bash scripts/install-media-agents.sh /caminho/da/biblioteca\n'; }
if [[ "$#" == 1 && ( "$1" == --help || "$1" == -h ) ]]; then
  usage
  exit 0
fi
if [[ "$#" != 1 || -z "$1" ]]; then
  usage >&2
  exit 1
fi
library_dir="$1"
[[ -d "$library_dir" ]] || { printf 'Pasta da biblioteca não existe: %s\n' "$library_dir" >&2; exit 1; }
source_file="$ROOT_DIR/templates/media-library/AGENTS.md"
target_file="$library_dir/AGENTS.md"
if [[ -e "$target_file" || -L "$target_file" ]]; then
  if [[ ! -L "$target_file" && -f "$target_file" ]] && cmp -s "$source_file" "$target_file"; then
    printf 'AGENTS.md já está atualizado: %s\n' "$target_file"
    exit 0
  fi
  printf 'AGENTS.md já existe; revise e combine as notas manualmente: %s\n' "$target_file" >&2
  exit 1
fi
# noclobber also protects a file created between the check and the write.
(set -o noclobber; cat "$source_file" > "$target_file")
printf 'AGENTS.md instalado: %s\n' "$target_file"
