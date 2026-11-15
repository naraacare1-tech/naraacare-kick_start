"""Sign-up, codes, sign-in, lockout, sessions and passwords against a real database (doc 04 2.1)."""

from __future__ import annotations

import uuid

import pytest

from tests.conftest import AppFactory
from tests.integration.flows import (
    ADMIN_URL,
    INSTALLATION,
    PASSWORD,
    bearer,
    db_only,
    make_flow,
)

pytestmark = db_only


def test_signup_verify_and_tokens(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    address = f"new-{uuid.uuid4().hex[:10]}@example.com"
    challenge = flow.signup(address)
    assert challenge["expires_in_s"] == 300 and challenge["resend_after_s"] == 30
    sent = flow.email.sent[-1]
    assert (sent.to, sent.template) == (address, "otp_verification")
    assert len(sent.values["code"]) == 6 and sent.values["code"].isdigit()

    pair = flow.verify(challenge["challenge_id"], sent.values["code"]).json()
    assert pair["token_type"] == "Bearer" and pair["onboarding_required"] is True
    assert pair["access_expires_in_s"] == 900 and pair["refresh_expires_in_s"] == 60 * 86400
    me = flow.client.get("/api/v1/me", headers=bearer(pair))
    assert me.status_code == 200
    assert me.json()["email"] == address and me.json()["tier"] == "standard"
    # The code is single use.
    again = flow.verify(challenge["challenge_id"], sent.values["code"])
    assert again.status_code == 422 and again.json()["error"]["code"] == "OTP_INVALID"


def test_registered_email_weak_and_mismatched_passwords(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    address, _ = flow.new_user()
    body = {
        "email": address.upper(),
        "password": PASSWORD,
        "confirm_password": PASSWORD,
        "accept_terms": True,
        "policy_versions": {"terms": "0.0-draft", "privacy": "0.0-draft"},
        "installation_id": str(uuid.uuid4()),
    }
    taken = flow.client.post("/api/v1/auth/signup", json=body)
    assert taken.status_code == 409 and taken.json()["error"]["code"] == "EMAIL_REGISTERED"
    weak = flow.client.post(
        "/api/v1/auth/signup",
        json={
            **body,
            "email": "w@example.com",
            "password": "password1",
            "confirm_password": "password1",
        },
    )
    assert weak.status_code == 422 and weak.json()["error"]["code"] == "PASSWORD_WEAK"
    mismatch = flow.client.post(
        "/api/v1/auth/signup",
        json={**body, "email": "m@example.com", "confirm_password": "Other1Pass"},
    )
    assert mismatch.json()["error"]["fields"] == ["confirm_password"]
    no_terms = flow.client.post("/api/v1/auth/signup", json={**body, "accept_terms": False})
    assert no_terms.status_code == 422
    unknown_policy = flow.client.post(
        "/api/v1/auth/signup",
        json={
            **body,
            "email": "p@example.com",
            "policy_versions": {"terms": "9.9", "privacy": "9.9"},
        },
    )
    assert unknown_policy.status_code == 422


def test_three_wrong_codes_kill_the_challenge_and_resend_is_rate_limited(
    app_factory: AppFactory,
) -> None:
    flow = make_flow(app_factory)
    address = f"otp-{uuid.uuid4().hex[:10]}@example.com"
    challenge = flow.signup(address)["challenge_id"]
    real = flow.email.last_code(address)
    wrong = "000000" if real != "000000" else "111111"
    first = flow.verify(challenge, wrong).json()["error"]
    second = flow.verify(challenge, wrong).json()["error"]
    assert (first["code"], first["attempts_left"]) == ("OTP_INVALID", 2)
    assert second["attempts_left"] == 1
    third = flow.verify(challenge, wrong)
    assert third.status_code == 423 and third.json()["error"]["code"] == "OTP_LOCKED"
    assert flow.verify(challenge, real).status_code == 423  # dead even with the right code
    resend = flow.client.post("/api/v1/auth/otp/resend", json={"challenge_id": challenge})
    assert resend.status_code == 429 and resend.headers["Retry-After"]
    unknown = flow.client.post("/api/v1/auth/otp/resend", json={"challenge_id": str(uuid.uuid4())})
    assert unknown.status_code == 202  # same answer as a real challenge (no enumeration)


def test_login_and_generic_failures(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    address, _ = flow.new_user()
    ok = flow.login(address)
    assert ok.status_code == 200 and ok.json()["onboarding_required"] is True
    wrong = flow.login(address, "Wrong1Password")
    unknown = flow.login("nobody-" + address, PASSWORD)
    assert wrong.status_code == unknown.status_code == 401
    assert wrong.json()["error"]["message"] == unknown.json()["error"]["message"]
    assert wrong.json()["error"]["code"] == "INVALID_CREDENTIALS"


def test_lockout_after_five_failures_with_notice_email(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    address, _ = flow.new_user()
    codes = [flow.login(address, "Wrong1Password").status_code for _ in range(5)]
    assert codes == [401, 401, 401, 401, 423]
    locked = flow.login(address)  # even the right password while locked
    assert locked.status_code == 423 and int(locked.json()["error"]["retry_after_s"]) > 0
    notices = [m for m in flow.email.sent if m.template == "lockout_notice"]
    assert len(notices) == 1 and notices[0].to == address


def test_unverified_account_gets_a_new_code_on_login(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    address = f"pending-{uuid.uuid4().hex[:10]}@example.com"
    flow.signup(address)
    response = flow.login(address)
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "EMAIL_NOT_VERIFIED"


def test_refresh_rotation_and_reuse_detection(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    _, pair = flow.new_user()
    installation = {"installation_id": str(INSTALLATION)}
    first = flow.client.post(
        "/api/v1/auth/token/refresh", json={"refresh_token": pair["refresh_token"], **installation}
    )
    assert first.status_code == 200
    rotated = first.json()
    assert rotated["refresh_token"] != pair["refresh_token"]
    # Presenting the used token again: the whole family is revoked (theft signal).
    reuse = flow.client.post(
        "/api/v1/auth/token/refresh", json={"refresh_token": pair["refresh_token"], **installation}
    )
    assert reuse.status_code == 401
    after = flow.client.post(
        "/api/v1/auth/token/refresh",
        json={"refresh_token": rotated["refresh_token"], **installation},
    )
    assert after.status_code == 401


def test_refresh_from_another_installation_is_refused(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    _, pair = flow.new_user()
    stolen = flow.client.post(
        "/api/v1/auth/token/refresh",
        json={"refresh_token": pair["refresh_token"], "installation_id": str(uuid.uuid4())},
    )
    assert stolen.status_code == 401


def test_logout_revokes_the_session_and_its_access_token(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    address, pair = flow.new_user()
    other = flow.login(address).json()
    assert flow.client.post("/api/v1/auth/logout", headers=bearer(pair)).status_code == 204
    assert flow.client.get("/api/v1/me", headers=bearer(pair)).status_code == 401
    refresh = flow.client.post(
        "/api/v1/auth/token/refresh",
        json={"refresh_token": pair["refresh_token"], "installation_id": str(INSTALLATION)},
    )
    assert refresh.status_code == 401
    assert flow.client.get("/api/v1/me", headers=bearer(other)).status_code == 200  # other device
    assert flow.client.post("/api/v1/auth/logout-all", headers=bearer(other)).status_code == 204
    assert flow.client.get("/api/v1/me", headers=bearer(other)).status_code == 401


def test_forgot_and_reset_password(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    address, pair = flow.new_user()
    forgot = flow.client.post("/api/v1/auth/password/forgot", json={"email": address})
    assert forgot.status_code == 202
    challenge = forgot.json()["challenge_id"]
    code = flow.email.last_code(address)
    assert flow.email.sent[-1].template == "password_reset"

    reset = {"challenge_id": challenge, "code": code}
    reused = flow.client.post(
        "/api/v1/auth/password/reset",
        json={**reset, "new_password": PASSWORD, "confirm_password": PASSWORD},
    )
    assert reused.status_code == 422 and reused.json()["error"]["code"] == "PASSWORD_REUSED"
    done = flow.client.post(
        "/api/v1/auth/password/reset",
        json={**reset, "new_password": "Brand2NewPass", "confirm_password": "Brand2NewPass"},
    )
    assert done.status_code == 204  # the code survived the rejected reuse attempt
    assert flow.email.sent[-1].template == "password_changed"
    assert flow.client.get("/api/v1/me", headers=bearer(pair)).status_code == 401
    assert flow.login(address).status_code == 401
    assert flow.login(address, "Brand2NewPass").status_code == 200


def test_forgot_password_for_an_unknown_email_looks_the_same(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    before = len(flow.email.sent)
    response = flow.client.post("/api/v1/auth/password/forgot", json={"email": "ghost@example.com"})
    assert response.status_code == 202 and uuid.UUID(response.json()["challenge_id"])
    assert len(flow.email.sent) == before
    attempt = flow.client.post(
        "/api/v1/auth/password/reset",
        json={
            "challenge_id": response.json()["challenge_id"],
            "code": "123456",
            "new_password": "Brand2NewPass",
            "confirm_password": "Brand2NewPass",
        },
    )
    assert attempt.status_code == 422 and attempt.json()["error"]["code"] == "OTP_INVALID"


def test_change_password(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    address, pair = flow.new_user()
    other = flow.login(address).json()
    wrong = flow.client.post(
        "/api/v1/auth/password/change",
        headers=bearer(pair),
        json={
            "current_password": "Wrong1Password",
            "new_password": "Brand2NewPass",
            "confirm_password": "Brand2NewPass",
        },
    )
    assert wrong.status_code == 401
    ok = flow.client.post(
        "/api/v1/auth/password/change",
        headers=bearer(pair),
        json={
            "current_password": PASSWORD,
            "new_password": "Brand2NewPass",
            "confirm_password": "Brand2NewPass",
        },
    )
    assert ok.status_code == 204
    refresh_other = flow.client.post(
        "/api/v1/auth/token/refresh",
        json={"refresh_token": other["refresh_token"], "installation_id": str(INSTALLATION)},
    )
    assert refresh_other.status_code == 401  # other sessions are revoked
    refresh_own = flow.client.post(
        "/api/v1/auth/token/refresh",
        json={"refresh_token": pair["refresh_token"], "installation_id": str(INSTALLATION)},
    )
    assert refresh_own.status_code == 200  # the current device stays signed in


@pytest.mark.skipif(ADMIN_URL is None, reason="NARAACARE_TEST_ADMIN_URL not set")
async def test_email_is_stored_in_plain_text(app_factory: AppFactory) -> None:
    import asyncpg  # noqa: PLC0415

    flow = make_flow(app_factory)
    address, _ = flow.new_user()
    assert ADMIN_URL is not None
    conn = await asyncpg.connect(ADMIN_URL)
    try:
        emails = await conn.fetch("SELECT email FROM auth.user_account")
    finally:
        await conn.close()
    assert address.lower() in {r["email"] for r in emails}  # owner decision 2026-11-03
