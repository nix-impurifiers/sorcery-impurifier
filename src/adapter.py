#!/usr/bin/python3
# SPDX-License-Identifier: MIT
"""Report native Sorcery and post-transaction profile activation failures."""
import os
from pathlib import Path
import re
import subprocess
import sys


def main():
    args = sys.argv[1:]
    if os.geteuid() != 0:
        raise ValueError('native Sorcery requires root')
    native_options = []
    if args[:2] == ['install', '--from']:
        if len(args) < 4 or not Path(args[2]).is_dir():
            raise ValueError('--from requires an existing native source-cache directory')
        native_options = ['--from', str(Path(args[2]).resolve())]
        args = [args[0], *args[3:]]
    if not args or any(not re.fullmatch(r'[a-z0-9][a-z0-9+._-]*', a) for a in args):
        raise ValueError('use install [--from DIRECTORY] SPELL...; remove SPELL...; or reconcile')
    config = subprocess.run(['/bin/bash', '-c', '. /etc/sorcery/config >/dev/null; printf "%s\\n" "${INSTALL_ROOT:-/}" "${STATE_ROOT:-/}" "${TRACK_ROOT:-/}" "$ACTIVITY_LOG"'], check=True, capture_output=True, text=True).stdout.splitlines()
    if len(config) != 4 or config[:3] != ['/', '/', '/']:
        raise ValueError('native Sorcery requires live install/state/tracking roots')
    status = 0
    if args[0] == 'install' and len(args) > 1:
        log = Path(config[3])
        offset = log.stat().st_size if log.exists() else 0
        status = subprocess.run(['cast', '--no-opts', '-c', *native_options, *args[1:]]).returncode
        # Native cast can report zero after dropping spells whose downloads
        # failed. Require a fresh native success record for each requested spell.
        with log.open('rb') as stream:
            stream.seek(offset)
            entries = [line.decode().rstrip('\n').split('\t') for line in stream]
        completed = {row[2].split(':')[0] for row in entries if len(row) >= 5 and row[1] == 'cast' and row[4] == 'success'}
        if not set(args[1:]).issubset(completed):
            print('sorcery-impurifier: native cast did not complete every requested spell', file=sys.stderr)
            status = status or 1
    elif args[0] == 'remove' and len(args) > 1:
        status = subprocess.run(['dispel', *args[1:]]).returncode
        query = subprocess.run(['/bin/bash', '-c', '. /etc/sorcery/config >/dev/null; for spell in "$@"; do if spell_ok "$spell"; then exit 1; fi; done', 'sorcery-impurifier', *args[1:]])
        status = status or query.returncode
    elif args != ['reconcile']:
        raise ValueError('use install [--from DIRECTORY] SPELL...; remove SPELL...; or reconcile')
    activation = subprocess.run(['/usr/sbin/sorcery-impurifier-activate']).returncode
    return status or activation


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print('sorcery-impurifier: ' + str(error), file=sys.stderr)
        sys.exit(1)
