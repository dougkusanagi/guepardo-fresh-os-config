#!/usr/bin/env bash

section "Fonts"

FONT_SOURCE_DIR="$ROOT_DIR/fonts"
FONT_DEST_DIR="$TARGET_HOME/.local/share/fonts/new-linux-fresh-config"

if [[ ! -d "$FONT_SOURCE_DIR" ]]; then
  warn "Font directory not found: $FONT_SOURCE_DIR"
  return
fi

if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY-RUN] Would install local fonts into $FONT_DEST_DIR"
  return
fi

if [[ -d "$FONT_DEST_DIR" ]]; then
  log "Fonts already installed, skipping copy."
else
  mkdir -p "$FONT_DEST_DIR"

  while IFS= read -r -d '' font_file; do
    cp -f "$font_file" "$FONT_DEST_DIR/"
  done < <(find "$FONT_SOURCE_DIR" -maxdepth 1 -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print0)
fi

if command -v fc-cache >/dev/null 2>&1; then
  mkdir -p "$TARGET_HOME/.cache/fontconfig"
  run_quiet fc-cache -f
  success "Font cache refreshed"
else
  warn "fc-cache is not available. Refresh the font cache manually if needed."
fi
