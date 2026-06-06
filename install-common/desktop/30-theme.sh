#!/usr/bin/env bash

if [[ -n "${SELECTED_THEME:-}" ]]; then
  section "Theme"
  apply_selected_theme "$SELECTED_THEME"
fi
