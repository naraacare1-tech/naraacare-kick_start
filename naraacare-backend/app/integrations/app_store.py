"""App Store signed data (Session 11, doc 07 SEC-6.2): StoreKit 2 signed transactions and App Store
Server Notifications v2 are JWS (ES256) whose ``x5c`` header carries the certificate chain.

``AppleJwsVerifier`` accepts a JWS only when:
* the chain is leaf -> intermediate(s) -> one of the configured Apple root certificates
  (``APPLE_ROOT_CA_PATHS``, Apple Root CA - G3), each certificate directly issued by the next and
  valid now; the leaf carries Apple's receipt-signing OID and the intermediate Apple's WWDR OID;
* the ES256 signature verifies with the leaf key;
* for transactions, the bundle id is ours and the environment is the configured one.
It is built on ``cryptography`` (already pinned) instead of app-store-server-library, keeping the
dependency surface small; the checks are the same ones that library performs.

``AppStoreApiClient`` calls the App Store Server API (Get All Subscription Statuses) with a
short-lived ES256 token signed by the in-app purchase key, for the reconcile job.
"""

from __future__ import annotations

import base64
import itertools
import time
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from http import HTTPStatus
from pathlib import Path
from typing import Any
from urllib.parse import quote

import httpx2
import jwt
import structlog
from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric import ec

log = structlog.get_logger(__name__)

LEAF_OID = x509.ObjectIdentifier("1.2.840.113635.100.6.11.1")
INTERMEDIATE_OID = x509.ObjectIdentifier("1.2.840.113635.100.6.2.1")


class AppleVerificationError(Exception):
    """The signed data is not authentic or not for this app/environment."""


@dataclass(frozen=True, slots=True)
class AppleTransaction:
    product_id: str
    original_transaction_id: str
    transaction_id: str
    purchase_date: datetime
    expires_date: datetime
    revoked: bool
    environment: str
    price_micros: int
    currency: str


def _ms(value: object) -> datetime:
    return datetime.fromtimestamp(int(value) / 1000, tz=UTC)  # type: ignore[call-overload]


def load_roots(paths: Sequence[str]) -> list[x509.Certificate]:
    roots = []
    for raw in paths:
        data = Path(raw).read_bytes()
        roots.append(
            x509.load_pem_x509_certificate(data)
            if data.lstrip().startswith(b"-----")
            else x509.load_der_x509_certificate(data)
        )
    return roots


class AppleJwsVerifier:
    def __init__(
        self,
        roots: Sequence[x509.Certificate],
        *,
        bundle_id: str,
        environment: str,
        clock: Any = time.time,
    ) -> None:
        if not roots:
            raise ValueError("at least one Apple root certificate is required")
        self.roots = list(roots)
        self.bundle_id = bundle_id
        self.environment = environment
        self.clock = clock

    def _verify_chain(self, x5c: object) -> x509.Certificate:
        if not isinstance(x5c, list) or not 2 <= len(x5c) <= 4:  # noqa: PLR2004 - leaf, CA(s), root
            raise AppleVerificationError("bad x5c")
        try:
            chain = [x509.load_der_x509_certificate(base64.b64decode(c)) for c in x5c]
        except (ValueError, TypeError):
            raise AppleVerificationError("bad certificate") from None
        now = datetime.fromtimestamp(self.clock(), tz=UTC)
        for cert in chain:
            if not cert.not_valid_before_utc <= now <= cert.not_valid_after_utc:
                raise AppleVerificationError("certificate not valid now")
        try:
            for child, parent in itertools.pairwise(chain):
                child.verify_directly_issued_by(parent)
            top = chain[-1]
            if not any(top == root for root in self.roots):
                # The chain may stop below the root: its last certificate must be issued by a root.
                for root in self.roots:
                    try:
                        top.verify_directly_issued_by(root)
                        break
                    except (ValueError, TypeError, InvalidSignature):
                        continue
                else:
                    raise AppleVerificationError("chain does not end at an Apple root")
        except (ValueError, TypeError, InvalidSignature):
            raise AppleVerificationError("chain signature") from None
        leaf, intermediate = chain[0], chain[1]
        if not _has_extension(leaf, LEAF_OID) or not _has_extension(intermediate, INTERMEDIATE_OID):
            raise AppleVerificationError("not an Apple signing certificate")
        return leaf

    def verify(self, jws: str) -> dict[str, Any]:
        try:
            header = jwt.get_unverified_header(jws)
        except jwt.PyJWTError:
            raise AppleVerificationError("bad JWS") from None
        if header.get("alg") != "ES256":
            raise AppleVerificationError("unexpected algorithm")
        key = self._verify_chain(header.get("x5c")).public_key()
        if not isinstance(key, ec.EllipticCurvePublicKey):
            raise AppleVerificationError("unexpected key type")
        try:
            claims: dict[str, Any] = jwt.decode(
                jws, key, algorithms=["ES256"], options={"verify_aud": False}
            )
        except jwt.PyJWTError:
            raise AppleVerificationError("signature") from None
        return claims

    def transaction(self, jws: str) -> AppleTransaction:
        claims = self.verify(jws)
        if claims.get("bundleId") != self.bundle_id:
            raise AppleVerificationError("other app")
        if claims.get("environment") != self.environment:
            raise AppleVerificationError("other environment")
        if claims.get("type") != "Auto-Renewable Subscription" or "expiresDate" not in claims:
            raise AppleVerificationError("not a subscription")
        return AppleTransaction(
            product_id=str(claims["productId"]),
            original_transaction_id=str(claims["originalTransactionId"]),
            transaction_id=str(claims["transactionId"]),
            purchase_date=_ms(claims["purchaseDate"]),
            expires_date=_ms(claims["expiresDate"]),
            revoked="revocationDate" in claims,
            environment="sandbox" if claims["environment"] == "Sandbox" else "production",
            price_micros=int(claims.get("price", 0)) * 1000,  # price is in milli-units
            currency=str(claims.get("currency") or "INR"),
        )


def _has_extension(cert: x509.Certificate, oid: x509.ObjectIdentifier) -> bool:
    try:
        cert.extensions.get_extension_for_oid(oid)
    except x509.ExtensionNotFound:
        return False
    return True


class AppStoreApiClient:
    """Get All Subscription Statuses (reconcile). The response items are themselves signed JWS,
    verified with the same verifier."""

    def __init__(
        self,
        http: httpx2.AsyncClient,
        *,
        base_url: str,
        issuer_id: str,
        key_id: str,
        private_key_p8: str,
        bundle_id: str,
        timeout_s: float = 8.0,
    ) -> None:
        self.http = http
        self.base_url = base_url.rstrip("/")
        self.issuer_id = issuer_id
        self.key_id = key_id
        self.private_key = private_key_p8
        self.bundle_id = bundle_id
        self.timeout_s = timeout_s

    def _token(self) -> str:
        now = int(time.time())
        return jwt.encode(
            {
                "iss": self.issuer_id,
                "iat": now,
                "exp": now + 600,
                "aud": "appstoreconnect-v1",
                "bid": self.bundle_id,
            },
            self.private_key,
            algorithm="ES256",
            headers={"kid": self.key_id},
        )

    async def subscription_statuses(self, original_transaction_id: str) -> dict[str, Any] | None:
        url = f"{self.base_url}/inApps/v1/subscriptions/{quote(original_transaction_id, safe='')}"
        try:
            response = await self.http.get(
                url, headers={"Authorization": f"Bearer {self._token()}"}, timeout=self.timeout_s
            )
        except httpx2.HTTPError as exc:
            log.warning("app_store_api_error", error=type(exc).__name__)
            return None
        if response.status_code != HTTPStatus.OK:
            log.warning("app_store_api_failed", status=response.status_code)
            return None
        body: dict[str, Any] = response.json()
        return body


def renewal_auto_renew(verifier: AppleJwsVerifier, signed_renewal: str | None) -> bool | None:
    """autoRenewStatus from a signed renewal info (1 = on), or None when absent/invalid."""
    if not signed_renewal:
        return None
    try:
        info = verifier.verify(signed_renewal)
    except AppleVerificationError:
        return None
    return info.get("autoRenewStatus") == 1
