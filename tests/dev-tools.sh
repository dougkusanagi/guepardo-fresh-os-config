#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'ERROR %s\n' "$*" >&2; exit 1; }
contains() { grep -Fq "$2" "$ROOT_DIR/$1" || fail "Expected $1 to contain: $2"; }
excludes() { if grep -Fq "$2" "$ROOT_DIR/$1"; then fail "Did not expect $1 to contain: $2"; fi; }
for distro in ubuntu fedora; do
  cli="install-$distro/terminal/00-cli.sh"
  dev="install-$distro/terminal/05-dev-tools.sh"
  web="install-$distro/terminal/10-web-stack.sh"
  desktop="install-$distro/desktop/10-apps.sh"
  games="install-$distro/games/10-apps.sh"
  contains "$cli" 'ripgrep'
  contains "$cli" 'run_independent'
  excludes "$cli" 'configure_static_ipv4_network'
  excludes "$cli" 'warp-terminal'
  excludes "$cli" 'mysql-server'
  contains "$dev" 'nodejs npm'
  contains "$dev" 'install_npm_global_package codex @openai/codex'
  contains "$web" 'composer'
  excludes "$web" "BY '';"
  contains "$desktop" 'install_vscode_desktop'
  excludes "$desktop" 'install_steam'
  contains "$games" 'install_steam'
  contains "$games" 'install_lutris'
  excludes "$games" 'install_vscode_desktop'
  contains "install-$distro/network.sh" 'configure_static_ipv4_network'
done
contains 'install-common/lib.sh' 'run_independent()'
contains 'scripts/run-profile.sh' 'source "$INSTALL_ROOT/games/10-apps.sh"'
contains 'scripts/run-profile.sh' 'exec "$sudo_binary" -n "\$@"'
contains 'cmd/guepardo/main.go' 'sudoSession('
contains 'cmd/guepardo/main.go' 'time.NewTicker(sudoRefreshInterval)'
printf 'Developer tool checks passed\n'
