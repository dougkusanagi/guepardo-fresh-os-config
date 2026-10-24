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
  run_quiet bash "$destination/install.sh"
}

install_release_appimage() {
  local repo="$1" name="$2" pattern="$3" url destination
  if [[ -x "$TARGET_HOME/.local/bin/$name" ]]; then log "$name is already installed."; return; fi
  if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] Would install $name AppImage from $repo"
    return
  fi
  url="$(github_latest_asset_url "$repo" "$pattern")" || {
    error "No compatible public release for $name ($repo)."; return 1;
  }
  destination="$TARGET_HOME/.local/share/guepardo/apps/$name.AppImage"
  download_file "$url" "$destination" || return 1
  chmod +x "$destination"
  mkdir -p "$TARGET_HOME/.local/bin" "$TARGET_HOME/.local/share/applications"
  # Extraction avoids depending on FUSE 2 on recent distros.
  printf '#!/bin/sh\nAPPIMAGE_EXTRACT_AND_RUN=1 exec "%s" "$@"\n' "$destination" > "$TARGET_HOME/.local/bin/$name"
  chmod +x "$TARGET_HOME/.local/bin/$name"
  cat > "$TARGET_HOME/.local/share/applications/$name.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$name
Exec="$TARGET_HOME/.local/bin/$name" %U
Terminal=false
Categories=Development;Utility;
DESKTOP
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
  if ! command_exists cargo; then install_remote_script https://sh.rustup.rs sh -y || return 1; fi
  export PATH="$TARGET_HOME/.cargo/bin:$PATH"
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
  install_release_appimage pingdotgg/t3code t3-code '^T3-Code-.*-x86_64\.AppImage$' || return 1
  install_sloth_note || return 1
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
  install_web_app chatgpt ChatGPT https://chatgpt.com
}

install_web_app() {
  local id="$1" name="$2" url="$3"
  if [[ "$DRY_RUN" == true ]]; then log "[DRY-RUN] Would install $name Chrome web app ($url)"; return; fi
  mkdir -p "$TARGET_HOME/.local/share/applications"
  cat > "$TARGET_HOME/.local/share/applications/$id.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$name
Exec=google-chrome --app=$url
Terminal=false
Categories=Office;Network;
DESKTOP
}
