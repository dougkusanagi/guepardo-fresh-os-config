#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'ERROR %s\n' "$*" >&2; exit 1; }
required=(
  install.sh install.ps1 go.mod cmd/guepardo/main.go scripts/run-profile.sh
  install-common/lib.sh install-common/desktop/05-fonts.sh
  install-ubuntu/lib.sh install-fedora/lib.sh
)
for path in "${required[@]}"; do
  [[ -f "$ROOT_DIR/$path" ]] || fail "Missing $path"
done
for distro in ubuntu fedora; do
  for path in terminal/00-cli.sh terminal/05-dev-tools.sh terminal/10-web-stack.sh desktop/00-core.sh desktop/05-warp.sh desktop/10-apps.sh games/00-core.sh games/10-apps.sh network.sh; do
    [[ -f "$ROOT_DIR/install-$distro/$path" ]] || fail "Missing install-$distro/$path"
  done
done
[[ -x "$ROOT_DIR/install.sh" ]] || fail 'install.sh is not executable'
grep -Fq 'GUEPARDO_REF:-stable' "$ROOT_DIR/install.sh" || fail 'bootstrap must fetch stable by default'
grep -Fq 'SHA256SUMS' "$ROOT_DIR/install.sh" || fail 'release binary must be checksum verified'
grep -Fq 'GUEPARDO_SUDO_NONINTERACTIVE=1' "$ROOT_DIR/cmd/guepardo/main.go" || fail 'child installers must use sudo -n'
printf 'Project structure checks passed\n'
