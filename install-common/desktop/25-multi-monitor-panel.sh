#!/usr/bin/env bash

configure_multi_monitor_panel() {
  local uuid='topbar-all-monitors@fa8i.github.io'
  local shell_version extension_dir tmpdir download_path current updated key

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install and enable Top Bar All Monitors for compatible GNOME versions"
    return
  fi

  if ! command_exists gnome-shell || ! command_exists gnome-extensions; then
    warn "GNOME Shell extension tools unavailable; skipping multi-monitor top bar"
    return
  fi
  shell_version="$(gnome-shell --version)" || return 1
  shell_version="${shell_version##* }"
  shell_version="${shell_version%%.*}"
  extension_dir="${XDG_DATA_HOME:-$TARGET_HOME/.local/share}/gnome-shell/extensions/$uuid"

  if ! jq -e --arg version "$shell_version" --arg uuid "$uuid" \
    '.uuid == $uuid and (."shell-version" | index($version) != null)' \
    "$extension_dir/metadata.json" >/dev/null 2>&1; then
    tmpdir="$(mktemp -d)" || return 1
    if ! download_file "https://extensions.gnome.org/extension-info/?pk=10094&shell_version=$shell_version" "$tmpdir/info.json"; then
      rm -rf "$tmpdir"
      warn "Could not query Top Bar All Monitors compatibility"
      return 1
    fi
    download_path="$(jq -r --arg version "$shell_version" --arg uuid "$uuid" \
      'select(.uuid == $uuid and .shell_version_map[$version] != null) | .download_url // empty' \
      "$tmpdir/info.json")" || download_path=''
    if [[ "$download_path" != /download-extension/"$uuid".shell-extension.zip\?* ]]; then
      rm -rf "$tmpdir"
      warn "Top Bar All Monitors is unavailable for GNOME $shell_version; skipping"
      return
    fi
    if ! download_file "https://extensions.gnome.org$download_path" "$tmpdir/extension.zip" || \
       ! gnome-extensions install --force "$tmpdir/extension.zip"; then
      rm -rf "$tmpdir"
      warn "Could not install Top Bar All Monitors"
      return 1
    fi
    rm -rf "$tmpdir"
  fi

  # Newly installed extensions may only be detected after the next Wayland login.
  # Persist the setting without the interactive InstallRemoteExtension dialog.
  for key in enabled-extensions disabled-extensions; do
    current="$(gsettings get org.gnome.shell "$key")" || return 1
    updated="$(python3 - "$current" "$uuid" "$key" <<'PY'
import ast
import sys
value, uuid, key = sys.argv[1:]
extensions = ast.literal_eval(value.removeprefix('@as').strip())
if key == 'enabled-extensions':
    if uuid not in extensions:
        extensions.append(uuid)
else:
    extensions = [item for item in extensions if item != uuid]
print(repr(extensions))
PY
)" || return 1
    if [[ "$current" != "$updated" ]]; then
      gsettings set org.gnome.shell "$key" "$updated" || return 1
    fi
  done
  gnome-extensions enable "$uuid" 2>/dev/null || true
  success "Top Bar All Monitors configured: clock, calendar and system controls on every monitor"
  log "If the secondary top bar is not visible yet, log out and back in. Third-party indicators may remain on the primary monitor."
}

section "Multi-monitor top bar"
configure_multi_monitor_panel
