from __future__ import annotations

import asyncio
import importlib

from tests.conftest import SetEnv


def test_broker_loads_and_heartbeat_runs(set_env: SetEnv) -> None:
    set_env()
    broker_module = importlib.import_module("app.workers.broker")

    assert broker_module.heartbeat.task_name == "ops.heartbeat"
    assert asyncio.run(broker_module.heartbeat.original_func()) == "ok"
