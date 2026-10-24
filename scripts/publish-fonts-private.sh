#!/usr/bin/env bash
# Publishes the local ./fonts directory to a PRIVATE GitHub repository, which
# the `fonts` profile then clones (requires `gh auth login` on each machine).
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${1:-${GUEPARDO_FONTS_REPO:-dougkusanagi/guepardo-fonts}}"
SOURCE="${GUEPARDO_FONTS_DIR:-$ROOT_DIR/fonts}"

[[ -d "$SOURCE" ]] || { echo "Font directory not found: $SOURCE" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
gh auth status >/dev/null || { echo "Run 'gh auth login' first" >&2; exit 1; }

if gh repo view "$REPO" >/dev/null 2>&1; then
  [[ "$(gh repo view "$REPO" --json isPrivate -q .isPrivate)" == true ]] || { echo "$REPO exists and is not private; aborting" >&2; exit 1; }
else
  gh repo create "$REPO" --private --description "Private fonts for guepardo-fresh-os-config"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
gh repo clone "$REPO" "$work/repo" -- --quiet
find "$SOURCE" -maxdepth 1 -type f \( -iname '*.ttf' -o -iname '*.otf' \) -exec cp -f {} "$work/repo/" \;
git -C "$work/repo" add -A
if git -C "$work/repo" diff --cached --quiet; then
  echo "Nothing to publish."
else
  git -C "$work/repo" commit -q -m "Update fonts"
  git -C "$work/repo" push -q
  echo "Published fonts to private repository $REPO"
fi
