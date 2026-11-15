"""Google service-account access tokens (OAuth 2.0 JWT bearer flow), shared by FCM (S09) and the
Play Developer API (S11). An RS256 assertion signed with the service-account key is exchanged at the
configured token URL (never the one inside the key file) for a one-hour access token, cached until
5 minutes before it expires. Keys and tokens are never logged.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from http import HTTPStatus

import httpx2
import jwt
import structlog

log = structlog.get_logger(__name__)


@dataclass(frozen=True, slots=True)
class ServiceAccount:
    project_id: str
    client_email: str
    private_key: str

    @classmethod
    def parse(cls, raw: str) -> ServiceAccount | None:
        try:
            data = json.loads(raw)
        except ValueError:
            return None
        if not isinstance(data, dict) or data.get("type") != "service_account":
            return None
        try:
            return cls(str(data["project_id"]), str(data["client_email"]), str(data["private_key"]))
        except KeyError:
            return None


class GoogleTokenSource:
    def __init__(
        self,
        http: httpx2.AsyncClient,
        account: ServiceAccount,
        *,
        scope: str,
        token_url: str,
        timeout_s: float = 5.0,
    ) -> None:
        self.http = http
        self.account = account
        self.scope = scope
        self.token_url = token_url
        self.timeout_s = timeout_s
        self._token: str | None = None
        self._expires_at = 0.0

    def invalidate(self) -> None:
        self._token = None

    async def token(self) -> str | None:
        now = time.time()
        if self._token is not None and now < self._expires_at - 300:
            return self._token
        assertion = jwt.encode(
            {
                "iss": self.account.client_email,
                "scope": self.scope,
                "aud": self.token_url,
                "iat": int(now),
                "exp": int(now) + 3600,
            },
            self.account.private_key,
            algorithm="RS256",
        )
        response = await self.http.post(
            self.token_url,
            data={
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": assertion,
            },
            timeout=self.timeout_s,
        )
        if response.status_code != HTTPStatus.OK:
            log.warning("google_token_failed", status=response.status_code, scope=self.scope)
            return None
        body = response.json()
        self._token = str(body["access_token"])
        self._expires_at = now + float(body.get("expires_in", 3600))
        return self._token
