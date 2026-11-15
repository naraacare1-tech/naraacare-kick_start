"""Argon2id password hashing (doc 07 SEC-1.1): 64 MiB, t=3, p=2, 16-byte salt, 32-byte hash (from
settings, which enforce a floor). Passwords are the only user data stored hashed; OTP codes are
stored in plain text (owner decision, 2026-11-03) and compared in constant time.

Hashing is CPU-bound (~50-150 ms), so the async helpers run it in a worker thread and never block
the event loop. ``verify_dummy`` spends the same time when an account does not exist, so response
time does not reveal which emails are registered (OQ-26).
"""

from __future__ import annotations

import anyio.to_thread
from argon2 import PasswordHasher, Type
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

SALT_BYTES = 16
HASH_BYTES = 32


class Hasher:
    def __init__(self, *, memory_kib: int, time_cost: int, parallelism: int) -> None:
        self._ph = PasswordHasher(
            time_cost=time_cost,
            memory_cost=memory_kib,
            parallelism=parallelism,
            hash_len=HASH_BYTES,
            salt_len=SALT_BYTES,
            type=Type.ID,
        )
        self._dummy = self._ph.hash("naraacare-dummy-password-for-timing")

    def hash(self, secret: str) -> str:
        return self._ph.hash(secret)

    def verify(self, stored_hash: str, secret: str) -> bool:
        try:
            return self._ph.verify(stored_hash, secret)
        except (VerifyMismatchError, VerificationError, InvalidHashError):
            return False

    def needs_rehash(self, stored_hash: str) -> bool:
        """True when the stored hash used older parameters: rehash after a successful login."""
        return self._ph.check_needs_rehash(stored_hash)

    async def hash_async(self, secret: str) -> str:
        return await anyio.to_thread.run_sync(self.hash, secret)

    async def verify_async(self, stored_hash: str, secret: str) -> bool:
        return await anyio.to_thread.run_sync(self.verify, stored_hash, secret)

    async def verify_dummy(self, secret: str) -> bool:
        """Same cost as a real verification; always False."""
        await anyio.to_thread.run_sync(self.verify, self._dummy, secret)
        return False


def password_hasher(*, memory_kib: int, time_cost: int, parallelism: int) -> Hasher:
    return Hasher(memory_kib=memory_kib, time_cost=time_cost, parallelism=parallelism)
