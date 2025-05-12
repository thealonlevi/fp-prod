#!/usr/bin/env python3
"""
tree_to_log.py  –  export a clean, one-file tree of your project.

• Run it from (or place it in) the project’s root directory.
• Hidden files/dirs (.*) are ignored.
• Output goes to `project_structure.log` in the same directory.
"""

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent          # project root = script location
LOG_FILE = ROOT / "project_structure.log"


def is_hidden(path: Path) -> bool:
    """Return True for .* entries anywhere in the path parts."""
    return any(part.startswith(".") for part in path.parts)


def build_tree(base: Path) -> list[str]:
    """Return a sorted list of relative paths for every visible file/dir."""
    tree_lines: list[str] = []
    for dirpath, dirnames, filenames in os.walk(base):
        rel_dir = Path(dirpath).relative_to(base)

        # Filter *in-place* so os.walk doesn’t descend into hidden dirs
        dirnames[:] = [d for d in dirnames if not is_hidden(Path(d))]
        filenames = [f for f in filenames if not is_hidden(Path(f))]

        # Add directory entry except for root (“.”)
        if rel_dir != Path("."):
            tree_lines.append(f"{rel_dir}/")

        # Add files
        for fname in filenames:
            rel_file = rel_dir / fname if rel_dir != Path(".") else Path(fname)
            tree_lines.append(str(rel_file))

    return sorted(tree_lines, key=lambda p: p.lower())


def main() -> None:
    lines = build_tree(ROOT)
    LOG_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {len(lines)} entries → {LOG_FILE}")


if __name__ == "__main__":
    main()
