"""Google Cloud Pub/Sub push authentication for Play RTDN (Session 11, doc 07 SEC-6.3).

Pub/Sub sends an OIDC ID token in ``Authorization: Bearer``. It is accepted only when it is signed
by Google (JWKS from ``GOOGLE_JWKS_URL``, cached), issued by accounts.google.com, for our push
audience (``GOOGLE_RTDN_PUSH_AUDIENCE``), not expired, and its verified ``email`` is the push
service account (``GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL``). Anything else is rejected before the
body is read.
"""

from __future__ import annotations

import hmac

import jwt

from app.core.security.oauth import GOOGLE_ISSUERS, LEEWAY_S, JwksCache
from app.core.security.tokens import TokenError


class PubSubAuthError(Exception):
    pass


class PubSubVerifier:
    def __init__(self, keys: JwksCache, *, audience: str, service_account_email: str) -> None:
        self.keys = keys
        self.audience = audience
        self.email = service_account_email

    async def verify(self, authorization: str | None) -> None:
        if not authorization or not authorization.startswith("Bearer "):
            raise PubSubAuthError
        token = authorization.removeprefix("Bearer ").strip()
        try:
            kid = jwt.get_unverified_header(token).get("kid")
            if not isinstance(kid, str):
                raise PubSubAuthError
            key = await self.keys.key(kid)
            claims = jwt.decode(
                token,
                key,
                algorithms=["RS256"],
                audience=self.audience,
                leeway=LEEWAY_S,
                options={"require": ["exp", "iat", "iss", "aud", "email"]},
            )
        except (jwt.PyJWTError, TokenError):
            raise PubSubAuthError from None
        if claims.get("iss") not in GOOGLE_ISSUERS:
            raise PubSubAuthError
        email = claims.get("email")
        if not (
            claims.get("email_verified") is True
            and isinstance(email, str)
            and hmac.compare_digest(email, self.email)
        ):
            raise PubSubAuthError
