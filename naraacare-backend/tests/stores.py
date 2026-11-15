"""Test stand-ins for the app stores: an Apple-like certificate chain that signs JWS payloads, a
Google-like OIDC signer for Pub/Sub pushes, and a scripted Google Play client.

The verifiers under test are the production ones; only their trust anchors (root certificate,
JWKS) are swapped for these test keys. An ``attacker`` chain/signer looks identical but is not
trusted, which is what a forgery is.
"""

from __future__ import annotations

import base64
import json
import time
import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from cryptography.x509.oid import NameOID

from app.core.security.oauth import JwksCache
from app.integrations.app_store import INTERMEDIATE_OID, LEAF_OID, AppleJwsVerifier
from app.integrations.google_play import PlayError, PlaySubscription
from app.integrations.pubsub_auth import PubSubVerifier

# The .env.example values the test app runs with.
BUNDLE_ID = "com.naraacare.app.dev"
PACKAGE_NAME = "com.naraacare.app.dev"
PUSH_AUDIENCE = "http://localhost:8000/api/v1/billing/webhooks/google"
PUSH_EMAIL = "rtdn@dummy-project.iam.gserviceaccount.com"


def _name(common: str) -> x509.Name:
    return x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common)])


def _cert(
    subject: str,
    key: ec.EllipticCurvePrivateKey,
    issuer: str,
    issuer_key: ec.EllipticCurvePrivateKey,
    *,
    ca: bool,
    oid: x509.ObjectIdentifier | None = None,
) -> x509.Certificate:
    now = datetime.now(UTC)
    builder = (
        x509.CertificateBuilder()
        .subject_name(_name(subject))
        .issuer_name(_name(issuer))
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(days=1))
        .not_valid_after(now + timedelta(days=30))
        .add_extension(x509.BasicConstraints(ca=ca, path_length=None), critical=True)
    )
    if oid is not None:
        builder = builder.add_extension(
            x509.UnrecognizedExtension(oid, b"\x05\x00"), critical=False
        )
    return builder.sign(issuer_key, hashes.SHA256())


@dataclass
class ApplePki:
    """Root -> intermediate (WWDR OID) -> leaf (receipt-signing OID), like Apple's chain."""

    root_key: ec.EllipticCurvePrivateKey = field(
        default_factory=lambda: ec.generate_private_key(ec.SECP256R1())
    )
    mid_key: ec.EllipticCurvePrivateKey = field(
        default_factory=lambda: ec.generate_private_key(ec.SECP256R1())
    )
    leaf_key: ec.EllipticCurvePrivateKey = field(
        default_factory=lambda: ec.generate_private_key(ec.SECP256R1())
    )

    def __post_init__(self) -> None:
        self.root = _cert("Test Root", self.root_key, "Test Root", self.root_key, ca=True)
        self.mid = _cert(
            "Test WWDR", self.mid_key, "Test Root", self.root_key, ca=True, oid=INTERMEDIATE_OID
        )
        self.leaf = _cert(
            "Test Signing", self.leaf_key, "Test WWDR", self.mid_key, ca=False, oid=LEAF_OID
        )

    def sign(self, claims: dict[str, Any], *, with_oids: bool = True) -> str:
        chain = [self.leaf, self.mid, self.root]
        if not with_oids:  # a valid chain whose leaf is an ordinary certificate
            plain = _cert("Plain", self.leaf_key, "Test WWDR", self.mid_key, ca=False)
            chain = [plain, self.mid, self.root]
        x5c = [base64.b64encode(c.public_bytes(serialization.Encoding.DER)).decode() for c in chain]
        return jwt.encode(claims, self.leaf_key, algorithm="ES256", headers={"x5c": x5c})


def apple_transaction(
    original_transaction_id: str, *, product_id: str = "star_monthly", days: int = 30, **extra: Any
) -> dict[str, Any]:
    now = int(time.time() * 1000)
    return {
        "bundleId": BUNDLE_ID,
        "environment": "Sandbox",
        "type": "Auto-Renewable Subscription",
        "productId": product_id,
        "originalTransactionId": original_transaction_id,
        "transactionId": str(uuid.uuid4().int)[:16],
        "purchaseDate": now - 60_000,
        "expiresDate": now + days * 86_400_000,
        "price": 199000,
        "currency": "INR",
        **extra,
    }


def apple_notification(
    pki: ApplePki, transaction: dict[str, Any], *, type_: str = "SUBSCRIBED", **extra: Any
) -> str:
    return pki.sign(
        {
            "notificationType": type_,
            "subtype": extra.pop("subtype", ""),
            "notificationUUID": str(uuid.uuid4()),
            "data": {
                "bundleId": BUNDLE_ID,
                "environment": "Sandbox",
                "signedTransactionInfo": pki.sign(transaction),
                **extra,
            },
            "signedDate": int(time.time() * 1000),
        }
    )


@dataclass
class GoogleOidc:
    """Signs Pub/Sub push tokens (RS256, like Google); ``jwks`` is what the verifier trusts."""

    key: rsa.RSAPrivateKey = field(
        default_factory=lambda: rsa.generate_private_key(public_exponent=65537, key_size=2048)
    )
    kid: str = "test-google-key"

    @property
    def jwks(self) -> dict[str, Any]:
        jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(self.key.public_key()))
        return {"keys": [{**jwk, "kid": self.kid, "alg": "RS256", "use": "sig"}]}

    def token(self, **overrides: Any) -> str:
        now = int(time.time())
        claims = {
            "iss": "https://accounts.google.com",
            "aud": PUSH_AUDIENCE,
            "email": PUSH_EMAIL,
            "email_verified": True,
            "iat": now,
            "exp": now + 600,
            "sub": "1234567890",
            **overrides,
        }
        claims = {k: v for k, v in claims.items() if v is not None}
        return jwt.encode(claims, self.key, algorithm="RS256", headers={"kid": self.kid})


def pubsub_body(data: dict[str, Any], message_id: str | None = None) -> bytes:
    encoded = base64.b64encode(json.dumps(data).encode()).decode()
    return json.dumps(
        {
            "message": {"data": encoded, "messageId": message_id or str(uuid.uuid4().int)[:12]},
            "subscription": "projects/naraacare-test/subscriptions/rtdn",
        }
    ).encode()


@dataclass
class FakePlay:
    """Google Play Developer API stand-in: known purchase tokens -> subscription state."""

    subscriptions: dict[str, PlaySubscription] = field(default_factory=dict)
    acknowledged: list[str] = field(default_factory=list)

    def add(
        self,
        token: str,
        *,
        product_id: str = "star_monthly",
        status: str = "active",
        days: int = 30,
    ) -> None:
        end = datetime.now(UTC) + timedelta(days=days)
        self.subscriptions[token] = PlaySubscription(
            product_id=product_id,
            status=status,
            auto_renew=status == "active",
            period_start=end - timedelta(days=30),
            period_end=end,
            environment="sandbox",
            acknowledged=False,
            order_id=f"GPA.{uuid.uuid4().hex[:8]}",
        )

    async def subscription(self, purchase_token: str) -> PlaySubscription:
        try:
            return self.subscriptions[purchase_token]
        except KeyError:
            raise PlayError("unknown token") from None

    async def acknowledge(self, product_id: str, purchase_token: str) -> bool:
        self.acknowledged.append(purchase_token)
        return True


@dataclass
class Stores:
    """Everything a billing test needs, plus the app.state entries that plug it in."""

    pki: ApplePki = field(default_factory=ApplePki)
    oidc: GoogleOidc = field(default_factory=GoogleOidc)
    play: FakePlay = field(default_factory=FakePlay)

    def state(self) -> dict[str, Any]:
        async def fetch(_: str) -> dict[str, Any]:
            return self.oidc.jwks

        return {
            "apple_verifier": AppleJwsVerifier(
                [self.pki.root], bundle_id=BUNDLE_ID, environment="Sandbox"
            ),
            "pubsub_verifier": PubSubVerifier(
                JwksCache("https://jwks.test/certs", fetch),
                audience=PUSH_AUDIENCE,
                service_account_email=PUSH_EMAIL,
            ),
            "play_client": self.play,
        }
