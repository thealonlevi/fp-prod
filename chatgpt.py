#!/usr/bin/env python3
from pathlib import Path

exts={'.yaml', '.cfg'}
root=Path(__file__).resolve().parent
with open('files_dump.log','w',encoding='utf-8') as out:
    for f in sorted(root.rglob('*')):
        if f.is_file() and f.suffix in exts:
            out.write(f'{f.relative_to(root)}:\n')
            out.write(f.read_text(encoding='utf-8',errors='ignore'))
            out.write('\n')
