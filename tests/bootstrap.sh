#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
fail() { printf 'ERROR %s\n' "$*" >&2; exit 1; }
repo="$sandbox/repo"
mkdir -p "$repo"/{scripts,cmd,install-common,install-ubuntu,install-fedora} "$sandbox/bin" "$sandbox/release"
cp "$ROOT_DIR/install.sh" "$repo/install.sh"
cp "$ROOT_DIR/scripts/source-digest.sh" "$repo/scripts/source-digest.sh"
printf 'module bootstrap.test\n' > "$repo/go.mod"
touch "$repo/go.sum" "$repo/install-common/lib.sh"
cat > "$repo/scripts/fallback.sh" <<'SH'
#!/usr/bin/env bash
printf 'fallback %s\n' "$*" >> "$GUEPARDO_TEST_CALLS"
SH
chmod +x "$repo/scripts/fallback.sh"
cat > "$sandbox/bin/go" <<'SH'
#!/usr/bin/env bash
echo 'go version go1.18.0 linux/amd64'
SH
cat > "$sandbox/bin/curl" <<'SH'
#!/usr/bin/env bash
set -eu
while (($#)); do
  case "$1" in
    -o) destination="$2"; shift ;;
    https://*) url="$1" ;;
  esac
  shift
done
printf '%s\n' "$url" >> "$GUEPARDO_TEST_URLS"
if [[ "$url" == *codeload.github.com* ]]; then
  cp "$GUEPARDO_TEST_ARCHIVE" "$destination"
else
  file="$GUEPARDO_TEST_RELEASE/${url##*/}"
  [[ -f "$file" ]] || exit 22
  cp "$file" "$destination"
fi
SH
chmod +x "$sandbox/bin/"*
export PATH="$sandbox/bin:$PATH" GUEPARDO_TEST_CALLS="$sandbox/calls" GUEPARDO_TEST_URLS="$sandbox/urls" GUEPARDO_TEST_RELEASE="$sandbox/release"
unset GUEPARDO_BIN
case "$(uname -m)" in x86_64|amd64) asset=guepardo-linux-amd64 ;; *) asset=guepardo-linux-arm64 ;; esac
cat > "$sandbox/release/$asset" <<'SH'
#!/usr/bin/env bash
printf 'binary %s\n' "$*" >> "$GUEPARDO_TEST_CALLS"
SH
refresh_release() {
  bash "$repo/scripts/source-digest.sh" "$repo" > "$sandbox/release/SOURCE_SHA256"
  (cd "$sandbox/release" && sha256sum "$asset" SOURCE_SHA256 > SHA256SUMS)
  : > "$sandbox/calls"
  : > "$sandbox/urls"
}
refresh_release
bash "$repo/install.sh" --list-profiles >/dev/null
[[ "$(cat "$sandbox/calls")" == binary*'--list-profiles' ]] || fail 'Compatible binary was not used'

# A newer release must never orchestrate older scripts from another branch.
printf 'different source\n' > "$sandbox/release/SOURCE_SHA256"
(cd "$sandbox/release" && sha256sum "$asset" SOURCE_SHA256 > SHA256SUMS)
: > "$sandbox/calls"
bash "$repo/install.sh" --list-profiles >/dev/null 2>&1
[[ "$(cat "$sandbox/calls")" == 'fallback --list-profiles' ]] || fail 'Source mismatch did not use fallback'

# Neither corrupted artifacts nor missing checksums can execute a binary.
refresh_release
printf 'corrupted\n' >> "$sandbox/release/$asset"
if bash "$repo/install.sh" --list-profiles >/dev/null 2>&1; then fail 'Corrupt binary was accepted'; fi
[[ ! -s "$sandbox/calls" ]] || fail 'Corrupt binary was executed'
refresh_release
sed -i "/  $asset$/d" "$sandbox/release/SHA256SUMS"
if bash "$repo/install.sh" --list-profiles >/dev/null 2>&1; then fail 'Missing checksum was accepted'; fi
[[ ! -s "$sandbox/calls" ]] || fail 'Unverified binary was executed'

# Remote archives may be branches containing slashes, tags or commits. Their
# top-level directory must not be derived from the caller's ref string.
mkdir -p "$sandbox/remote"
cp "$ROOT_DIR/install.sh" "$sandbox/remote/install.sh"
tar -czf "$sandbox/archive.tar.gz" -C "$sandbox" repo
export GUEPARDO_REF=feature/test GUEPARDO_TEST_ARCHIVE="$sandbox/archive.tar.gz" GUEPARDO_BIN="$repo/scripts/fallback.sh"
: > "$sandbox/calls"
bash "$sandbox/remote/install.sh" --plan >/dev/null 2>&1
[[ "$(cat "$sandbox/calls")" == *'--root='*'/repository --plan' ]] || fail 'Remote archive did not preserve the root and arguments'
[[ "$(cat "$sandbox/urls")" == *'/tar.gz/feature/test'* ]] || fail 'Remote branch ref was not used'
# Execute the exact README one-liner with downloads/sudo mocked: a fresh WSL
# must never receive the desktop/games full preset, and the temp file is removed.
mkdir -p "$sandbox/readme-bin"
cat > "$sandbox/readme-bin/sudo" <<'SH'
#!/bin/bash
exit 0
SH
cat > "$sandbox/readme-bin/grep" <<'SH'
#!/bin/bash
# Simulate the non-WSL Linux kernel regardless of the test host.
exit 1
SH
cat > "$sandbox/readme-bin/curl" <<'SH'
#!/bin/bash
while (($#)); do
  if [[ "$1" == -o ]]; then
    printf '%s\n' "$2" > "$GUEPARDO_TEST_DOWNLOAD_PATH"
    cat > "$2" <<'INSTALLER'
#!/bin/bash
printf '%s\n' "$*" > "$GUEPARDO_TEST_README_ARGS"
INSTALLER
    exit 0
  fi
  shift
done
exit 1
SH
chmod +x "$sandbox/readme-bin/"*
readme_command="$(sed -n '/^bash -c /{p;q;}' "$ROOT_DIR/README.md")"
[[ -n "$readme_command" ]] || fail 'README is missing its recommended command'
for environment in linux wsl interop; do
  distro_name='' interop=''
  [[ "$environment" == wsl ]] && distro_name=Ubuntu
  [[ "$environment" == interop ]] && interop=/run/WSL/interop
  WSL_DISTRO_NAME="$distro_name" WSL_INTEROP="$interop" \
    GUEPARDO_TEST_README_ARGS="$sandbox/readme-args" GUEPARDO_TEST_DOWNLOAD_PATH="$sandbox/readme-download" \
    PATH="$sandbox/readme-bin:$PATH" bash -c "$readme_command"
  expected='--mode=wsl --yes'
  [[ "$environment" == linux ]] && expected='--mode=full --yes'
  [[ "$(cat "$sandbox/readme-args")" == "$expected" ]] || fail "README selected the wrong preset for $environment"
  [[ ! -e "$(cat "$sandbox/readme-download")" ]] || fail 'README download was not cleaned up'
done
printf 'Bootstrap checks passed\n'
