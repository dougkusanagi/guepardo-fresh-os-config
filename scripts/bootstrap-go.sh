#!/usr/bin/env bash
set -Eeuo pipefail
# A temporary, checksum-verified toolchain preserves the Go picker on fresh OSes.
root="${1:?repository root}"
shift
case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo 'Unsupported Go architecture' >&2; exit 1 ;;
esac
command -v python3 >/dev/null || { echo 'Install python3 to bootstrap the Go TUI, or use explicit --profiles.' >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
download() { curl -fsSL --retry 3 --connect-timeout 20 --max-time 600 "$1" -o "$2"; }
download 'https://go.dev/dl/?mode=json' "$tmp/releases.json"
python3 - "$tmp/releases.json" "$arch" > "$tmp/asset" <<'PY'
import json, re, sys
for release in json.load(open(sys.argv[1])):
    if not release.get('stable'):
        continue
    for asset in release['files']:
        if asset['os'] == 'linux' and asset['arch'] == sys.argv[2] and asset['kind'] == 'archive':
            assert re.fullmatch(r'go[0-9.]+\.linux-(amd64|arm64)\.tar\.gz', asset['filename'])
            assert re.fullmatch(r'[0-9a-f]{64}', asset['sha256'])
            print(asset['filename'], asset['sha256'])
            sys.exit(0)
sys.exit('No stable Linux Go toolchain found')
PY
read -r filename checksum < "$tmp/asset"
echo 'Preparing temporary Go toolchain for the interactive menu...' >&2
download "https://go.dev/dl/$filename" "$tmp/go.tar.gz"
(cd "$tmp" && printf '%s  go.tar.gz\n' "$checksum" | sha256sum -c - >&2)
tar -xzf "$tmp/go.tar.gz" -C "$tmp"
(cd "$root" && "$tmp/go/bin/go" run ./cmd/guepardo --root="$root" "$@")
