"""Purchase receipts (Session 16, doc 07 T11 receipt sharing / SEC-6).

A store purchase unlocks exactly one account: a second account presenting the same Play token or
Apple original transaction gets 409 PURCHASE_TOKEN_IN_USE, stays STANDARD, the owner keeps STAR,
and a security event is logged. Verifying again on the owner's account is idempotent. Forged,
foreign-app and mismatched receipts unlock nothing.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import pytest

from tests.conftest import AppFactory
from tests.integration.flows import ADMIN_URL, DB_URL, Flow, make_flow
from tests.integration.users import User, sql
from tests.stores import ApplePki, Stores, apple_transaction

pytestmark = [
    pytest.mark.db,
    pytest.mark.skipif(DB_URL is None or ADMIN_URL is None, reason="needs the test database URLs"),
]
VERIFY = "/api/v1/billing/purchases/verify"


@pytest.fixture
def stores() -> Stores:
    return Stores()


@pytest.fixture
def flow(app_factory: AppFactory, stores: Stores) -> Iterator[Flow]:
    yield make_flow(app_factory, **stores.state())


def tier(flow: Flow, user: User) -> str:
    return str(flow.client.get("/api/v1/me/entitlements", headers=user.headers).json()["tier"])


def verify(flow: Flow, user: User, body: dict[str, Any]) -> Any:
    return flow.client.post(
        VERIFY, headers={**user.headers, "Idempotency-Key": str(uuid.uuid4())}, json=body
    )


def play(token: str, product: str = "star_monthly") -> dict[str, Any]:
    return {"platform": "android", "product_id": product, "purchase_token": token}


def ios(signed: str, product: str = "star_monthly") -> dict[str, Any]:
    return {"platform": "ios", "product_id": product, "signed_transaction": signed}


async def receipt_sharing_events(user: User) -> int:
    rows = await sql(
        "SELECT count(*) AS n FROM audit.security_event"
        " WHERE user_id = $1 AND event_type LIKE '%token%'",
        user.id,
    )
    return int(rows[0]["n"])


async def test_play_token_unlocks_one_account_only(flow: Flow, stores: Stores) -> None:
    owner, other = User(flow), User(flow)
    token = f"tok-{uuid.uuid4().hex}"
    stores.play.add(token)
    assert verify(flow, owner, play(token)).status_code == 200
    assert verify(flow, owner, play(token)).status_code == 200  # idempotent for the owner

    reused = verify(flow, other, play(token))
    assert reused.status_code == 409
    assert reused.json()["error"]["code"] == "PURCHASE_TOKEN_IN_USE"
    assert (tier(flow, owner), tier(flow, other)) == ("star", "standard")
    assert await receipt_sharing_events(other) >= 1


async def test_apple_transaction_unlocks_one_account_only(flow: Flow, stores: Stores) -> None:
    owner, other = User(flow), User(flow)
    original = str(uuid.uuid4().int)[:16]
    assert verify(flow, owner, ios(stores.pki.sign(apple_transaction(original)))).status_code == 200
    # A renewal of the same subscription (new transaction id, same original) on another account.
    renewal = stores.pki.sign(apple_transaction(original))
    reused = verify(flow, other, ios(renewal))
    assert reused.status_code == 409
    assert (tier(flow, owner), tier(flow, other)) == ("star", "standard")


@pytest.mark.parametrize(
    "case",
    ["untrusted chain", "other app", "other environment", "product mismatch", "not a subscription"],
)
async def test_bad_apple_receipts_unlock_nothing(flow: Flow, stores: Stores, case: str) -> None:
    user = User(flow)
    original = str(uuid.uuid4().int)[:16]
    product = "star_monthly"
    if case == "untrusted chain":
        signed = ApplePki().sign(apple_transaction(original))
    elif case == "other app":
        signed = stores.pki.sign(apple_transaction(original, bundleId="com.evil.app"))
    elif case == "other environment":
        signed = stores.pki.sign(apple_transaction(original, environment="Production"))
    elif case == "product mismatch":
        signed, product = stores.pki.sign(apple_transaction(original)), "star_yearly"
    else:
        signed = stores.pki.sign(apple_transaction(original, type="Consumable"))
    response = verify(flow, user, ios(signed, product))
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "PURCHASE_INVALID"
    assert tier(flow, user) == "standard"


@pytest.mark.parametrize("case", ["unknown token", "product mismatch", "expired"])
async def test_bad_play_receipts_unlock_nothing(flow: Flow, stores: Stores, case: str) -> None:
    user = User(flow)
    token = f"tok-{uuid.uuid4().hex}"
    product = "star_monthly"
    if case == "product mismatch":
        stores.play.add(token, product_id="star_yearly")
    elif case == "expired":
        stores.play.add(token, status="expired", days=-1)
    response = verify(flow, user, play(token, product))
    if case == "expired":
        assert response.status_code == 200  # recorded, but an expired subscription grants nothing
    else:
        assert response.status_code == 422
    assert tier(flow, user) == "standard"
