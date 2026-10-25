#!/usr/bin/env bash
# Sourced by install-common/lib.sh so tests and callers can replace curl.
guepardo_download() (
  set -Eeuo pipefail
  umask 077
  local url="${1:?URL required}" destination="${2:?destination required}" expected="${3:-}"
  local cache="${GUEPARDO_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/guepardo/downloads}"
  local max_age="${GUEPARDO_CACHE_MAX_AGE:-86400}" now key file partial actual timestamp lock tries=0
  [[ "$url" == https://* || "$url" == http://127.0.0.1:*/* || "$url" == http://localhost:*/* ]] || { error 'Downloads require HTTPS'; return 1; }
  [[ -z "$expected" || "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || { error 'Invalid SHA256'; return 1; }
  [[ "$max_age" =~ ^[0-9]+$ ]] || { error 'Invalid cache age'; return 1; }
  key="$(printf '%s|%s' "$url" "${expected,,}" | sha256sum | cut -d ' ' -f 1)"
  mkdir -p "$cache" "$(dirname "$destination")" || return 1
  file="$cache/$key"; partial="$file.part"; lock="$file.lock"
  until mkdir "$lock" 2>/dev/null; do
    if [[ -f "$lock/pid" ]]; then
      local owner="$(cat "$lock/pid")"
      if [[ "$owner" =~ ^[0-9]+$ ]] && ! kill -0 "$owner" 2>/dev/null; then
        rm -f "$lock/pid"; rmdir "$lock" 2>/dev/null || true
        continue
      fi
    elif ((tries > 3)); then
      rmdir "$lock" 2>/dev/null || true
    fi
    tries=$((tries+1)); ((tries < 120)) || { error "Download cache locked: $url"; return 1; }
    sleep 1
  done
  printf '%s\n' "$BASHPID" > "$lock/pid"
  trap 'rm -f "$lock/pid"; rmdir "$lock" 2>/dev/null || true' EXIT
  now="$(date +%s)"
  if [[ -f "$file" && -f "$file.sha256" && -f "$file.time" ]]; then
    actual="$(sha256sum "$file" | cut -d ' ' -f 1)"
    timestamp="$(cat "$file.time")"
    if [[ "$actual" == "$(cat "$file.sha256")" && "$timestamp" =~ ^[0-9]+$ ]] &&
       { [[ -n "$expected" && "$actual" == "${expected,,}" ]] || [[ -z "$expected" && $((now-timestamp)) -lt "$max_age" ]]; }; then
      cp "$file" "${destination}.guepardo-tmp" && mv -f "${destination}.guepardo-tmp" "$destination"
      return
    fi
  fi
  # Only content pinned to an upstream digest can safely resume across attempts.
  [[ -n "$expected" ]] || rm -f "$partial"
  local attempt status=1
  for attempt in 1 2 3; do
    local -a args=(-fsSL --connect-timeout 20 --max-time "${GUEPARDO_DOWNLOAD_TIMEOUT:-600}" --speed-time 45 --speed-limit 1024)
    [[ "$url" != https://* ]] || args+=(--proto '=https' --proto-redir '=https')
    [[ ! -f "$partial" || -z "$expected" ]] || args+=(--continue-at -)
    if curl "${args[@]}" "$url" -o "$partial"; then
      actual="$(sha256sum "$partial" | cut -d ' ' -f 1)"
      if [[ -n "$expected" && "$actual" != "${expected,,}" ]]; then
        error "SHA256 mismatch: $url"; rm -f "$partial"; status=1
      else
        mv -f "$partial" "$file" || return 1
        printf '%s\n' "$actual" > "$file.sha256"
        printf '%s\n' "$now" > "$file.time"
        cp "$file" "${destination}.guepardo-tmp" && mv -f "${destination}.guepardo-tmp" "$destination"
        return
      fi
    else
      status=$?
      case "$status" in 22|33|36) rm -f "$partial" ;; esac
      [[ -n "$expected" ]] || rm -f "$partial"
    fi
    ((attempt == 3)) || sleep "$attempt"
  done
  error "Download failed ($status): $url. A verified partial download can be resumed."
  return 1
)
