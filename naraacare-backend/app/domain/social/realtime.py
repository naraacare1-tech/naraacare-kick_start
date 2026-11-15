"""Realtime delivery for circles (doc 04 section 2.9), in process memory: no Redis in the API.

* ``TicketStore``: ``POST /realtime/ticket`` hands out a random 256-bit ticket that opens one
  WebSocket within 30 s and is then gone (single use). The access token never travels in a URL,
  where proxies and logs could keep it.
* ``Hub``: the open sockets of each user, each tied to the session (refresh-token family) whose
  access token asked for its ticket. Events go to the users a database call just returned (active
  members), so a removed member stops receiving at once; a revoked session (logout, logout-all,
  password change/reset, account deletion) has its sockets closed at once (``end_sessions``, wired
  to ``Revocations``).
* Both live in this process only, so the API must run as ONE process (as for the in-memory rate
  limits). Scaling out needs a shared broker (Redis pub/sub) first; see docs/pending-tasks.md.
"""

from __future__ import annotations

import asyncio
import secrets
import time
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from typing import Any, Protocol
from uuid import UUID

import structlog
from fastapi.encoders import jsonable_encoder

log = structlog.get_logger(__name__)

TICKET_TTL_S = 30
TICKET_BYTES = 32
MAX_TICKETS = 10_000  # bounds memory if tickets are requested and never used
MAX_SOCKETS_PER_USER = 5  # the oldest socket is closed when a sixth opens


@dataclass(frozen=True, slots=True)
class Ticket:
    user_id: UUID
    session_id: UUID
    expires_at: float


class TicketStore:
    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        self._tickets: dict[str, Ticket] = {}
        self._clock = clock

    def issue(self, user_id: UUID, session_id: UUID) -> str:
        self._purge()
        if len(self._tickets) >= MAX_TICKETS:
            # Drop the oldest; a client whose ticket vanished simply asks for a new one.
            self._tickets.pop(next(iter(self._tickets)))
        ticket = secrets.token_urlsafe(TICKET_BYTES)
        self._tickets[ticket] = Ticket(user_id, session_id, self._clock() + TICKET_TTL_S)
        return ticket

    def redeem(self, ticket: str) -> Ticket | None:
        """The ticket if it is known and fresh; it is removed either way."""
        entry = self._tickets.pop(ticket, None)
        if entry is None or entry.expires_at <= self._clock():
            return None
        return entry

    def _purge(self) -> None:
        now = self._clock()
        for key in [k for k, t in self._tickets.items() if t.expires_at <= now]:
            del self._tickets[key]


class Socket(Protocol):
    async def send_json(self, data: Any, mode: str = "text") -> None: ...
    async def close(self, code: int = 1000, reason: str | None = None) -> None: ...


class Hub:
    def __init__(self) -> None:
        self._sockets: dict[UUID, list[Socket]] = {}
        self._session_of: dict[int, UUID] = {}  # id(socket) -> the session that opened it

    async def add(self, user_id: UUID, socket: Socket, session_id: UUID) -> None:
        sockets = self._sockets.setdefault(user_id, [])
        sockets.append(socket)
        self._session_of[id(socket)] = session_id
        while len(sockets) > MAX_SOCKETS_PER_USER:
            oldest = sockets.pop(0)
            self._session_of.pop(id(oldest), None)
            await _close_quietly(oldest, 4000)

    def remove(self, user_id: UUID, socket: Socket) -> None:
        self._session_of.pop(id(socket), None)
        sockets = self._sockets.get(user_id)
        if not sockets:
            return
        if socket in sockets:
            sockets.remove(socket)
        if not sockets:
            del self._sockets[user_id]

    async def end_sessions(
        self,
        *,
        user_id: UUID | None = None,
        session_id: UUID | None = None,
        keep_session: UUID | None = None,
    ) -> None:
        """Close (4401) the sockets of a revoked session, or of all a user's sessions but one."""
        targets = [
            (owner, socket)
            for owner, sockets in self._sockets.items()
            if user_id is None or owner == user_id
            for socket in sockets
            if (session := self._session_of.get(id(socket))) != keep_session
            and (session_id is None or session == session_id)
        ]
        for owner, socket in targets:
            self.remove(owner, socket)
            await _close_quietly(socket, 4401)

    def connected(self, user_id: UUID) -> int:
        return len(self._sockets.get(user_id, ()))

    async def publish(self, user_ids: Iterable[UUID], event: dict[str, Any]) -> None:
        """Send ``event`` to every open socket of these users; a failing socket is dropped."""
        targets = [(u, s) for u in set(user_ids) for s in list(self._sockets.get(u, ()))]
        if not targets:
            return
        payload = jsonable_encoder(event)  # UUIDs and datetimes as JSON strings
        results = await asyncio.gather(
            *(s.send_json(payload) for _, s in targets), return_exceptions=True
        )
        for (user_id, socket), result in zip(targets, results, strict=True):
            if isinstance(result, Exception):
                log.info("ws_send_failed", exc_type=type(result).__name__)
                self.remove(user_id, socket)

    async def close_all(self) -> None:
        for sockets in list(self._sockets.values()):
            for socket in list(sockets):
                await _close_quietly(socket, 1001)
        self._sockets.clear()
        self._session_of.clear()


async def _close_quietly(socket: Socket, code: int) -> None:
    try:
        await socket.close(code=code)
    except Exception as exc:  # already closed by the peer
        log.debug("ws_close_failed", exc_type=type(exc).__name__)
