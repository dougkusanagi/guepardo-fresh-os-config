#!/usr/bin/env bash
# Install compatible, on-disk extensions before persisting their enabled state.
install_ego_extension() (
  local uuid="$1" shell_version info url tmp destination
  shell_version="$(gnome-shell --version | grep -oE '[0-9]+' | head -1)" || return 1
  info="$(curl -fsSL --retry 3 --connect-timeout 20 --max-time 60 "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$shell_version")" || return 1
  url="$(printf '%s' "$info" | jq -er --arg uuid "$uuid" --arg version "$shell_version" 'select(.uuid == $uuid) | select(.shell_version_map[$version] != null) | .download_url')" || {
    error "No compatible extension $uuid for GNOME $shell_version"; return 1;
  }
  [[ "$url" == /download-extension/* ]] || return 1
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  download_file "https://extensions.gnome.org$url" "$tmp/extension.zip" || return 1
  unzip -q "$tmp/extension.zip" -d "$tmp/extension" || return 1
  jq -e --arg uuid "$uuid" --arg version "$shell_version" '.uuid == $uuid and (."shell-version" | index($version) != null)' "$tmp/extension/metadata.json" >/dev/null || return 1
  if [[ -d "$tmp/extension/schemas" ]]; then glib-compile-schemas --strict "$tmp/extension/schemas" || return 1; fi
  destination="${XDG_DATA_HOME:-$TARGET_HOME/.local/share}/gnome-shell/extensions/$uuid"
  mkdir -p "$destination"
  cp -a "$tmp/extension/." "$destination/" || return 1
)

persist_gnome_extension() {
  local uuid="$1" enabled disabled
  enabled="$(gsettings get org.gnome.shell enabled-extensions)" || return 1
  disabled="$(gsettings get org.gnome.shell disabled-extensions)" || return 1
  local new_enabled new_disabled
  new_enabled="$(python3 - "$enabled" "$uuid" <<'PY'
import ast, sys
values = ast.literal_eval(sys.argv[1].removeprefix('@as').strip())
print(repr(list(dict.fromkeys(values + [sys.argv[2]]))))
PY
)" || return 1
  new_disabled="$(python3 - "$disabled" "$uuid" <<'PY'
import ast, sys
print(repr([x for x in ast.literal_eval(sys.argv[1].removeprefix('@as').strip()) if x != sys.argv[2]]))
PY
)" || return 1
  gsettings set org.gnome.shell disabled-extensions "$new_disabled" || return 1
  gsettings set org.gnome.shell enabled-extensions "$new_enabled" || return 1
  gsettings set org.gnome.shell disable-user-extensions false || return 1
  GNOME_SETTINGS_MODIFIED=true
  gnome-extensions enable "$uuid" 2>/dev/null || warn "$uuid installed and enabled for next login; log out and back in."
}

configure_multimonitor_panels() {
  local uuid=multi-monitors-bar@frederykabryan schema_dir shell_version
  install_ego_extension "$uuid" || return 1
  schema_dir="${XDG_DATA_HOME:-$TARGET_HOME/.local/share}/gnome-shell/extensions/$uuid/schemas"
  shell_version="$(gnome-shell --version | grep -oE '[0-9]+' | head -1)" || return 1
  # GNOME 50 removed AppDisplay grid.setGridModes. Keep additional panels,
  # but disable the extension's incompatible overview before enabling it.
  if ((shell_version >= 50)); then
    GSETTINGS_SCHEMA_DIR="$schema_dir" set_gsettings_if_different org.gnome.shell.extensions.multi-monitors-bar show-overview-on-extended-monitors false || return 1
  fi
  for key in show-panel show-date-time show-app-indicators; do
    GSETTINGS_SCHEMA_DIR="$schema_dir" set_gsettings_if_different org.gnome.shell.extensions.multi-monitors-bar "$key" true || return 1
  done
  persist_gnome_extension "$uuid" || return 1
}

install_ai_quota_pulse() {
  local destination="$TARGET_HOME/.local/share/guepardo/sources/ai-quota-pulse-gnome" uuid=ai-usage@guepardosys shell_version
  if [[ "$DISTRO" == ubuntu ]]; then
    apt_install git make libglib2.0-bin gir1.2-soup-3.0 gir1.2-secret-1 python3
  else
    dnf_install git make glib2 libsoup3 libsecret python3
  fi
  install_source_checkout dougkusanagi/ai-quota-pulse-gnome "$destination" || return 1
  shell_version="$(gnome-shell --version | grep -oE '[0-9]+' | head -1)"
  jq -e --arg version "$shell_version" '."shell-version" | index($version) != null' "$destination/$uuid/metadata.json" >/dev/null || {
    error "AI Quota Pulse does not support GNOME $shell_version"; return 1;
  }
  run_quiet make -C "$destination" install "EXTENSIONS_DIR=${XDG_DATA_HOME:-$TARGET_HOME/.local/share}/gnome-shell/extensions" || return 1
  persist_gnome_extension "$uuid"
}
