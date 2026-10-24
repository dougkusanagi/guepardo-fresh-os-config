#!/usr/bin/env bash
# Shared application installers. Called by both distro families.

install_source_checkout() {
  local repo="$1" destination="$2"
  if [[ -d "$destination/.git" ]]; then
    [[ "$(git -C "$destination" remote get-url origin)" == "https://github.com/$repo.git" ]] || {
      error "Unexpected repository at $destination; preserving existing files."; return 1;
    }
    run_quiet git -C "$destination" pull --ff-only || return 1
  elif [[ -e "$destination" ]]; then
    error "Directory already exists: $destination; preserving existing files."
    return 1
  else
    mkdir -p "$(dirname "$destination")"
    run_quiet git clone --depth=1 "https://github.com/$repo.git" "$destination" || return 1
  fi
}

install_dotagents() {
  local destination="$TARGET_HOME/.local/share/guepardo/sources/dotagents"
  if [[ "$DRY_RUN" == true ]]; then
    log '[DRY-RUN] Would install dotagents and sync agent rules (with upstream backups)'
    return
  fi
  if [[ "$DISTRO" == ubuntu ]]; then apt_install git; else dnf_install git; fi
  install_source_checkout dougkusanagi/dotagents "$destination" || return 1
  mkdir -p "$TARGET_HOME/.codex" "$TARGET_HOME/.claude"
  run_quiet bash "$destination/install.sh" || return 1
  run_quiet bash "$destination/bin/sync"
}

install_release_appimage() {
  local repo="$1" name="$2" pattern="$3" url destination existing extracted
  if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] Would install $name AppImage from $repo"
    return
  fi
  if existing="$(python3 "$ROOT_DIR/scripts/app-launcher.py" find "$TARGET_HOME" "$name")"; then
    log "$name desktop entry already installed: $existing"
    return
  fi
  destination="$TARGET_HOME/.local/share/guepardo/apps/$name.AppImage"
  if [[ ! -x "$destination" ]]; then
    url="$(github_latest_asset_url "$repo" "$pattern")" || {
      error "No compatible public release for $name ($repo)."; return 1;
    }
    download_file "$url" "$destination" || return 1
    chmod +x "$destination"
  fi
  mkdir -p "$TARGET_HOME/.local/bin" "$TARGET_HOME/.local/share/applications"
  # Read the upstream identity and icon rather than inventing another app.
  extracted="$(mktemp -d)"
  if ! (cd "$extracted" && "$destination" --appimage-extract >/dev/null) \
    || ! python3 "$ROOT_DIR/scripts/app-launcher.py" integrate "$TARGET_HOME" "$name" "$extracted/squashfs-root"; then
    rm -rf "$extracted"
    error "Could not integrate $name AppImage desktop entry."
    return 1
  fi
  rm -rf "$extracted"
  printf '#!/bin/sh\nAPPIMAGE_EXTRACT_AND_RUN=1 exec "%s" "$@"\n' "$destination" > "$TARGET_HOME/.local/bin/$name"
  chmod +x "$TARGET_HOME/.local/bin/$name"
}

install_sloth_note() {
  if command_exists sloth-note; then log "Sloth Note is already installed."; return; fi
  if [[ "$DRY_RUN" == true ]]; then
    log '[DRY-RUN] Would install Sloth Note release or build source with Bun/Rust/Tauri dependencies'
    return
  fi
  if github_latest_asset_url dougkusanagi/sloth-noter '.*(amd64|x86_64).*\.AppImage$' >/dev/null; then
    install_release_appimage dougkusanagi/sloth-noter sloth-note '.*(amd64|x86_64).*\.AppImage$'
    return
  fi
  warn 'Sloth Note has no public Linux release; building source (may take several minutes).'
  if [[ "$DISTRO" == ubuntu ]]; then
    apt_install git build-essential libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev libxdo-dev libssl-dev patchelf || return 1
  else
    dnf_install git gcc gcc-c++ make webkit2gtk4.1-devel libappindicator-gtk3-devel librsvg2-devel libxdo-devel openssl-devel patchelf || return 1
  fi
  install_node_lts || return 1
  if ! command_exists bun; then install_remote_script https://bun.sh/install || return 1; fi
  ensure_cargo || return 1
  local destination="$TARGET_HOME/.local/share/guepardo/sources/sloth-noter"
  install_source_checkout dougkusanagi/sloth-noter "$destination" || return 1
  (cd "$destination" && run_quiet bun install --frozen-lockfile && run_quiet bun run desktop:build --no-bundle) || return 1
  mkdir -p "$TARGET_HOME/.local/bin" "$TARGET_HOME/.local/share/applications"
  install -m755 "$destination/src-tauri/target/release/sloth-note" "$TARGET_HOME/.local/bin/sloth-note" || return 1
  cat > "$TARGET_HOME/.local/share/applications/sloth-note.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Sloth Note
Exec="$TARGET_HOME/.local/bin/sloth-note" %F
Terminal=false
Categories=Office;Utility;
MimeType=text/markdown;text/plain;
DESKTOP
}

install_ai_desktop_apps() {
  configure_user_path
  run_app "T3 Code" install_release_appimage pingdotgg/t3code t3-code '^T3-Code-.*-x86_64\.AppImage$'
  run_app "Sloth Note" install_sloth_note
  run_app "Claude Desktop" install_claude_desktop
  run_app "ChatGPT" install_web_app chatgpt ChatGPT https://chatgpt.com
  run_app "OneDriveGUI" install_onedrive_gui
}

install_claude_desktop() {
  if [[ "$DISTRO" == ubuntu ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      log '[DRY-RUN] Would install Claude Desktop from the official Anthropic APT repository'
    else
      download_file https://downloads.claude.ai/claude-desktop/key.asc "$TARGET_HOME/.cache/guepardo/claude-key.asc" || return 1
      sudo install -Dm644 "$TARGET_HOME/.cache/guepardo/claude-key.asc" /usr/share/keyrings/claude-desktop-archive-keyring.asc
      echo 'deb [signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main' | sudo tee /etc/apt/sources.list.d/claude-desktop.list >/dev/null
      apt_update --force
      apt_install claude-desktop
    fi
  else
    install_web_app claude Claude https://claude.ai
    warn 'Claude Desktop upstream supports Debian/Ubuntu; installed Claude web app on Fedora/Nobara.'
  fi
}

install_web_app() {
  local id="$1" name="$2" url="$3"
  if [[ "$DRY_RUN" == true ]]; then log "[DRY-RUN] Would install $name Chrome web app ($url)"; return; fi
  local existing
  if existing="$(python3 "$ROOT_DIR/scripts/app-launcher.py" find "$TARGET_HOME" "$id")"; then
    log "$name desktop entry already installed: $existing"
    return
  fi
  mkdir -p "$TARGET_HOME/.local/share/applications"
  cat > "$TARGET_HOME/.local/share/applications/$id.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$name
Exec=google-chrome --app=$url --class=$id
Icon=google-chrome
StartupWMClass=$id
Terminal=false
Categories=Office;Network;
DESKTOP
}

ensure_cargo() {
  export PATH="$TARGET_HOME/.cargo/bin:$PATH"
  if ! command_exists cargo || ! command_exists rustc; then
    install_remote_script https://sh.rustup.rs sh -y --profile minimal || return 1
  fi
  command_exists cargo && command_exists rustc || { error 'Cargo/Rust unavailable after installation.'; return 1; }
  run_quiet cargo --version || return 1
  run_quiet rustc --version
}

install_vite_plus() {
  if command_exists vp; then log 'Vite+ (vp) is already installed.'; return; fi
  if [[ "$DRY_RUN" == true ]]; then log '[DRY-RUN] Would install global Vite+ CLI (vp)'; return; fi
  # Use the upstream standalone global CLI, not the project-local npm package.
  VP_HOME="$TARGET_HOME/.vite-plus" VP_NODE_MANAGER=no VP_PM_MANAGER=no \
    install_remote_script https://vite.plus bash || return 1
  export PATH="$TARGET_HOME/.vite-plus/bin:$PATH"
  add_line_if_missing 'export PATH="$HOME/.vite-plus/bin:$PATH"' "$TARGET_HOME/.bashrc"
  command_exists vp || { error 'Vite+ installer did not provide vp.'; return 1; }
  run_quiet vp --version
}

install_onedrive_gui() {
  if [[ "$DRY_RUN" == true ]]; then
    log '[DRY-RUN] Would install OneDrive sync client + OneDriveGUI and enable GUI autostart (sign-in required)'
    return
  fi
  if [[ "$DISTRO" == ubuntu ]]; then
    local version_id repo key_dir
    version_id="$(. /etc/os-release; printf '%s' "${UBUNTU_VERSION_ID:-$VERSION_ID}")"
    [[ "$version_id" =~ ^[0-9]+\.[0-9]+$ ]] || { error 'Cannot detect Ubuntu version for OneDrive repository.'; return 1; }
    repo="https://download.opensuse.org/repositories/home:/npreining:/debian-ubuntu-onedrive/xUbuntu_$version_id"
    key_dir="$(mktemp -d)"
    if ! download_file "$repo/Release.key" "$key_dir/key.asc" \
      || ! gpg --batch --yes --dearmor -o "$key_dir/key.gpg" "$key_dir/key.asc"; then
      rm -rf "$key_dir"; error "OneDrive repository unavailable for Ubuntu $version_id."; return 1
    fi
    sudo install -Dm644 "$key_dir/key.gpg" /usr/share/keyrings/obs-onedrive.gpg || { rm -rf "$key_dir"; return 1; }
    rm -rf "$key_dir"
    printf 'deb [signed-by=/usr/share/keyrings/obs-onedrive.gpg] %s/ ./\n' "$repo" | sudo tee /etc/apt/sources.list.d/onedrive.list >/dev/null || return 1
    apt_update --force || return 1
    apt_install python3 || return 1
    run_quiet sudo env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 install --no-install-recommends --no-install-suggests -y onedrive || return 1
  else
    dnf_install onedrive python3 || return 1
    run_quiet sudo dnf upgrade -y onedrive || return 1
  fi
  local installed_version
  installed_version="$(onedrive --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  [[ -n "$installed_version" && "$(printf '%s\n' 2.5.11 "$installed_version" | sort -V | head -1)" == 2.5.11 ]] || {
    error 'OneDriveGUI requires OneDrive client >= 2.5.11.'; return 1;
  }
  install_release_appimage bpozdena/OneDriveGUI onedrive-gui '^OneDriveGUI-.*-x86_64\.AppImage$' || return 1
  python3 "$ROOT_DIR/scripts/configure-desktop.py" onedrive-gui "$TARGET_HOME" || return 1
  install_user_autostart_entry OneDriveGUI "\"$TARGET_HOME/.local/bin/onedrive-gui\"" onedrive 'OneDrive synchronization GUI' || return 1
  warn 'Open OneDriveGUI to sign in and choose folders. Enable auto-sync for each desired account in its profile settings.'
}

install_zapfast() {
  install_release_appimage crmne/zapfast zapfast '^zapfast-.*-x86_64\.AppImage$' || return 1
  # Migrate only after the replacement is installed. Keep the old app's data.
  if [[ "$DRY_RUN" == true ]]; then
    log '[DRY-RUN] Would remove the obsolete Whatsie Flatpak, preserving its user data'
  elif command_exists flatpak && flatpak info --system com.ktechpit.whatsie >/dev/null 2>&1; then
    run_quiet sudo flatpak uninstall -y --system com.ktechpit.whatsie || return 1
  fi
  if [[ "$DRY_RUN" != true ]] && command_exists flatpak && flatpak info --user com.ktechpit.whatsie >/dev/null 2>&1; then
    run_quiet flatpak uninstall -y --user com.ktechpit.whatsie || return 1
  fi
}

configure_flameshot_notifications() {
  if [[ "$DRY_RUN" == true ]]; then log '[DRY-RUN] Would disable Flameshot desktop and abort notifications'; return; fi
  python3 "$ROOT_DIR/scripts/configure-desktop.py" flameshot "$TARGET_HOME" || return 1
  if [[ "${RUNNING_GNOME:-false}" == true ]]; then
    local app_id
    for app_id in org-flameshot-flameshot flameshot; do
      gsettings set "org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/$app_id/" enable false || return 1
    done
  fi
}
