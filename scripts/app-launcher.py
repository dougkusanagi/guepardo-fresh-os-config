#!/usr/bin/env python3
"""Preserve installed desktop identities and integrate AppImage metadata."""
import ast
import configparser
import os
from pathlib import Path
import re
import shutil
import sys
import subprocess


def read(path):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    parser.read(path, encoding="utf-8")
    return parser


def generic(home, name):
    return ("[Desktop Entry]\nType=Application\nName=" + name
            + '\nExec="' + str(home / ".local/bin" / name)
            + '" %U\nTerminal=false\nCategories=Development;Utility;\n')


def normalized(value):
    return re.sub(r"[^a-z0-9]", "", value.lower())


def old_web(path, name):
    if name not in ("chatgpt", "claude"):
        return False
    title, url = {"chatgpt": ("ChatGPT", "https://chatgpt.com"), "claude": ("Claude", "https://claude.ai")}[name]
    expected = f"[Desktop Entry]\nType=Application\nName={title}\nExec=google-chrome --app={url}\nTerminal=false\nCategories=Office;Network;\n"
    modern = expected.replace(f"Exec=google-chrome --app={url}\n", f"Exec=google-chrome --app={url} --class={name}\nIcon=google-chrome\nStartupWMClass={name}\n")
    return path.read_text() in (expected, modern)


def find(home, name):
    roots = [home / ".local/share"]
    roots += [Path(p) for p in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if p]
    for root in roots:
        for path in sorted((root / "applications").glob("*.desktop")):
            try:
                parser = read(path)
                entry = parser["Desktop Entry"]
                if any(entry.get(flag, "false").lower() == "true" for flag in ("Hidden", "NoDisplay")):
                    continue
                ids = [path.stem, entry.get("Name", ""), entry.get("StartupWMClass", ""), entry.get("X-AppImage-Name", "")]
                key = normalized(name)
                if not any(normalized(v) == key or (key == "t3code" and normalized(v) in ("t3codebeta", "t3codenightly", "comt3toolst3code")) for v in ids):
                    continue
                if path == home / ".local/share/applications" / (name + ".desktop") and (path.read_text() == generic(home, name) or old_web(path, name)):
                    continue
                return path
            except (OSError, UnicodeError, configparser.Error, KeyError):
                continue
    return None


def remap_favorites(values, old, new):
    result = []
    for value in values:
        value = new if value == old else value
        if value not in result:
            result.append(value)
    return result


def cleanup(home, name, replacement):
    path = home / ".local/share/applications" / (name + ".desktop")
    if path.exists() and (path.read_text() == generic(home, name) or old_web(path, name)):
        # Move a pinned generic launcher to the preserved desktop identity.
        if home == Path.home() and os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
            try:
                current = subprocess.run(["gsettings", "get", "org.gnome.shell", "favorite-apps"], check=True, capture_output=True, text=True).stdout.strip()
                values = [] if current == "@as []" else ast.literal_eval(current)
                updated = remap_favorites(values, path.name, replacement.name)
                if updated != values:
                    subprocess.run(["gsettings", "set", "org.gnome.shell", "favorite-apps", repr(updated)], check=True)
            except (OSError, ValueError, subprocess.CalledProcessError) as error:
                print(f"Could not update dock favorites: {error}", file=sys.stderr)
                return
        path.unlink()


def integrate(home, name, extracted):
    entries = sorted(extracted.glob("*.desktop"))
    if not entries:
        raise SystemExit("AppImage has no desktop entry; refusing to create an incomplete launcher")
    parser = read(entries[0])
    entry = parser["Desktop Entry"]
    entry["Exec"] = '"' + str(home / ".local/bin" / name) + '" %U'
    entry["TryExec"] = str(home / ".local/bin" / name)
    icon = entry.get("Icon", "")
    if icon:
        candidates = [extracted / icon]
        candidates += [extracted / (icon + ext) for ext in (".svg", ".png", ".xpm")]
        candidates += sorted((extracted / "usr/share/icons").rglob(Path(icon).name + ".*"))
        source = next((p for p in candidates if p.is_file()), None)
        if source is None:
            raise SystemExit("AppImage icon not found; refusing to save an incomplete launcher")
        destination = home / ".local/share/icons" / (name + source.suffix)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        entry["Icon"] = str(destination)
    else:
        raise SystemExit("AppImage desktop entry has no icon")
    # Upstream actions may reference executables unavailable outside the AppImage.
    entry.pop("Actions", None)
    for section in list(parser.sections()):
        if section.startswith("Desktop Action "):
            parser.remove_section(section)
    target = home / ".local/share/applications" / (name + ".desktop")
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("w") as stream:
        parser.write(stream, space_around_delimiters=False)


if __name__ == "__main__":
    mode, home_arg, name = sys.argv[1:4]
    home = Path(home_arg)
    if mode == "find":
        found = find(home, name)
        if found:
            cleanup(home, name, found)
            print(found)
        else:
            raise SystemExit(1)
    elif mode == "integrate":
        integrate(home, name, Path(sys.argv[4]))
    else:
        raise SystemExit("Unknown command")
