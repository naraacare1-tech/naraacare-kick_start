"""Billing and referral requests (doc 04 section 2.12). Tokens are Safe opaque tokens (no markup),
products a closed Literal; models forbid unknown fields and carry no ``user_id``."""

from __future__ import annotations

from typing import Literal, Self

from pydantic import model_validator

from app.core.security.validators import (
    SafeOpaqueToken2048,
    SafeOpaqueToken16384,
    SafeOpaqueToken65536,
    SafeReferralCode,
)
from app.schemas.common import JsonUUID
from app.schemas.nutrition import _Model

ProductId = Literal["star_monthly", "star_yearly"]


class PurchaseVerify(_Model):
    platform: Literal["android", "ios"]
    product_id: ProductId
    purchase_token: SafeOpaqueToken2048 | None = None
    signed_transaction: SafeOpaqueToken16384 | None = None

    @model_validator(mode="after")
    def _token_for_platform(self) -> Self:
        if self.platform == "android" and (not self.purchase_token or self.signed_transaction):
            raise ValueError("android sends purchase_token only")
        if self.platform == "ios" and (not self.signed_transaction or self.purchase_token):
            raise ValueError("ios sends signed_transaction only")
        return self


class AppleNotification(_Model):
    signedPayload: SafeOpaqueToken65536  # noqa: N815 - Apple's field name


class ReferralAttribute(_Model):
    code: SafeReferralCode
    installation_id: JsonUUID
