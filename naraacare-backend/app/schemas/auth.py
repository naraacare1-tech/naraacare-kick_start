"""Auth requests and responses (doc 04 section 2.1). Every string is a Safe* type; models forbid
unknown fields, so a client cannot smuggle ``role``/``tier``/``user_id`` (mass assignment)."""

from __future__ import annotations

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.core.security.validators import (
    SafeEmail,
    SafeOpaqueToken128,
    SafeOpaqueToken256,
    SafeOpaqueToken512,
    SafeOpaqueToken2048,
    SafeOpaqueToken4096,
    SafeOtp,
    SafePassword,
    SafeShortText20,
)
from app.schemas.common import JsonUUID


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class PolicyVersions(Strict):
    terms: SafeShortText20
    privacy: SafeShortText20


class SignupRequest(Strict):
    email: SafeEmail
    password: SafePassword
    confirm_password: SafePassword
    accept_terms: Literal[True]
    policy_versions: PolicyVersions
    installation_id: JsonUUID


class ChallengeResponse(BaseModel):
    challenge_id: UUID
    expires_in_s: int
    resend_after_s: int


class OtpVerifyRequest(Strict):
    challenge_id: JsonUUID
    code: SafeOtp
    installation_id: JsonUUID


class OtpResendRequest(Strict):
    challenge_id: JsonUUID


class ResendResponse(BaseModel):
    resend_after_s: int


class LoginRequest(Strict):
    email: SafeEmail
    password: SafePassword
    installation_id: JsonUUID


class GoogleSignInRequest(Strict):
    id_token: SafeOpaqueToken4096
    nonce: SafeOpaqueToken128
    installation_id: JsonUUID


class AppleSignInRequest(Strict):
    identity_token: SafeOpaqueToken4096
    authorization_code: SafeOpaqueToken512 | None = None
    nonce: SafeOpaqueToken128
    installation_id: JsonUUID


class LinkRequest(Strict):
    link_token: SafeOpaqueToken2048
    password: SafePassword
    installation_id: JsonUUID


class RefreshRequest(Strict):
    refresh_token: SafeOpaqueToken256
    installation_id: JsonUUID


class ForgotPasswordRequest(Strict):
    email: SafeEmail


class ForgotPasswordResponse(BaseModel):
    challenge_id: UUID


class ResetPasswordRequest(Strict):
    challenge_id: JsonUUID
    code: SafeOtp
    new_password: SafePassword
    confirm_password: SafePassword


class ChangePasswordRequest(Strict):
    current_password: SafePassword
    new_password: SafePassword
    confirm_password: SafePassword


class TokenPairResponse(BaseModel):
    access_token: SafeOpaqueToken2048
    access_expires_in_s: int
    refresh_token: SafeOpaqueToken256
    refresh_expires_in_s: int
    token_type: Literal["Bearer"] = "Bearer"  # noqa: S105  # nosec B105 - token type label
    onboarding_required: bool
