"""Account enumeration and lockout (Session 16, doc 07 T1 / T26, OQ-26).

Accepted by OQ-26: sign-up says "already registered" (behind 5/h/IP + 3/h/email, tested in
test_auth_limits). Everything else must look the same for a registered and an unknown email:
login failures (including the lockout that follows them), forgot password, and people search,
which never matches an email address. (OTP resend answers by challenge id, a random server value,
so it cannot be used to test emails.)
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Any

import pytest

from tests.conftest import AppFactory
from tests.integration.flows import ADMIN_URL, DB_URL, PASSWORD, Flow, make_flow
from tests.integration.users import User

pytestmark = [
    pytest.mark.db,
    pytest.mark.skipif(DB_URL is None or ADMIN_URL is None, reason="needs the test database URLs"),
]


@pytest.fixture
def flow(app_factory: AppFactory) -> Iterator[Flow]:
    yield make_flow(app_factory)


def shape(response: Any) -> tuple[int, str | None, str | None, list[str] | None]:
    error = response.json().get("error", {}) if response.content else {}
    return response.status_code, error.get("code"), error.get("message"), error.get("fields")


def test_login_failures_look_the_same_for_unknown_emails_including_lockout(flow: Flow) -> None:
    known, _ = flow.new_user()
    unknown = f"ghost-{uuid.uuid4().hex[:10]}@example.com"
    known_seq = [shape(flow.login(known, "Wrong1Password")) for _ in range(6)]
    unknown_seq = [shape(flow.login(unknown, "Wrong1Password")) for _ in range(6)]
    assert [s[:3] for s in known_seq] == [s[:3] for s in unknown_seq]
    assert known_seq[-1][1] == "ACCOUNT_LOCKED"


def test_lockout_blocks_the_right_password_and_emails_the_owner_once(flow: Flow) -> None:
    address, _ = flow.new_user()
    for _ in range(7):
        flow.login(address, "Wrong1Password")
    locked = flow.login(address, PASSWORD)
    assert locked.status_code == 423
    assert int(locked.json()["error"]["retry_after_s"]) > 0
    assert [m.template for m in flow.email.sent if m.to == address].count("lockout_notice") == 1


def test_forgot_password_looks_the_same_for_unknown_emails(flow: Flow) -> None:
    known, _ = flow.new_user()
    sent_before = len(flow.email.sent)
    a = flow.client.post("/api/v1/auth/password/forgot", json={"email": known})
    b = flow.client.post("/api/v1/auth/password/forgot", json={"email": "ghost@example.com"})
    assert a.status_code == b.status_code == 202
    assert a.json().keys() == b.json().keys()
    assert len(flow.email.sent) == sent_before + 1  # only the real account gets an email


def test_people_search_never_matches_an_email(flow: Flow) -> None:
    searcher, target = User(flow), User(flow)
    for user in (searcher, target):
        name = f"u{uuid.uuid4().hex[:10]}"
        response = flow.client.put(
            "/api/v1/me/username", headers=user.headers, json={"username": name}
        )
        assert response.status_code in {200, 204}
    local_part = target.email.split("@")[0]
    response = flow.client.get(
        "/api/v1/people/search", params={"q": local_part}, headers=searcher.headers
    )
    assert response.status_code in {200, 422}
    if response.status_code == 200:
        assert str(target.id) not in response.text
