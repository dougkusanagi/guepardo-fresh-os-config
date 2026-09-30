#!/usr/bin/env bash

section "Fonts"

FONT_SOURCE_DIR="$ROOT_DIR/fonts"
FONT_DEST_DIR="$TARGET_HOME/.local/share/fonts/guepardo-fresh-os-config"

if [[ ! -d "$FONT_SOURCE_DIR" ]]; then
  warn "Font directory not found: $FONT_SOURCE_DIR"
  return
fi

if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY-RUN] Would install local fonts into $FONT_DEST_DIR"
  return
fi

mkdir -p "$FONT_DEST_DIR"
while IFS= read -r -d '' font_file; do
  # A previous interrupted copy may have left the directory incomplete.
  if ! cmp -s "$font_file" "$FONT_DEST_DIR/$(basename "$font_file")"; then
    cp -f "$font_file" "$FONT_DEST_DIR/"
  fi
done < <(find "$FONT_SOURCE_DIR" -maxdepth 1 -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print0)

if command -v fc-cache >/dev/null 2>&1; then
  mkdir -p "$TARGET_HOME/.cache/fontconfig"
  run_quiet fc-cache -f
  success "Font cache refreshed"
else
  warn "fc-cache is not available. Refresh the font cache manually if needed."
fi
