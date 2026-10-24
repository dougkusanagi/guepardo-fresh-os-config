#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export XDG_DATA_DIRS="$sandbox/system"
source "$ROOT_DIR/install-common/lib.sh"
TARGET_HOME="$sandbox/home with spaces"
DRY_RUN=false
mkdir -p "$TARGET_HOME/.local/share/applications" "$XDG_DATA_DIRS/applications"
# Native ChatGPT must take precedence over the old generated Chrome launcher.
cat > "$XDG_DATA_DIRS/applications/chatgpt.desktop" <<'EOF'
[Desktop Entry]
Name=ChatGPT
Exec=chatgpt %U
Icon=chatgpt
Type=Application
EOF
printf '[Desktop Entry]\nType=Application\nName=ChatGPT\nExec=google-chrome --app=https://chatgpt.com\nTerminal=false\nCategories=Office;Network;\n' > "$TARGET_HOME/.local/share/applications/chatgpt.desktop"
install_web_app chatgpt ChatGPT https://chatgpt.com
[[ ! -f "$TARGET_HOME/.local/share/applications/chatgpt.desktop" ]]
# Preserve an existing integrated T3 Beta, without downloading another version.
cat > "$TARGET_HOME/.local/share/applications/t3_code_beta.desktop" <<'EOF'
[Desktop Entry]
Name=T3 Code (Beta)
Exec=/existing/T3.AppImage %U
Icon=/existing/icon.png
StartupWMClass=t3code
Type=Application
EOF
# The duplicate produced by the old installer is removed, not the integrated one.
python3 - "$ROOT_DIR" "$TARGET_HOME" <<'PYTEST'
import importlib.util, pathlib, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("launcher", pathlib.Path(sys.argv[1])/"scripts/app-launcher.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
assert m.remap_favorites(["chrome.desktop", "t3-code.desktop", "t3_code_beta.desktop"], "t3-code.desktop", "t3_code_beta.desktop") == ["chrome.desktop", "t3_code_beta.desktop"]
home = pathlib.Path(sys.argv[2])
(home/".local/share/applications/t3-code.desktop").write_text(m.generic(home, "t3-code"))
PYTEST
github_latest_asset_url() { echo 'Unexpected download' >&2; return 1; }
install_release_appimage pingdotgg/t3code t3-code unused
[[ ! -e "$TARGET_HOME/.local/bin/t3-code" && ! -e "$TARGET_HOME/.local/share/applications/t3-code.desktop" ]]
# Repair the old generic ZapFast launcher from the AppImage's own metadata.
mkdir -p "$TARGET_HOME/.local/share/guepardo/apps"
cat > "$TARGET_HOME/.local/share/guepardo/apps/zapfast.AppImage" <<'EOF'
#!/bin/sh
[ "$1" = --appimage-extract ] || exit 1
mkdir -p squashfs-root
cat > squashfs-root/zapfast.desktop <<'ENTRY'
[Desktop Entry]
Type=Application
Name=ZapFast
Exec=zapfast %U
Icon=zapfast
StartupWMClass=zapfast
MimeType=x-scheme-handler/whatsapp;
Actions=quit;
[Desktop Action quit]
Name=Quit
Exec=zapfast quit
ENTRY
printf '<svg xmlns="http://www.w3.org/2000/svg"/>' > squashfs-root/zapfast.svg
EOF
chmod +x "$TARGET_HOME/.local/share/guepardo/apps/zapfast.AppImage"
install_release_appimage crmne/zapfast zapfast unused
cp "$TARGET_HOME/.local/share/applications/zapfast.desktop" "$sandbox/expected"
install_release_appimage crmne/zapfast zapfast unused
cmp "$sandbox/expected" "$TARGET_HOME/.local/share/applications/zapfast.desktop"
grep -Fxq 'StartupWMClass=zapfast' "$sandbox/expected"
grep -Fxq 'MimeType=x-scheme-handler/whatsapp;' "$sandbox/expected"
grep -Fq "Icon=$TARGET_HOME/.local/share/icons/zapfast.svg" "$sandbox/expected"
[[ -f "$TARGET_HOME/.local/share/icons/zapfast.svg" ]]
! grep -q 'Desktop Action' "$sandbox/expected"
# A custom user launcher is never overwritten.
printf '[Desktop Entry]\nType=Application\nName=ChatGPT\nExec=/custom/chatgpt\nIcon=custom\n' > "$TARGET_HOME/.local/share/applications/chatgpt.desktop"
cp "$TARGET_HOME/.local/share/applications/chatgpt.desktop" "$sandbox/custom"
install_web_app chatgpt ChatGPT https://chatgpt.com
cmp "$sandbox/custom" "$TARGET_HOME/.local/share/applications/chatgpt.desktop"
# Missing package metadata must fail without replacing an existing launcher.
mkdir -p "$sandbox/empty-appimage"
if python3 "$ROOT_DIR/scripts/app-launcher.py" integrate "$TARGET_HOME" zapfast "$sandbox/empty-appimage" 2>/dev/null; then
  echo 'Missing metadata accepted' >&2; exit 1
fi
cmp "$sandbox/expected" "$TARGET_HOME/.local/share/applications/zapfast.desktop"
echo 'Desktop launcher regression checks passed' 
