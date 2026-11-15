"""FCM client, reminder fan-out, drink estimator and the Session 09 request schemas."""

from __future__ import annotations

import json
import re
from collections.abc import Callable
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any
from uuid import UUID, uuid4

import httpx2
import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from pydantic import ValidationError

from app.domain.ai.drink_estimator import DrinkEstimate, DrinkEstimator
from app.domain.ai.rin_model import Usage
from app.integrations import fcm
from app.integrations.google_oauth import ServiceAccount
from app.schemas.hydration import (
    CustomDrinkIn,
    DeviceIn,
    IntakeCreate,
    IntakeUpdate,
    ReminderIn,
    RemindersIn,
    TemperatureIn,
    WorkoutCreate,
)
from app.workers.jobs import reminders

# ------------------------------------------------------------------ FCM


def _key_pem() -> str:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    return key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode()


PEM = _key_pem()
ACCOUNT = ServiceAccount("naraacare-test", "push@naraacare-test.iam.example", PEM)


def _client(handler: Callable[[httpx2.Request], httpx2.Response]) -> fcm.FcmClient:
    http = httpx2.AsyncClient(transport=httpx2.MockTransport(handler))
    return fcm.FcmClient(
        http,
        ACCOUNT,
        api_base_url="https://fcm.example",
        token_url="https://oauth.example/token",
    )


def test_service_account_parse() -> None:
    raw = json.dumps(
        {"type": "service_account", "project_id": "p", "client_email": "e", "private_key": "k"}
    )
    assert ServiceAccount.parse(raw) == ServiceAccount("p", "e", "k")
    assert ServiceAccount.parse('{"type":"dummy"}') is None
    assert ServiceAccount.parse("not json") is None
    assert ServiceAccount.parse('{"type":"service_account"}') is None


def test_push_templates_carry_no_numbers() -> None:
    """OQ-41: lock screens are public, so push texts never contain values."""
    for message in fcm.TEMPLATES.values():
        assert not re.search(r"\d", message.title + message.body)
        assert message.deep_link.startswith("naraacare://")
    payload = fcm.FcmClient.payload("tok", fcm.TEMPLATES["hydration"])["message"]
    assert set(payload["data"]) == {"type", "deep_link"}


async def test_send_gets_token_once_and_posts_generic_message() -> None:
    calls: list[httpx2.Request] = []

    def handler(request: httpx2.Request) -> httpx2.Response:
        calls.append(request)
        if request.url.host == "oauth.example":
            form = dict(x.split("=", 1) for x in request.content.decode().split("&"))
            claims = jwt.decode(form["assertion"], options={"verify_signature": False})
            assert claims["scope"] == fcm.SCOPE and claims["aud"] == "https://oauth.example/token"
            return httpx2.Response(200, json={"access_token": "at-1", "expires_in": 3600})
        assert request.headers["Authorization"] == "Bearer at-1"
        assert request.url.path == "/v1/projects/naraacare-test/messages:send"
        return httpx2.Response(200, json={"name": "m"})

    client = _client(handler)
    assert await client.send("device-token", fcm.TEMPLATES["hydration"]) is fcm.PushResult.SENT
    assert await client.send("device-token", fcm.TEMPLATES["sleep"]) is fcm.PushResult.SENT
    assert sum(1 for c in calls if c.url.host == "oauth.example") == 1


@pytest.mark.parametrize(
    ("status", "body", "result"),
    [
        (404, {"error": {"details": [{"errorCode": "UNREGISTERED"}]}}, fcm.PushResult.DEAD_TOKEN),
        (400, {"error": {"details": [{"errorCode": "INVALID_ARGUMENT"}]}}, fcm.PushResult.FAILED),
        (500, {}, fcm.PushResult.FAILED),
        (401, {}, fcm.PushResult.FAILED),
    ],
)
async def test_send_errors(status: int, body: dict[str, Any], result: fcm.PushResult) -> None:
    def handler(request: httpx2.Request) -> httpx2.Response:
        if request.url.host == "oauth.example":
            return httpx2.Response(200, json={"access_token": "at", "expires_in": 3600})
        return httpx2.Response(status, json=body)

    assert await _client(handler).send("t", fcm.TEMPLATES["nutrition"]) is result


async def test_token_failure_and_network_error() -> None:
    assert (
        await _client(lambda _r: httpx2.Response(403)).send("t", fcm.TEMPLATES["hydration"])
        is fcm.PushResult.FAILED
    )

    def boom(_r: httpx2.Request) -> httpx2.Response:
        raise httpx2.ConnectError("down")

    assert await _client(boom).send("t", fcm.TEMPLATES["hydration"]) is fcm.PushResult.FAILED


# ------------------------------------------------------------------ reminder fan-out


class FakeSender:
    def __init__(self, results: dict[str, fcm.PushResult]) -> None:
        self.results = results
        self.sent: list[tuple[str, str]] = []

    async def send(self, token: str, message: fcm.PushMessage) -> fcm.PushResult:
        self.sent.append((token, message.kind))
        return self.results.get(token, fcm.PushResult.SENT)


class FakeRedis:
    def __init__(self) -> None:
        self.keys: set[str] = set()

    async def set(self, name: str, value: str, *, nx: bool, ex: int) -> bool:
        if name in self.keys:
            return False
        self.keys.add(name)
        return True


class FakeDb:
    def __init__(self, rows: list[dict[str, Any]]) -> None:
        self.rows = rows
        self.revoked: list[UUID] = []

    async def run(self, work: Callable[[Any], Any], **_kw: Any) -> Any:
        return await work(self)

    async def fetch_all(self, statement: Any, **_params: Any) -> list[dict[str, Any]]:
        return self.rows

    async def execute(self, statement: Any, **params: Any) -> None:
        self.revoked.append(params["device_id"])


def _row(token: str, kind: str = "hydration") -> dict[str, Any]:
    return {
        "user_id": uuid4(),
        "device_id": uuid4(),
        "reminder_type": kind,
        "platform": "android",
        "push_token": token,
    }


async def test_send_reminders_dedups_and_wipes_dead_tokens() -> None:
    rows = [_row("a"), _row("b", "nutrition"), _row("dead")]
    rows.append({**rows[0]})  # redelivered row: same user, device and minute
    db = FakeDb(rows)
    sender = FakeSender({"dead": fcm.PushResult.DEAD_TOKEN})
    now = datetime(2026, 11, 2, 3, 30, 42, tzinfo=UTC)
    stats = await reminders.send_reminders(
        db=db,  # type: ignore[arg-type]
        sender=sender,
        dedup=FakeRedis(),
        now=now,
    )
    assert (stats.sent, stats.skipped, stats.dead) == (2, 1, 1)
    assert sender.sent == [("a", "hydration"), ("b", "nutrition"), ("dead", "hydration")]
    assert db.revoked == [rows[2]["device_id"]]


async def test_failed_send_is_counted_and_day_ending_soon_kind() -> None:
    db = FakeDb([_row("x"), _row("y")])
    sender = FakeSender({"x": fcm.PushResult.FAILED})
    stats = await reminders.day_ending_soon(
        db=db,  # type: ignore[arg-type]
        sender=sender,
        dedup=FakeRedis(),
        hours=Decimal(3),
    )
    assert (stats.sent, stats.failed) == (1, 1)
    assert sender.sent == [("x", "day_ending_soon"), ("y", "day_ending_soon")]


# ------------------------------------------------------------------ drink estimator


class FakeModel:
    model = "gpt-test"

    def __init__(self, result: DrinkEstimate | None = None, error: bool = False) -> None:
        self.result = result
        self.error = error
        self.names: list[str] = []

    async def estimate(self, drink_name: str) -> tuple[DrinkEstimate | None, Usage]:
        self.names.append(drink_name)
        if self.error:
            raise TimeoutError
        return self.result, Usage(input_tokens=40, output_tokens=20)


DEFAULT = Decimal("0.85")


async def test_estimator_uses_model_and_rounds() -> None:
    model = FakeModel(
        DrinkEstimate(hydration_factor=0.8237, confidence="high", explanation_code="milk_based")
    )
    out = await DrinkEstimator(model).estimate("Banana Shake", DEFAULT)
    assert (out.hydration_factor, out.source, out.explanation_code) == (
        Decimal("0.824"),
        "ai",
        "milk_based",
    )
    assert model.names == ["Banana Shake"]  # only the name is sent


@pytest.mark.parametrize(
    "model",
    [
        None,
        FakeModel(error=True),
        FakeModel(None),
        FakeModel(
            DrinkEstimate(hydration_factor=0.5, confidence="low", explanation_code="unknown")
        ),
    ],
)
async def test_estimator_falls_back_to_default(model: FakeModel | None) -> None:
    out = await DrinkEstimator(model).estimate("x", DEFAULT)
    assert (out.hydration_factor, out.source) == (DEFAULT, "default")


def test_model_output_is_closed() -> None:
    with pytest.raises(ValidationError):
        DrinkEstimate(hydration_factor=1.2, confidence="high", explanation_code="unknown")
    with pytest.raises(ValidationError):
        DrinkEstimate.model_validate(
            {"hydration_factor": 0.5, "confidence": "high", "explanation_code": "<b>x</b>"}
        )
    with pytest.raises(ValidationError):
        DrinkEstimate.model_validate(
            {
                "hydration_factor": 0.5,
                "confidence": "high",
                "explanation_code": "unknown",
                "note": "hi",
            }
        )


# ------------------------------------------------------------------ schemas

ID = str(uuid4())
AT = "2026-11-02T08:00:00+05:30"


def test_intake_rules() -> None:
    ok = IntakeCreate.model_validate(
        {
            "client_entry_id": ID,
            "logged_at": AT,
            "drink_code": "water",
            "volume_ml": -100,
            "source": "swipe",
        }
    )
    assert ok.volume_ml == -100
    bad: list[dict[str, Any]] = [
        {"drink_code": "water", "volume_ml": -100, "source": "manual"},
        {"drink_code": "tea", "volume_ml": -100, "source": "swipe"},
        {"drink_code": "water", "volume_ml": 0, "source": "manual"},
        {"drink_code": "water", "volume_ml": 3001, "source": "manual"},
        {"drink_code": "water", "custom_drink_id": ID, "volume_ml": 100, "source": "manual"},
        {"volume_ml": 100, "source": "manual"},
        {"drink_code": "smoothie", "volume_ml": 100, "source": "manual"},
        {"drink_code": "water", "volume_ml": "100", "source": "manual"},
        {"drink_code": "water", "volume_ml": 100, "source": "manual", "user_id": ID},
    ]
    for extra in bad:
        with pytest.raises(ValidationError):
            IntakeCreate.model_validate({"client_entry_id": ID, "logged_at": AT, **extra})
    with pytest.raises(ValidationError):
        IntakeUpdate.model_validate({"drink_code": "tea", "custom_drink_id": ID})
    with pytest.raises(ValidationError):
        IntakeUpdate.model_validate({"volume_ml": 50000})


def test_temperature_custom_drink_workout_device() -> None:
    assert TemperatureIn.model_validate({"temperature_c": 30.5}).temperature_c == Decimal("30.5")
    for value in (14.9, 40.1, 30.25):
        with pytest.raises(ValidationError):
            TemperatureIn.model_validate({"temperature_c": value})
    assert (
        CustomDrinkIn.model_validate({"name": "Banana Shake", "hydration_factor": 0.82}).source
        == "user"
    )
    for body in (
        {"name": "<script>alert(1)</script>", "hydration_factor": 0.8},
        {"name": "Lassi", "hydration_factor": 1.5},
        {"name": "Lassi", "hydration_factor": 0.8125},
        {"name": "x" * 61, "hydration_factor": 0.8},
    ):
        with pytest.raises(ValidationError):
            CustomDrinkIn.model_validate(body)
    WorkoutCreate.model_validate(
        {"client_entry_id": ID, "workout_type": "running", "duration_min": 60, "performed_at": AT}
    )
    for minutes in (0, 601):
        with pytest.raises(ValidationError):
            WorkoutCreate.model_validate(
                {
                    "client_entry_id": ID,
                    "workout_type": "gym",
                    "duration_min": minutes,
                    "performed_at": AT,
                }
            )
    with pytest.raises(ValidationError):
        DeviceIn.model_validate(
            {
                "installation_id": ID,
                "platform": "android",
                "push_token": "<img src=x>",
                "app_version": "1.0.0",
            }
        )


def test_reminders() -> None:
    body = RemindersIn.model_validate(
        {"reminders": [{"type": "nutrition", "enabled": True, "times": ["08:30", "20:00"]}]}
    )
    assert [t.strftime("%H:%M") for t in body.reminders[0].times] == ["08:30", "20:00"]
    assert ReminderIn.model_validate({"type": "sleep", "enabled": False}).times == []
    bad = [
        {"type": "nutrition", "enabled": True},
        {"type": "nutrition", "enabled": True, "times": ["08:30"], "interval_min": 60},
        {"type": "nutrition", "enabled": True, "times": ["08:30", "08:30"]},
        {"type": "nutrition", "enabled": True, "times": ["08:30:15"]},
        {"type": "hydration", "enabled": True, "interval_min": 30},
        {"type": "marketing", "enabled": False},
    ]
    for item in bad:
        with pytest.raises(ValidationError):
            ReminderIn.model_validate(item)
    with pytest.raises(ValidationError):
        RemindersIn.model_validate(
            {
                "reminders": [
                    {"type": "sleep", "enabled": False},
                    {"type": "sleep", "enabled": False},
                ]
            }
        )
