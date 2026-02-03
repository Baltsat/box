#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# ///
"""
Replace straight quotes with curly (smart) quotes at specific positions.

Usage:
    fancy left <file> <line:char> [line:char ...]
    fancy right <file> <line:char> [line:char ...]

Example:
    fancy left foo.md 5:10 5:25
    fancy right foo.md 5:15 5:30
"""
import sys
from pathlib import Path


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]
    filepath = Path(sys.argv[2])
    positions = sys.argv[3:]

    if cmd == "left":
        char = "\u201c"  # "
    elif cmd == "right":
        char = "\u201d"  # "
    else:
        print(f"unknown command: {cmd}")
        print("use 'left' or 'right'")
        sys.exit(1)

    if not filepath.exists():
        print(f"file not found: {filepath}")
        sys.exit(1)

    lines = filepath.read_text().splitlines(keepends=True)
    count = 0

    for pos in positions:
        try:
            line_num, col = map(int, pos.split(":"))
            line_idx = line_num - 1
            col_idx = col - 1

            if 0 <= line_idx < len(lines):
                line = lines[line_idx]
                if 0 <= col_idx < len(line):
                    lines[line_idx] = line[:col_idx] + char + line[col_idx + 1:]
                    count += 1
        except ValueError:
            print(f"invalid position: {pos} (use line:char format)")

    filepath.write_text("".join(lines))
    print(f"placed {count} {cmd} quote(s)")


if __name__ == "__main__":
    main()
