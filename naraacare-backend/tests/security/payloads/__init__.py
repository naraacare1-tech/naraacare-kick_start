"""Loaders for the payload lists (doc 07 §4.7): the shared script/markup list (xss.txt, generated,
identical in all three repos) and the backend's SQLi / path traversal / CSV injection lists."""

from __future__ import annotations

import json
from pathlib import Path

PAYLOAD_FILE = Path(__file__).with_name("xss.txt")
EXPECTED_VERSION = "1.0.0"


def payload_list_version() -> str:
    for line in PAYLOAD_FILE.read_text(encoding="utf-8").splitlines():
        if line.startswith("# payload-list-version:"):
            return line.split(":", 1)[1].strip()
    return ""


def load_payloads(name: str = "xss.txt") -> list[str]:
    payloads: list[str] = []
    for line in PAYLOAD_FILE.with_name(name).read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        payloads.append(json.loads(line[5:]) if line.startswith("json:") else line)
    return payloads
