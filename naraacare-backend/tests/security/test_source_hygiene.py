"""No invisible or bidi control characters in source files ("Trojan Source", CVE-2021-42574).

Literal zero-width/bidi characters can make code read differently from how it runs, and they are
exactly what the validators reject. Sources must spell them as escapes. The editing tooling has
silently turned escapes into literal characters before (Sessions 01 and 04), so this runs
every time.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BANNED = (
    set(range(0x200B, 0x2010)) | set(range(0x202A, 0x202F)) | set(range(0x2066, 0x206A)) | {0xFEFF}
)
SCANNED = ("app", "tests", "tools", "semgrep")
SUFFIXES = {".py", ".yml", ".yaml", ".toml", ".md", ".txt"}
# The shared payload list deliberately contains these characters (as json: escapes, but the
# generated file is still excluded so a future format change cannot break this test).
EXCLUDED = {ROOT / "tests/security/payloads/xss.txt"}


def test_no_invisible_characters_in_sources() -> None:
    findings: list[str] = []
    for top in SCANNED:
        for path in sorted((ROOT / top).rglob("*")):
            if path.suffix not in SUFFIXES or not path.is_file() or path in EXCLUDED:
                continue
            for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                bad = sorted({f"U+{ord(ch):04X}" for ch in line if ord(ch) in BANNED})
                if bad:
                    findings.append(f"{path.relative_to(ROOT)}:{lineno}: {', '.join(bad)}")
    assert findings == [], "\n".join(findings)
