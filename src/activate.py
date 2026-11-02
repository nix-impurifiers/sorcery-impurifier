#!/usr/bin/python3
# SPDX-License-Identifier: MIT
"""Check native runtime minimums before touching the shared profile."""
import os
from pathlib import Path
import re
import sys


def main():
    for key in ('ROOT', 'DESTDIR', 'INSTALL_ROOT', 'STATE_ROOT', 'TRACK_ROOT'):
        if os.environ.get(key, '/') not in ('', '/'):
            raise ValueError('activation requires the live host root')
    args = sys.argv[1:]
    mode = args.pop(0) if args and args[0] in ('activate', 'remove') else 'activate'
    if any(root not in ('', '/') for root in args):
        raise ValueError('activation requires live install/state roots')
    if mode == 'remove':
        # Sorcery dispels the old spell during prepare_install. Reconcile at
        # FINAL instead, preserving the previous generation and upgrade state.
        pid = os.getppid()
        seen = set()
        while pid > 1 and pid not in seen:
            seen.add(pid)
            try:
                command = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
                if any(Path(os.fsdecode(arg)).name == 'cast' or (os.fsdecode(arg) == os.environ.get('SAFE_CAST') and Path(os.fsdecode(arg)).name == 'casting_safe') for arg in command[:3] if arg):
                    return
                pid = int(Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[1])
            except (OSError, ValueError, IndexError):
                break
    base = Path('/usr/share/sorcery-impurifier')
    current = base.joinpath('runtime-version').read_text().strip()
    requirements = [p.read_text().strip() for p in base.joinpath('requirements').glob('*')]
    for value in [current, *requirements]:
        if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*', value):
            raise ValueError('invalid native runtime version')
    if any(tuple(map(int, current.split('.'))) < tuple(map(int, minimum.split('.'))) for minimum in requirements):
        raise ValueError('native runtime is too old; upgrade sorcery-impurifier')
    os.execv('/usr/sbin/nix-profile-engine', ['nix-profile-engine', 'reconcile'])


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        print('sorcery-impurifier: ' + str(error), file=sys.stderr)
        sys.exit(1)
