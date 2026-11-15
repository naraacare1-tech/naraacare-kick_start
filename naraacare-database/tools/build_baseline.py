"""Generate baseline Flyway migrations from the canonical DDL (tools/canonical_order.txt).

Usage:
  python tools/build_baseline.py            # write missing migrations/Vnnn__*.sql files
  python tools/build_baseline.py --check    # CI: every canonical file is listed exactly once, every listed
                                            #     file exists, and every group has its migration file

Existing migration files are never overwritten: Flyway migrations are immutable once merged.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tools" / "canonical_order.txt"
CANONICAL_DIRS = ("schemas", "roles", "tables", "indexes")
HEADER = re.compile(r"^\[(V\d{3}__[a-z0-9_]+)\]$")


def read_manifest() -> dict[str, list[str]]:
    groups: dict[str, list[str]] = {}
    current: str | None = None
    for raw in MANIFEST.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = HEADER.match(line)
        if match:
            current = match.group(1)
            groups[current] = []
        elif current is None:
            raise SystemExit(f"File listed before any [Vnnn__name] header: {line}")
        else:
            groups[current].append(line)
    return groups


def check(groups: dict[str, list[str]]) -> list[str]:
    problems: list[str] = []
    listed = [path for files in groups.values() for path in files]
    for path in listed:
        if listed.count(path) > 1:
            problems.append(f"listed more than once: {path}")
        if not (ROOT / path).is_file():
            problems.append(f"listed but missing: {path}")
    on_disk = {
        p.relative_to(ROOT).as_posix()
        for d in CANONICAL_DIRS
        for p in (ROOT / d).glob("*.sql")
    }
    for path in sorted(on_disk - set(listed)):
        problems.append(f"canonical file not in manifest: {path}")
    for name in groups:
        if not (ROOT / "migrations" / f"{name}.sql").is_file():
            problems.append(f"migration missing: migrations/{name}.sql")
    return sorted(set(problems))


def build(groups: dict[str, list[str]]) -> int:
    written = 0
    for name, files in groups.items():
        target = ROOT / "migrations" / f"{name}.sql"
        if target.exists():
            continue
        parts = [
            f"-- {name}: generated from canonical DDL by tools/build_baseline.py.",
            "-- Immutable once merged. Later changes go into new migrations (V014+) plus the canonical files.",
            "",
        ]
        for path in files:
            body = (ROOT / path).read_text(encoding="utf-8").rstrip()
            parts += [f"-- >>> {path}", body, ""]
        target.write_text("\n".join(parts), encoding="utf-8", newline="\n")
        written += 1
        print(f"wrote migrations/{name}.sql")
    return written


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    groups = read_manifest()
    if args.check:
        problems = check(groups)
        for problem in problems:
            print(problem, file=sys.stderr)
        return 1 if problems else 0
    build(groups)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
