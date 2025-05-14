#!/usr/bin/env python3
from __future__ import annotations  # keeps type hints as strings on 3.8+

import argparse
from pathlib import Path
from typing import Iterable, Optional, Set

DEFAULT_EXTS: Set[str] = {'.yaml', '.yml', '.cfg'}


def iter_files(root: Path, wanted: Optional[Set[str]]) -> Iterable[Path]:
    """Yield files under *root* whose suffix is in *wanted* (or all if None)."""
    for path in sorted(root.rglob('*')):
        if path.is_file() and (wanted is None or path.suffix in wanted):
            yield path


def dump(roots: list[Path], wanted: Optional[Set[str]]) -> None:
    with open('files_dump.log', 'w', encoding='utf-8') as out:
        for root in roots:
            for file in iter_files(root, wanted):
                out.write(f'{file.relative_to(root)}:\n')
                out.write(file.read_text(encoding='utf-8', errors='ignore'))
                out.write('\n')


if __name__ == '__main__':
    p = argparse.ArgumentParser(description='Dump selected files to log.')
    p.add_argument('folders', nargs='*', type=Path,
                   default=[Path(__file__).resolve().parent],
                   help='Folders to scan (default: script directory)')

    grp = p.add_mutually_exclusive_group()
    grp.add_argument('--ext', action='append', metavar='.EXT',
                     help='extra extension(s) to include')
    grp.add_argument('--all', action='store_true',
                     help='include all files (ignore extensions)')

    args = p.parse_args()

    if args.all:
        wanted_exts: Optional[Set[str]] = None
    else:
        extra = {e if e.startswith('.') else f'.{e}' for e in (args.ext or [])}
        wanted_exts = DEFAULT_EXTS | extra

    dump([p.resolve() for p in args.folders], wanted_exts)
