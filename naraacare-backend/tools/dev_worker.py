"""Dev-only job runner: runs the worker's queue-free jobs in a loop without Redis.

On a dev machine without Redis the taskiq worker cannot start, so report and export jobs stay
"queued" forever. This runs the same task functions from ``app.workers.broker`` directly:

* every 10 s: reports.generate, privacy.generate_exports, support.forward
* every 10 min: reports.expire, privacy.expire_exports

Reminder/social pushes, billing reconcile, erasure and retention are left to the real worker.

Run it with the app_worker login (the ops routines are granted to that role only); the URL comes
from the environment, never from this file, and overrides DATABASE_URL in .env:

    DATABASE_URL='postgresql+asyncpg://app_worker:<password>@localhost:5432/naraacare' \
        uv run python tools/dev_worker.py

Refuses to start unless APP_ENV=dev.
"""

from __future__ import annotations

import asyncio
import contextlib
import os
import sys
import time
from collections.abc import Awaitable, Callable
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

FAST_SECONDS = 10
SLOW_SECONDS = 600


def _check_environment() -> None:
    url = os.environ.get("DATABASE_URL", "")
    if urlsplit(url).username != "app_worker":
        sys.exit("dev_worker: set DATABASE_URL in the environment to the app_worker login")


async def _run(name: str, job: Callable[[], Awaitable[str]]) -> None:
    try:
        result = await job()
    except Exception as exc:  # one failing job never stops the loop
        print(f"{time.strftime('%H:%M:%S')} {name}: {type(exc).__name__}", flush=True)
        return
    if not result.startswith(("built 0, failed 0", "forwarded 0", "expired 0")):
        print(f"{time.strftime('%H:%M:%S')} {name}: {result}", flush=True)


async def main() -> None:
    _check_environment()
    from app.workers import broker  # noqa: PLC0415 - settings load after the environment check

    if broker._settings.APP_ENV != "dev":
        sys.exit("dev_worker: refuses to run outside APP_ENV=dev; use the taskiq worker")

    fast = {
        "reports.generate": broker.generate_reports_job,
        "privacy.generate_exports": broker.generate_exports_job,
        "support.forward": broker.forward_support_job,
    }
    slow = {
        "reports.expire": broker.expire_reports_job,
        "privacy.expire_exports": broker.expire_exports_job,
    }
    print("dev_worker: running (Ctrl+C to stop)", flush=True)
    last_slow = 0.0
    while True:
        for name, job in fast.items():
            await _run(name, job)
        if time.monotonic() - last_slow >= SLOW_SECONDS:
            for name, job in slow.items():
                await _run(name, job)
            last_slow = time.monotonic()
        await asyncio.sleep(FAST_SECONDS)


if __name__ == "__main__":
    with contextlib.suppress(KeyboardInterrupt):
        asyncio.run(main())
