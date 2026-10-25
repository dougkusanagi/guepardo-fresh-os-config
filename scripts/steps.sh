#!/usr/bin/env bash
# Per-app checkpoints supplement package-manager detection, never replace it.
guepardo_verify_task() {
  local installer="${1:-}"; shift || true
  case "$installer" in
    ensure_cargo) command_exists cargo && command_exists rustc && cargo --version >/dev/null && rustc --version >/dev/null ;;
    install_node_lts) command_exists node && command_exists npm && [[ "$(node --version)" =~ ^v(22|24)\. ]] ;;
    install_npm_global_package) command_exists "${1:-__missing__}" ;;
    install_release_appimage) command_exists "${2:-__missing__}" ;;
    install_sloth_note) command_exists sloth-note ;;
    install_vite_plus) command_exists vp ;;
    *) return 2 ;; # Configuration-only steps must execute again.
  esac
}

guepardo_step_key() {
  printf '%s\0' "${GUEPARDO_CURRENT_PROFILE:-standalone}" "$@" | sha256sum | cut -d ' ' -f 1
}

guepardo_write_step() {
  local path="$1" status="$2"
  printf '%s\n' "$status" > "$path.$BASHPID.tmp" && mv -f "$path.$BASHPID.tmp" "$path"
}
