"""Consents, re-authentication, exports and deletion (doc 04 section 2.13, doc 07 SEC-7). No user id
from the client; the password is a SafePassword, codes are SafeOtp."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, model_validator

from app.core.security.validators import SafeOtp, SafePassword, SafeShortText20
from app.schemas.common import JsonUUID
from app.schemas.me import ConsentIn, ConsentPurpose
from app.schemas.nutrition import _Model


class ConsentRequest(ConsentIn):
    """One decision; a withdrawal is ``granted: false`` (a new record, never an update)."""


class ConsentOut(BaseModel):
    purpose: ConsentPurpose
    granted: bool
    policy_version: SafeShortText20
    recorded_at: datetime


class ConsentsResponse(BaseModel):
    consents: list[ConsentOut]


class ReauthProof(_Model):
    """Fresh proof of identity before an export or deletion: the account password, or the code from
    ``POST /privacy/reauth`` (accounts without a password)."""

    password: SafePassword | None = None
    challenge_id: JsonUUID | None = None
    code: SafeOtp | None = None

    @model_validator(mode="after")
    def _one_proof(self) -> ReauthProof:
        by_code = self.challenge_id is not None and self.code is not None
        if (self.password is None) == (not by_code) or (
            self.password is not None and (self.challenge_id or self.code)
        ):
            raise ValueError("send either password, or challenge_id and code")
        return self
