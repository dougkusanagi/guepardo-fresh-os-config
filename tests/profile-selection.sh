#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
fail() { printf 'ERROR %s\n' "$*" >&2; exit 1; }

server="$(go run ./cmd/guepardo --distro=ubuntu --profiles=cli --plan)"
[[ "$server" == *'1/1  cli'* ]] || fail 'CLI plan must contain only CLI'
[[ "$server" != *'  desktop   '* && "$server" != *'  games     '* ]] || fail 'CLI plan includes graphical profiles'

games="$(go run ./cmd/guepardo --distro=fedora --profiles=games --plan)"
[[ "$games" == *'1/1  games'* ]] || fail 'Games plan must contain only games'
[[ "$games" != *'  web       '* && "$games" != *'  dev       '* ]] || fail 'Games plan includes development profiles'

if go run ./cmd/guepardo --distro=ubuntu --profiles=cli --theme=nord --plan >/dev/null 2>&1; then
  fail 'Theme without desktop was accepted'
fi
if go run ./cmd/guepardo --distro=ubuntu --profiles=cli --jobs=0 --plan >/dev/null 2>&1; then
  fail 'Invalid concurrency was accepted'
fi
if go run ./cmd/guepardo --distro=ubuntu --profiles=network --yes --network-interface=enp1s0 --network-address=invalid --network-gateway=192.168.1.1 >/dev/null 2>&1; then
  fail 'Invalid static network address was accepted'
fi

# Both installers must start before the first is allowed to finish.
source "$ROOT_DIR/install-common/lib.sh"
marker="$(mktemp)"
rm -f "$marker"
first() {
  for _ in $(seq 1 50); do
    [[ -f "$marker" ]] && return 0
    sleep 0.01
  done
  return 1
}
second() { touch "$marker"; }
GUEPARDO_JOBS=2 run_independent first second || fail 'Independent installers did not overlap'
rm -f "$marker"
if GUEPARDO_JOBS=1 run_independent first second; then
  fail 'Sequential mode did not wait for the first installer'
fi
rm -f "$marker"

# Reuse a package index within one installation, but refresh after a new repo.
source "$ROOT_DIR/install-ubuntu/lib.sh"
DRY_RUN=false
index_dir="$(mktemp -d)"
GUEPARDO_INDEX_MARKER="$index_dir/updated"
calls="$(mktemp)"
run_quiet() { printf '%s\n' "$*" >> "$calls"; }
apt_update >/dev/null
apt_update >/dev/null
[[ "$(wc -l < "$calls")" == 1 ]] || fail 'APT index was refreshed twice without repository changes'
apt_update --force >/dev/null
[[ "$(wc -l < "$calls")" == 2 ]] || fail 'APT index was not refreshed after a repository change'
rm -rf "$index_dir" "$calls"

source "$ROOT_DIR/install-fedora/lib.sh"
index_dir="$(mktemp -d)"
GUEPARDO_INDEX_MARKER="$index_dir/updated"
calls="$(mktemp)"
dnf_update >/dev/null
dnf_update >/dev/null
[[ "$(wc -l < "$calls")" == 1 ]] || fail 'DNF index was refreshed twice without repository changes'
dnf_update --force >/dev/null
[[ "$(wc -l < "$calls")" == 2 ]] || fail 'DNF index was not refreshed after a repository change'
rm -rf "$index_dir" "$calls"

# The sudo shim must reach both sourced Bash code and nested POSIX sh scripts.
fake_root="$(mktemp -d)"
mkdir -p "$fake_root/install-common" "$fake_root/install-ubuntu/terminal" "$fake_root/fake-bin"
printf 'cleanup() { :; }\n' > "$fake_root/install-common/lib.sh"
: > "$fake_root/install-ubuntu/lib.sh"
printf 'sudo -v\nsh -c "sudo -v"\n' > "$fake_root/install-ubuntu/terminal/00-cli.sh"
cat > "$fake_root/fake-bin/sudo" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$GUEPARDO_SUDO_CALLS"
SH
chmod +x "$fake_root/fake-bin/sudo"
GUEPARDO_SUDO_CALLS="$fake_root/sudo-calls" GUEPARDO_ROOT="$fake_root" GUEPARDO_SUDO_NONINTERACTIVE=1 \
  PATH="$fake_root/fake-bin:$PATH" bash "$ROOT_DIR/scripts/run-profile.sh" ubuntu cli
[[ "$(grep -c '^-n -v$' "$fake_root/sudo-calls")" == 2 ]] || fail 'Nested shell sudo could ask for a password'
rm -rf "$fake_root"
printf 'Profile selection checks passed\n'
