#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/install-common/lib.sh"
source "$ROOT_DIR/install-ubuntu/lib.sh"
apt_update
apt_install ripgrep fzf
rg --version
fzf --version
# Running twice exercises installed-package detection without forcing reinstall.
apt_install ripgrep fzf
