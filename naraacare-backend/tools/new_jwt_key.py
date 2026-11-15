"""Create an Ed25519 key pair for access tokens (doc 07 SEC-1.2). No cloud service is involved.

Usage:
    python tools/new_jwt_key.py --kid k2

Prints two lines: the private key as one-line JSON string (store it in the secret manager as
JWT_PRIVATE_KEY_PEM, unescaped) and a JSON fragment {"k2": "<public key PEM>"} to merge into
JWT_PUBLIC_KEYS_JSON. Rotation: add the new public key, deploy, switch JWT_PRIVATE_KEY_PEM and
JWT_ACTIVE_KID, and remove the old public key after the access-token lifetime (15 min) has passed.
Nothing is written to disk.
"""

from __future__ import annotations

import argparse
import json

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--kid", required=True, help="key id, e.g. k2")
    args = parser.parse_args()
    key = Ed25519PrivateKey.generate()
    private_pem = key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    ).decode()
    public_pem = (
        key.public_key()
        .public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
        .decode()
    )
    print(json.dumps(private_pem))
    print(json.dumps({args.kid: public_pem}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
