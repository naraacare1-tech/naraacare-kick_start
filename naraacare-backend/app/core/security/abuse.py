"""What happens when input is rejected as unsafe (doc 07 §4.4 "Abuse").

1. A ``validation_rejected`` security event (field name + counts, never the value) is queued.
2. The principal (user if signed in, else IP) gets a rejection counted towards the penalty box.
3. Crossing the alert threshold logs ``security_alert`` at ERROR (Sentry + monitoring alert) and
   records a ``rate_limited`` security event.
"""

from __future__ import annotations

from uuid import UUID

import structlog
from fastapi import Request

from app.core.security.request_context import current_request_id, current_user_id
from app.middleware.rate_limit import client_ip, client_ip_or_none
from app.repositories.audit import SecurityEvent

log = structlog.get_logger(__name__)


async def on_unsafe_input(fields: list[str], request: Request) -> None:
    state = request.app.state
    ip = client_ip(request.scope)
    user_id = current_user_id()
    request_id = current_request_id()
    principal = f"user:{user_id}" if user_id else f"ip:{ip}"
    event_ip = client_ip_or_none(request.scope)
    event_request_id = UUID(request_id) if request_id else None
    state.security_events.submit(
        SecurityEvent(
            event_type="validation_rejected",
            user_id=user_id,
            ip=event_ip,
            request_id=event_request_id,
            field_name=fields[0],
            details={"field_count": len(fields), "method": request.method.lower()},
        )
    )
    if await state.rate_limiter.record_unsafe_rejection(principal):
        log.error("security_alert", reason="unsafe_input_burst")
        state.security_events.submit(
            SecurityEvent(
                event_type="rate_limited",
                user_id=user_id,
                ip=event_ip,
                request_id=event_request_id,
                details={"reason": "unsafe_input_burst"},
            )
        )
