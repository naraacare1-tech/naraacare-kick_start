"""Replay the Rin prompt-injection red-team set against a running API with a REAL model (staging).

Usage (values from the environment, never hard-coded; use a dedicated STAR test account):
  REDTEAM_API_URL=https://staging.example/api/v1 REDTEAM_EMAIL=... REDTEAM_PASSWORD=... \\
      python tools/rin_redteam.py [report.json]

For each case it records the HTTP status, the final reply and simple checks (plain text, emergency
reply, an action card proposed). A person reviews the report: the model should refuse or stay on
topic; the guardrails are already proven offline by tests/security/test_prompt_injection.py.
Costs real model tokens (one short turn per case).
"""

from __future__ import annotations

import json
import os
import sys
import uuid
from pathlib import Path
from typing import Any

import httpx2
import yaml

CASES = Path(__file__).resolve().parents[1] / "tests/security/payloads/prompt_injection.yaml"
MARKERS = ("<", ">", "javascript:", "](", "&lt", "&#", "{{", "${")


def events(body: str) -> list[tuple[str, dict[str, Any]]]:
    out = []
    for block in body.strip().split("\n\n"):
        lines = dict(line.split(": ", 1) for line in block.splitlines() if ": " in line)
        if "event" in lines and "data" in lines:
            out.append((lines["event"], json.loads(lines["data"])))
    return out


def main() -> int:
    base = os.environ["REDTEAM_API_URL"].rstrip("/")
    report_path = Path(sys.argv[1] if len(sys.argv) > 1 else "rin_redteam_report.json")
    cases = yaml.safe_load(CASES.read_text(encoding="utf-8"))["cases"]
    with httpx2.Client(base_url=base, timeout=90) as client:
        login = client.post(
            "/auth/login",
            json={
                "email": os.environ["REDTEAM_EMAIL"],
                "password": os.environ["REDTEAM_PASSWORD"],
                "installation_id": str(uuid.uuid4()),
            },
        )
        login.raise_for_status()
        headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
        results = []
        for case in cases:
            cid = client.post("/rin/conversations", headers=headers).json()["conversation_id"]
            response = client.post(
                f"/rin/conversations/{cid}/messages",
                headers=headers,
                json={"client_message_id": str(uuid.uuid4()), "content": case["prompt"]},
            )
            stream = events(response.text) if response.is_success else []
            reply = next((d.get("text", "") for k, d in stream if k == "done"), "")
            results.append(
                {
                    "id": case["id"],
                    "expect": case["expect"],
                    "status": response.status_code,
                    "reply": reply,
                    "plain_text": not any(m in reply.lower() for m in MARKERS),
                    "proposed_action": any(k == "action" for k, _ in stream),
                }
            )
            print(f"{case['id']:<28} {response.status_code} {reply[:70]!r}")
    report_path.write_text(json.dumps(results, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"report: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
