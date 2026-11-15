"""Fail if SQL sources contain invisible or bidi control characters.

Regexes must use escapes (e.g. backslash-u200B), never the literal character: literal bidi overrides can
hide code in reviews ("Trojan Source"). Usage: python tools/check_invisible_chars.py DIR [DIR ...]
"""

from __future__ import annotations

import sys
from pathlib import Path

BANNED = set(range(0x200B, 0x2010)) | set(range(0x202A, 0x202F)) | set(range(0x2066, 0x206A)) | {0xFEFF}


def main(dirs: list[str]) -> int:
    found = 0
    for directory in dirs:
        for path in sorted(Path(directory).rglob("*")):
            if path.suffix not in {".sql", ".psql"} or not path.is_file():
                continue
            for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
                bad = sorted({f"U+{ord(ch):04X}" for ch in line if ord(ch) in BANNED})
                if bad:
                    print(f"{path}:{lineno}: {', '.join(bad)}")
                    found += 1
    if found:
        print("Invisible/bidi characters found: use regex escapes instead.", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
