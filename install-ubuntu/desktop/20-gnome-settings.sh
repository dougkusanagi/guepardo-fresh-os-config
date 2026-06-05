#!/usr/bin/env bash

section "GNOME Tweaks"
log "Configuring Flameshot as the primary Print Screen tool..."
if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY-RUN] Would configure Flameshot as the primary Print Screen tool and screenshot portal permission"
  return
fi

set_gsettings_key_if_exists() {
  local schema="$1"
  local key="$2"
  local value="$3"

  if gsettings list-keys "$schema" 2>/dev/null | grep -Fxq "$key" 2>/dev/null; then
    gsettings set "$schema" "$key" "$value"
  fi
}

enable_gnome_extension() {
  local uuid="$1"
  if command_exists gnome-extensions; then
    gnome-extensions enable "$uuid" 2>/dev/null || true
  fi

  local current new_ext
  current="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null)" || current="@as []"
  if [[ "$current" != *"$uuid"* ]]; then
    if [[ "$current" == "@as []" || "$current" == "[]" ]]; then
      new_ext="['$uuid']"
    else
      new_ext="${current%]}"
      new_ext="${new_ext%, }"
      new_ext="${new_ext}, '$uuid']"
    fi
    gsettings set org.gnome.shell enabled-extensions "$new_ext" 2>/dev/null || true
  fi
}

set_screenshot_portal_permission() {
  local app_id="$1"

  if command_exists flatpak; then
    if flatpak permission-set screenshot screenshot "$app_id" yes; then
      return
    fi

    warn "flatpak could not set screenshot portal permission for $app_id; trying DBus directly"
  fi

  if command_exists busctl && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    if busctl --user call \
      org.freedesktop.impl.portal.PermissionStore \
      /org/freedesktop/impl/portal/PermissionStore \
      org.freedesktop.impl.portal.PermissionStore \
      SetPermission sbssas screenshot true screenshot "$app_id" 1 yes; then
      return
    fi
  fi

  warn "Could not configure screenshot portal permission for $app_id; no flatpak or user DBus busctl available"
}

existing_bindings="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)"
target_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-flameshot/"

set_gsettings_key_if_exists org.gnome.settings-daemon.plugins.media-keys screenshot "[]"
set_gsettings_key_if_exists org.gnome.settings-daemon.plugins.media-keys screenshot-clip "[]"
set_gsettings_key_if_exists org.gnome.settings-daemon.plugins.media-keys area-screenshot "[]"
set_gsettings_key_if_exists org.gnome.settings-daemon.plugins.media-keys area-screenshot-clip "[]"
set_gsettings_key_if_exists org.gnome.settings-daemon.plugins.media-keys window-screenshot "[]"
set_gsettings_key_if_exists org.gnome.settings-daemon.plugins.media-keys window-screenshot-clip "[]"

if [[ "$existing_bindings" != *"$target_path"* ]]; then
  if [[ "$existing_bindings" == "[]" || "$existing_bindings" == "@as []" ]]; then
    new_bindings="['$target_path']"
  else
    new_bindings="${existing_bindings%]}"
    new_bindings="${new_bindings}, '$target_path']"
  fi

  gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$new_bindings"
fi

gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$target_path name 'PrintScrn'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$target_path command 'flameshot gui'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$target_path binding 'Print'

set_screenshot_portal_permission org.flameshot.Flameshot
set_screenshot_portal_permission flameshot

success "Flameshot configured as the primary Print Screen tool"

log "Enabling Dash to Dock..."
sudo glib-compile-schemas /usr/share/glib-2.0/schemas/ 2>/dev/null || true
enable_gnome_extension dash-to-dock@micxgx.gmail.com
enable_gnome_extension dash-to-dock@dashdock.org
enable_gnome_extension ubuntu-dock@ubuntu.com

log "Configuring Dash to Dock..."
set_gsettings_key_if_exists org.gnome.shell.extensions.dash-to-dock show-apps-at-top true
set_gsettings_key_if_exists org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 30
set_gsettings_key_if_exists org.gnome.shell.extensions.dash-to-dock extend-height true
set_gsettings_key_if_exists org.gnome.shell.extensions.dash-to-dock dock-fixed true
set_gsettings_key_if_exists org.gnome.shell.extensions.dash-to-dock intellihide false
set_gsettings_key_if_exists org.gnome.shell.extensions.dash-to-dock autohide false

set_gsettings_key_if_exists org.gnome.shell.extensions.ubuntu-dock show-apps-at-top true
set_gsettings_key_if_exists org.gnome.shell.extensions.ubuntu-dock dash-max-icon-size 30
set_gsettings_key_if_exists org.gnome.shell.extensions.ubuntu-dock extend-height true
set_gsettings_key_if_exists org.gnome.shell.extensions.ubuntu-dock dock-fixed true
set_gsettings_key_if_exists org.gnome.shell.extensions.ubuntu-dock intellihide false
set_gsettings_key_if_exists org.gnome.shell.extensions.ubuntu-dock autohide false

success "Dash to Dock configured"
