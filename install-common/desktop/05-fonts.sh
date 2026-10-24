#!/usr/bin/env bash

section "Fonts"

FONT_DEST_DIR="$TARGET_HOME/.local/share/fonts/guepardo-fresh-os-config"
FONTS_REPO="${GUEPARDO_FONTS_REPO:-dougkusanagi/guepardo-fonts}"
FONTS_CACHE_DIR="$TARGET_HOME/.cache/guepardo/fonts"

# The fonts include commercial/personal-use files, so they live in a private
# repository. Order: explicit directory, local checkout copy, private clone.
FONT_SOURCE_DIR="${GUEPARDO_FONTS_DIR:-}"
if [[ -z "$FONT_SOURCE_DIR" && -d "$ROOT_DIR/fonts" ]]; then
  FONT_SOURCE_DIR="$ROOT_DIR/fonts"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY-RUN] Would install fonts from ${FONT_SOURCE_DIR:-the private repository $FONTS_REPO} into $FONT_DEST_DIR"
  return
fi

# A fresh bootstrap checkout does not contain private fonts. Reuse this user's
# installed copy when no explicit/local source or repository cache is available.
if [[ -z "$FONT_SOURCE_DIR" && ! -d "$FONTS_CACHE_DIR/.git" && -d "$FONT_DEST_DIR" ]] \
  && [[ -n "$(find "$FONT_DEST_DIR" -maxdepth 1 -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print -quit)" ]]; then
  log "Fontes já presentes em $FONT_DEST_DIR; usando os arquivos instalados."
  return
fi

if [[ -z "$FONT_SOURCE_DIR" ]]; then
  if [[ -d "$FONTS_CACHE_DIR/.git" ]]; then
    git -C "$FONTS_CACHE_DIR" pull --ff-only --quiet \
      || warn "Could not update the private fonts repository; using the cached copy."
  else
    mkdir -p "$(dirname "$FONTS_CACHE_DIR")"
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
      gh repo clone "$FONTS_REPO" "$FONTS_CACHE_DIR" -- --depth 1 --quiet || rm -rf "$FONTS_CACHE_DIR"
    else
      git clone --depth 1 --quiet "https://github.com/$FONTS_REPO.git" "$FONTS_CACHE_DIR" || rm -rf "$FONTS_CACHE_DIR"
    fi
  fi
  if [[ ! -d "$FONTS_CACHE_DIR" ]]; then
    error "Não foi possível acessar $FONTS_REPO. Confira se o repositório existe e se sua conta tem permissão, ou informe uma pasta de fontes com GUEPARDO_FONTS_DIR."
    return 1
  fi
  FONT_SOURCE_DIR="$FONTS_CACHE_DIR"
fi

if [[ ! -d "$FONT_SOURCE_DIR" ]]; then
  error "Font directory not found: $FONT_SOURCE_DIR"
  return 1
fi

if [[ -z "$(find "$FONT_SOURCE_DIR" -maxdepth 2 -not -path '*/.git/*' -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print -quit)" ]]; then
  error "Nenhuma fonte .ttf ou .otf encontrada em $FONT_SOURCE_DIR."
  return 1
fi

mkdir -p "$FONT_DEST_DIR"
while IFS= read -r -d '' font_file; do
  # A previous interrupted copy may have left the directory incomplete.
  if ! cmp -s "$font_file" "$FONT_DEST_DIR/$(basename "$font_file")"; then
    cp -f "$font_file" "$FONT_DEST_DIR/"
  fi
done < <(find "$FONT_SOURCE_DIR" -maxdepth 2 -not -path "*/.git/*" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print0)

if command -v fc-cache >/dev/null 2>&1; then
  mkdir -p "$TARGET_HOME/.cache/fontconfig"
  run_quiet fc-cache -f
  success "Font cache refreshed"
else
  warn "fc-cache is not available. Refresh the font cache manually if needed."
fi
