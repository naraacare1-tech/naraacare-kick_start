"""Store webhook forgery and replay (Session 16, doc 07 T10 / SEC-6).

The two webhooks are the only unauthenticated write routes. A forged call (no/garbage/foreign
OIDC token, a JWS from an untrusted chain or without Apple's certificate markers, another app)
gets 401/400 and changes nothing; a genuine one is applied once, however often it is replayed.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable, Iterator
from typing import Any

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec

from tests.conftest import AppFactory
from tests.integration.flows import ADMIN_URL, DB_URL, Flow, make_flow
from tests.integration.users import User, sql
from tests.stores import (
    PACKAGE_NAME,
    ApplePki,
    GoogleOidc,
    Stores,
    apple_notification,
    apple_transaction,
    pubsub_body,
)

pytestmark = [
    pytest.mark.db,
    pytest.mark.skipif(DB_URL is None or ADMIN_URL is None, reason="needs the test database URLs"),
]
GOOGLE = "/api/v1/billing/webhooks/google"
APPLE = "/api/v1/billing/webhooks/apple"


@pytest.fixture
def stores() -> Stores:
    return Stores()


@pytest.fixture
def flow(app_factory: AppFactory, stores: Stores) -> Iterator[Flow]:
    yield make_flow(app_factory, **stores.state())


def tier(flow: Flow, user: User) -> str:
    return str(flow.client.get("/api/v1/me/entitlements", headers=user.headers).json()["tier"])


async def notifications() -> int:
    rows = await sql("SELECT count(*) AS n FROM billing.store_notification")
    return int(rows[0]["n"])


def rtdn(token: str, kind: int = 4) -> dict[str, Any]:
    return {
        "version": "1.0",
        "packageName": PACKAGE_NAME,
        "eventTimeMillis": "1800000000000",
        "subscriptionNotification": {
            "version": "1.0",
            "notificationType": kind,
            "purchaseToken": token,
        },
    }


def verify_play(flow: Flow, user: User, token: str) -> Any:
    return flow.client.post(
        "/api/v1/billing/purchases/verify",
        headers={**user.headers, "Idempotency-Key": str(uuid.uuid4())},
        json={"platform": "android", "product_id": "star_monthly", "purchase_token": token},
    )


# --------------------------------------------------------------------------- Google RTDN
GOOGLE_FORGERIES: dict[str, Callable[[GoogleOidc], str | None]] = {
    "no header": lambda o: None,
    "garbage": lambda o: "Bearer not.a.jwt",
    "basic": lambda o: "Basic Zm9vOmJhcg==",
    "attacker key": lambda o: f"Bearer {GoogleOidc(kid=o.kid).token()}",
    "wrong audience": lambda o: f"Bearer {o.token(aud='https://evil.example/hook')}",
    "wrong service account": lambda o: f"Bearer {o.token(email='evil@evil.example')}",
    "email not verified": lambda o: f"Bearer {o.token(email_verified=False)}",
    "wrong issuer": lambda o: f"Bearer {o.token(iss='https://evil.example')}",
    "expired": lambda o: f"Bearer {o.token(iat=1_700_000_000, exp=1_700_000_600)}",
    "no email claim": lambda o: f"Bearer {o.token(email=None)}",
    "alg none": lambda o: "Bearer eyJhbGciOiJub25lIn0.eyJhdWQiOiJ4In0.",
}


@pytest.mark.parametrize("case", GOOGLE_FORGERIES)
async def test_forged_google_push_is_refused(flow: Flow, stores: Stores, case: str) -> None:
    user = User(flow)
    stores.play.add("tok-forged-target", status="active")
    before = await notifications()
    header = GOOGLE_FORGERIES[case](stores.oidc)
    headers = {"Content-Type": "application/json"} | ({"Authorization": header} if header else {})
    body = pubsub_body(rtdn("tok-forged-target"))
    response = flow.client.post(GOOGLE, content=body, headers=headers)
    assert response.status_code == 401, response.text
    assert await notifications() == before
    assert tier(flow, user) == "standard"


async def test_google_push_for_another_app_is_refused(flow: Flow, stores: Stores) -> None:
    before = await notifications()
    body = rtdn("tok-x") | {"packageName": "com.evil.app"}
    response = flow.client.post(
        GOOGLE,
        content=pubsub_body(body),
        headers={"Authorization": f"Bearer {stores.oidc.token()}"},
    )
    assert response.status_code == 400
    assert await notifications() == before


async def test_genuine_google_push_applies_once_however_often_replayed(
    flow: Flow, stores: Stores
) -> None:
    user = User(flow)
    token = f"tok-{uuid.uuid4().hex}"
    stores.play.add(token, status="active")
    assert verify_play(flow, user, token).status_code == 200
    assert tier(flow, user) == "star"

    stores.play.add(token, status="expired", days=-1)  # Google now reports it expired
    before = await notifications()
    body = pubsub_body(rtdn(token, kind=13), message_id=str(uuid.uuid4().int)[:12])
    for _ in range(3):
        response = flow.client.post(
            GOOGLE, content=body, headers={"Authorization": f"Bearer {stores.oidc.token()}"}
        )
        assert response.status_code == 204
    assert await notifications() == before + 1
    assert tier(flow, user) == "standard"


# --------------------------------------------------------------------------- Apple
def apple_forgeries(pki: ApplePki) -> dict[str, str]:
    attacker = ApplePki()
    txn = apple_transaction("1000000000000001")
    hs256 = jwt.encode({"notificationType": "SUBSCRIBED"}, "s" * 32, algorithm="HS256")
    other_curve = ec.generate_private_key(ec.SECP384R1())
    return {
        "untrusted chain": apple_notification(attacker, txn),
        "leaf without Apple OID": pki.sign({"notificationType": "SUBSCRIBED"}, with_oids=False),
        "hs256": hs256,
        "es384 no chain": jwt.encode({"a": 1}, other_curve, algorithm="ES384"),
        "garbage": "a.b.c",
        "tampered payload": _tamper(apple_notification(pki, txn)),
    }


def _tamper(jws: str) -> str:
    header, payload, signature = jws.split(".")
    flipped = payload[:-2] + ("A" if payload[-2] != "A" else "B") + payload[-1]
    return f"{header}.{flipped}.{signature}"


async def test_forged_apple_notifications_are_refused(flow: Flow, stores: Stores) -> None:
    before = await notifications()
    for name, payload in apple_forgeries(stores.pki).items():
        response = flow.client.post(APPLE, json={"signedPayload": payload})
        assert response.status_code in {401, 422}, (name, response.text)
    assert await notifications() == before


async def test_apple_notification_for_another_app_is_refused(flow: Flow, stores: Stores) -> None:
    payload = stores.pki.sign(
        {
            "notificationType": "SUBSCRIBED",
            "notificationUUID": str(uuid.uuid4()),
            "data": {"bundleId": "com.evil.app", "environment": "Sandbox"},
        }
    )
    response = flow.client.post(APPLE, json={"signedPayload": payload})
    assert response.status_code == 400


async def test_genuine_apple_refund_applies_once(flow: Flow, stores: Stores) -> None:
    user = User(flow)
    original = str(uuid.uuid4().int)[:16]
    txn = apple_transaction(original)
    verified = flow.client.post(
        "/api/v1/billing/purchases/verify",
        headers={**user.headers, "Idempotency-Key": str(uuid.uuid4())},
        json={
            "platform": "ios",
            "product_id": "star_monthly",
            "signed_transaction": stores.pki.sign(txn),
        },
    )
    assert verified.status_code == 200, verified.text
    assert tier(flow, user) == "star"

    before = await notifications()
    refund = apple_notification(
        stores.pki, apple_transaction(original, revocationDate=1), type_="REFUND"
    )
    for _ in range(3):
        assert flow.client.post(APPLE, json={"signedPayload": refund}).status_code == 200
    assert await notifications() == before + 1
    assert tier(flow, user) == "standard"
