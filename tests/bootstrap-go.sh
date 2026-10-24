#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/bin" "$sandbox/toolchain/go/bin" "$sandbox/root with spaces"
cat > "$sandbox/toolchain/go/bin/go" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$PWD" "$@" > "$GUEPARDO_TEST_CALLS"
SH
chmod +x "$sandbox/toolchain/go/bin/go"
tar -czf "$sandbox/toolchain.tar.gz" -C "$sandbox/toolchain" go
checksum="$(sha256sum "$sandbox/toolchain.tar.gz" | cut -d' ' -f1)"
case "$(uname -m)" in x86_64|amd64) arch=amd64 ;; *) arch=arm64 ;; esac
printf '[{"stable":true,"files":[{"os":"linux","arch":"%s","kind":"archive","filename":"go1.24.0.linux-%s.tar.gz","sha256":"%s"}]}]' "$arch" "$arch" "$checksum" > "$sandbox/metadata.json"
cat > "$sandbox/bin/curl" <<'SH'
#!/usr/bin/env bash
while (($#)); do
  case "$1" in -o) destination="$2"; shift ;; https://*) url="$1" ;; esac
  shift
done
if [[ "$url" == *mode=json ]]; then cp "$GUEPARDO_TEST_SANDBOX/metadata.json" "$destination"
else cp "$GUEPARDO_TEST_SANDBOX/toolchain.tar.gz" "$destination"; fi
SH
chmod +x "$sandbox/bin/curl"
export PATH="$sandbox/bin:$PATH" GUEPARDO_TEST_SANDBOX="$sandbox" GUEPARDO_TEST_CALLS="$sandbox/calls"
bash "$root/scripts/bootstrap-go.sh" "$sandbox/root with spaces" --list-profiles >/dev/null 2>&1
grep -Fxq -- '--list-profiles' "$sandbox/calls"
grep -Fxq -- "--root=$sandbox/root with spaces" "$sandbox/calls"
rm "$sandbox/calls"
echo corrupt >> "$sandbox/toolchain.tar.gz"
if bash "$root/scripts/bootstrap-go.sh" "$sandbox/root with spaces" >/dev/null 2>&1; then echo 'Corrupt Go archive accepted' >&2; exit 1; fi
[[ ! -e "$sandbox/calls" ]]
echo 'Temporary Go toolchain verification checks passed'
