"""Argon2id parameters and behaviour (doc 07 SEC-1.1, SEC-1.3)."""

from __future__ import annotations

import regex

from app.core.security.hashing import Hasher, password_hasher

# Same shape the database accepts (common.argon2_hash).
DB_FORMAT = regex.compile(
    r"^\$argon2id\$v=19\$m=[0-9]+,t=[0-9]+,p=[0-9]+\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+$"
)


def test_password_profile_parameters() -> None:
    stored = password_hasher(memory_kib=65536, time_cost=3, parallelism=2).hash("Correct1Horse")
    assert stored.startswith("$argon2id$v=19$m=65536,t=3,p=2$")
    assert DB_FORMAT.match(stored)
    assert len(stored) <= 256


def test_verify_and_salt() -> None:
    hasher = Hasher(memory_kib=16384, time_cost=2, parallelism=1)
    first, second = hasher.hash("123456"), hasher.hash("123456")
    assert first != second  # random salt
    assert hasher.verify(first, "123456")
    assert not hasher.verify(first, "123457")
    assert not hasher.verify("not-a-hash", "123456")


def test_needs_rehash_when_parameters_change() -> None:
    old = Hasher(memory_kib=16384, time_cost=2, parallelism=1).hash("Correct1Horse")
    current = password_hasher(memory_kib=65536, time_cost=3, parallelism=2)
    assert current.needs_rehash(old)
    assert not current.needs_rehash(current.hash("Correct1Horse"))


async def test_async_helpers_and_dummy_verification() -> None:
    hasher = Hasher(memory_kib=16384, time_cost=2, parallelism=1)
    stored = await hasher.hash_async("654321")
    assert await hasher.verify_async(stored, "654321")
    assert await hasher.verify_dummy("654321") is False
