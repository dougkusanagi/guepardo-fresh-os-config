#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
installer="$ROOT_DIR/scripts/install-media-agents.sh"
fail() { printf 'ERROR %s\n' "$*" >&2; exit 1; }
mkdir -p "$work_dir/biblioteca com espaços"
(cd /; bash "$installer" "$work_dir/biblioteca com espaços")
cmp "$ROOT_DIR/templates/media-library/AGENTS.md" "$work_dir/biblioteca com espaços/AGENTS.md"
bash "$installer" "$work_dir/biblioteca com espaços"
mv "$work_dir/biblioteca com espaços" "$work_dir/biblioteca movida"
bash "$installer" "$work_dir/biblioteca movida"
printf 'Notas locais\n' > "$work_dir/biblioteca movida/AGENTS.md"
if bash "$installer" "$work_dir/biblioteca movida"; then fail 'Existing notes were overwritten'; fi
[[ "$(cat "$work_dir/biblioteca movida/AGENTS.md")" == 'Notas locais' ]] || fail 'Existing notes changed'
mkdir "$work_dir/symlink"
ln -s "$work_dir/absent-target" "$work_dir/symlink/AGENTS.md"
if bash "$installer" "$work_dir/symlink"; then fail 'Symlink was accepted'; fi
[[ ! -e "$work_dir/absent-target" ]] || fail 'Symlink target was created'
if bash "$installer" "$work_dir/absent"; then fail 'Missing directory was accepted'; fi
[[ ! -e "$work_dir/absent" ]] || fail 'Missing directory was created'
if bash "$installer"; then fail 'Missing argument was accepted'; fi
if bash "$installer" ''; then fail 'Empty argument was accepted'; fi
if bash "$installer" "$work_dir" extra; then fail 'Extra argument was accepted'; fi
bash "$installer" --help
# Public installer entry points must bypass app installation and sudo.
help_output="$(GUEPARDO_BIN=/bin/false bash "$ROOT_DIR/install.sh" --helpers)"
[[ "$help_output" == *--media-agents* ]] || fail 'Helper missing from public help'
mkdir "$work_dir/public library"
GUEPARDO_BIN=/bin/false bash "$ROOT_DIR/install.sh" --media-agents "$work_dir/public library"
cmp "$ROOT_DIR/templates/media-library/AGENTS.md" "$work_dir/public library/AGENTS.md"
if bash "$ROOT_DIR/install.sh" --media-agents; then fail 'Public helper accepted missing path'; fi
if bash "$ROOT_DIR/install.sh" --media-agents "$work_dir" extra; then fail 'Public helper accepted extra args'; fi
if bash "$ROOT_DIR/install.sh" --helpers extra; then fail 'Helper help accepted extra args'; fi
printf 'Media library notes checks passed\n'
