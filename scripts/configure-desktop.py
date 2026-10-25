#!/usr/bin/env python3
"""Update desktop INI settings while preserving unrelated preferences."""
import configparser
import os
from pathlib import Path
import sys
import tempfile

mode, home = sys.argv[1], Path(sys.argv[2])
if mode == 'flameshot':
    destination = home / '.config/flameshot/flameshot.ini'
    section = 'General'
    values = {'showDesktopNotification': 'false', 'showAbortNotification': 'false'}
elif mode == 'onedrive-gui':
    destination = home / '.config/onedrive-gui/gui_settings'
    section = 'SETTINGS'
    values = {'autostart_enabled': 'False'}
else:
    raise SystemExit(f'Unknown settings mode: {mode}')
parser = configparser.ConfigParser(interpolation=None, strict=False)
parser.optionxform = str
parser.read(destination)
if not parser.has_section(section):
    parser.add_section(section)
for key, value in values.items():
    parser.set(section, key, value)
destination.parent.mkdir(parents=True, exist_ok=True)
fd, temporary = tempfile.mkstemp(dir=destination.parent, prefix='.guepardo-')
try:
    with os.fdopen(fd, 'w') as stream:
        parser.write(stream, space_around_delimiters=False)
    os.replace(temporary, destination)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
