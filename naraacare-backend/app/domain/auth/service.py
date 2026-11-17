"""Authentication flows (doc 04 section 2.1, doc 07 SEC-1.1 to SEC-1.6).

Pattern: expected outcomes (wrong code, failed sign-in, lockout) are decided INSIDE the transaction
but raised only AFTER it has committed, so attempt counters and lockouts persist. Errors that must
undo the work (password reuse) are raised inside and roll everything back.

Enumeration (OQ-26): forgot-password and resend always answer the same way; unknown emails still
cost one Argon2id verification at sign-in. Sign-up keeps the explicit "already registered" message
(design copy) behind tight rate limits.

Storage (owner decision, 2026-11-03): email, OTP codes, installation ids, IPs and provider tokens
are stored in plain text; only passwords (Argon2id) and refresh tokens (SHA-256) are hashed.
"""

from __future__ import annotations

import hmac
import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

import structlog
from fastapi import BackgroundTasks

from app.core.config import Settings
from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.authz import Principal, Revocations
from app.core.security.hashing import Hasher
from app.core.security.oauth import AppleTokenClient, OAuthVerifier, ProviderIdentity
from app.core.security.passwords import check_confirmation, check_policy, is_reused
from app.core.security.tokens import TokenError, TokenService, new_refresh_token, refresh_token_hash
from app.domain.entitlements import service as entitlements
from app.integrations.email import EmailSender, send_quietly
from app.integrations.ops_monitor import NO_MONITOR, OpsMonitor
from app.middleware.rate_limit import RateLimiter
from app.repositories import auth_repo, privacy_repo, profile_repo
from app.repositories.base import Database, DbSession

log = structlog.get_logger(__name__)

OTP_TTL_S = 300
OTP_COOLDOWN_S = 30
LOCK_NOTICE_TTL_S = 3600
OTP_TEMPLATES = {
    "email_verification": "otp_verification",
    "password_reset": "password_reset",  # nosec B105 - template name, not a secret
    "reauth": "otp_verification",
}


@dataclass(frozen=True, slots=True)
class TokenPair:
    access_token: str
    access_expires_in_s: int
    refresh_token: str
    refresh_expires_in_s: int
    onboarding_required: bool


def new_otp() -> str:
    return f"{secrets.randbelow(10**6):06d}"


def _otp_failure(status: str | None, attempts_left: int | None) -> AppError:
    if status == "expired":
        return AppError(ErrorCode.OTP_EXPIRED)
    if status == "dead":
        return AppError(ErrorCode.OTP_LOCKED)
    return AppError(ErrorCode.OTP_INVALID, extra={"attempts_left": attempts_left or 0})


def _rate_limited(retry_after_s: int | None) -> AppError:
    retry = max(1, int(retry_after_s or 1))
    return AppError(
        ErrorCode.RATE_LIMITED,
        extra={"retry_after_s": retry},
        headers={"Retry-After": str(retry)},
    )


class AuthService:
    def __init__(
        self,
        *,
        settings: Settings,
        db: Database,
        tokens: TokenService,
        password_hasher: Hasher,
        oauth: OAuthVerifier,
        apple: AppleTokenClient | None,
        email: EmailSender,
        rate_limiter: RateLimiter,
        revocations: Revocations,
        store: Any,
        monitor: OpsMonitor = NO_MONITOR,
    ) -> None:
        self.monitor = monitor
        self.settings = settings
        self.db = db
        self.tokens = tokens
        self.passwords = password_hasher
        self.oauth = oauth
        self.apple = apple
        self.email = email
        self.limiter = rate_limiter
        self.revocations = revocations
        self.store = store  # in-process store (lockout-notice dedupe)

    # ------------------------------------------------------------------ helpers
    @staticmethod
    def code_matches(stored: str, given: str) -> bool:
        """Constant-time OTP comparison."""
        return hmac.compare_digest(stored.encode(), given.encode())

    def _send(self, background: BackgroundTasks, to: str, template: str, **values: str) -> None:
        """After a successful response (FastAPI drops background tasks when a route raises)."""
        background.add_task(send_quietly, self.email, to, template, values)

    async def _send_now(self, to: str, template: str, **values: str) -> None:
        """For emails that accompany an error response (lockout notice, new verification code)."""
        await send_quietly(self.email, to, template, values)

    async def _issue(
        self, session: DbSession, *, user_id: UUID, role: str, installation_id: UUID
    ) -> TokenPair:
        """Inside a transaction whose actor is ``user_id`` (just authenticated)."""
        refresh, refresh_hash = new_refresh_token()
        issued = await auth_repo.issue_refresh_token(
            session,
            user_id=user_id,
            token_hash=refresh_hash,
            installation_id=installation_id,
        )
        tier = (await entitlements.load(session, user_id)).tier
        profile = await profile_repo.get_profile(session, user_id)
        return TokenPair(
            access_token=self.tokens.issue_access(
                user_id=user_id, role=role, session_id=issued["family_id"], tier_hint=tier
            ),
            access_expires_in_s=self.tokens.access_ttl_s,
            refresh_token=refresh,
            refresh_expires_in_s=self.settings.REFRESH_TOKEN_TTL_DAYS * 86400,
            onboarding_required=profile is None or profile["onboarding_completed_at"] is None,
        )

    # ------------------------------------------------------------------ sign-up and codes
    async def signup(
        self,
        *,
        email: str,
        password: str,
        confirm_password: str,
        policy_versions: dict[str, str],
        installation_id: UUID,
        ip: str | None,
        background: BackgroundTasks,
    ) -> UUID:
        check_confirmation(password, confirm_password)
        check_policy(password, email=email)
        await self.limiter.enforce("auth_signup_email", email)
        code = new_otp()
        password_hash = await self.passwords.hash_async(password)

        async def work(s: DbSession) -> auth_repo.Outcome:
            outcome = await auth_repo.create_account(
                s,
                email=email,
                password_hash=password_hash,
                installation_id=installation_id,
                code=code,
            )
            if outcome.status == "ok":
                await s.set_actor(outcome["user_id"])
                for purpose, version in (
                    ("terms", policy_versions["terms"]),
                    ("privacy", policy_versions["privacy"]),
                ):
                    await privacy_repo.record_consent(
                        s,
                        user_id=outcome["user_id"],
                        purpose=purpose,
                        policy_version=version,
                        granted=True,
                        app_version=None,
                        ip=ip,
                    )
            return outcome

        outcome = await self.db.run(work)
        if outcome.status == "email_registered":
            raise AppError(ErrorCode.EMAIL_REGISTERED)
        if outcome.status != "ok":
            raise _rate_limited(outcome["retry_after_s"])
        self._send(background, email, "otp_verification", code=code)
        return UUID(str(outcome["challenge_id"]))

    async def verify_email(
        self, *, challenge_id: UUID, code: str, installation_id: UUID
    ) -> TokenPair:
        async def work(s: DbSession) -> tuple[auth_repo.Outcome, TokenPair | None]:
            challenge = await auth_repo.get_otp_challenge(s, challenge_id)
            if challenge is None or challenge.purpose != "email_verification":
                return auth_repo.Outcome({"status": "not_found"}), None
            code_ok = challenge.is_usable and self.code_matches(challenge.code, code)
            outcome = await auth_repo.verify_otp(s, challenge_id=challenge_id, code_ok=code_ok)
            if outcome.status != "ok":
                return outcome, None
            user_id: UUID = outcome["user_id"]
            await s.set_actor(user_id)
            pair = await self._issue(
                s,
                user_id=user_id,
                role="user",
                installation_id=installation_id,
            )
            return outcome, pair

        outcome, pair = await self.db.run(work)
        if outcome.status != "not_found":
            # Many wrong or expired codes in a row usually mean the emails are not arriving.
            self.monitor.otp_checked(ok=pair is not None)
        if pair is None:
            raise _otp_failure(outcome.status, outcome["attempts_left"])
        return pair

    async def resend(self, *, challenge_id: UUID, background: BackgroundTasks) -> int:
        """Same answer whether or not the challenge exists (forgot-password ids may be fake)."""
        code = new_otp()

        async def work(s: DbSession) -> tuple[auth_repo.Outcome, Any]:
            target = await auth_repo.otp_challenge_email(s, challenge_id)
            if target is None:
                return auth_repo.Outcome({"status": "not_found"}), None
            outcome = await auth_repo.resend_otp(s, challenge_id=challenge_id, code=code)
            return outcome, target

        outcome, target = await self.db.run(work)
        if outcome.status == "rate_limited":
            raise _rate_limited(outcome["retry_after_s"])
        if outcome.status == "ok" and target is not None:
            self._send(
                background, str(target["email"]), OTP_TEMPLATES[str(target["purpose"])], code=code
            )
        return OTP_COOLDOWN_S

    # ------------------------------------------------------------------ password sign-in
    async def _lock_notice(self, email: str, minutes: int) -> None:
        try:
            first = await self.store.set(f"locknotice:{email}", "1", ex=LOCK_NOTICE_TTL_S, nx=True)
        except Exception as exc:
            log.warning("lock_notice_dedupe_unavailable", exc_type=type(exc).__name__)
            first = True
        if first:
            await self._send_now(email, "lockout_notice", minutes=str(minutes))

    async def login(
        self,
        *,
        email: str,
        password: str,
        installation_id: UUID,
        ip: str | None,
        background: BackgroundTasks,
    ) -> TokenPair:
        await self.limiter.enforce("auth_login_account", email)

        async def lookup(s: DbSession) -> tuple[auth_repo.Account | None, datetime | None]:
            found = await auth_repo.find_account(s, email)
            if found is not None:
                return found, found.locked_until
            # Unknown emails lock out like real accounts, or the lockout would reveal which
            # emails are registered (doc 07 T26).
            return None, await auth_repo.unknown_email_locked_until(s, email)

        account, locked_until = await self.db.run(lookup)
        now = datetime.now(UTC)
        if locked_until is not None and locked_until > now:
            retry = max(1, int((locked_until - now).total_seconds()))
            raise AppError(
                ErrorCode.ACCOUNT_LOCKED,
                extra={"retry_after_s": retry},
                headers={"Retry-After": str(retry)},
            )
        if account is not None and account.password_hash:
            password_ok = await self.passwords.verify_async(account.password_hash, password)
        else:
            password_ok = await self.passwords.verify_dummy(password)

        if password_ok and account is not None and account.status == "pending_verification":
            challenge_id = await self._send_verification(email)
            raise AppError(
                ErrorCode.EMAIL_NOT_VERIFIED,
                extra={"challenge_id": str(challenge_id)} if challenge_id else None,
            )
        success = password_ok and account is not None and account.status == "active"

        async def work(s: DbSession) -> tuple[auth_repo.Outcome, TokenPair | None]:
            outcome = await auth_repo.record_login_attempt(s, email=email, ip=ip, success=success)
            if not success or account is None:
                return outcome, None
            await s.set_actor(account.user_id)
            if account.password_hash and self.passwords.needs_rehash(account.password_hash):
                await auth_repo.rehash_password(
                    s,
                    user_id=account.user_id,
                    old_hash=account.password_hash,
                    new_hash=await self.passwords.hash_async(password),
                )
            pair = await self._issue(
                s,
                user_id=account.user_id,
                role=account.role,
                installation_id=installation_id,
            )
            return outcome, pair

        outcome, pair = await self.db.run(work)
        if outcome.status == "locked":
            lock_end: datetime | None = outcome["locked_until"]
            retry = max(1, int((lock_end - now).total_seconds())) if lock_end else 60
            if account is not None:  # never email an address that has no account
                await self._lock_notice(email, minutes=max(1, -(-retry // 60)))
            raise AppError(
                ErrorCode.ACCOUNT_LOCKED,
                extra={"retry_after_s": retry},
                headers={"Retry-After": str(retry)},
            )
        if pair is None:
            raise AppError(ErrorCode.INVALID_CREDENTIALS)
        return pair

    async def _send_verification(self, email: str) -> UUID | None:
        code = new_otp()
        outcome = await self.db.run(
            lambda s: auth_repo.create_otp_challenge(
                s, email=email, purpose="email_verification", code=code
            )
        )
        if outcome.status != "ok":
            return None  # cooldown: the previous code is still valid
        await self._send_now(email, "otp_verification", code=code)
        return UUID(str(outcome["challenge_id"]))

    # ------------------------------------------------------------------ Google / Apple
    async def _verify_provider(self, provider: str, token: str, nonce: str) -> ProviderIdentity:
        try:
            if provider == "google":
                identity = await self.oauth.verify_google(token, nonce)
            else:
                identity = await self.oauth.verify_apple(token, nonce)
        except TokenError:
            self.monitor.oauth_checked(provider, ok=False)
            raise AppError(ErrorCode.UNAUTHENTICATED) from None
        except Exception:  # provider keys unreachable and the like: counted, then a 500
            self.monitor.oauth_checked(provider, ok=False)
            raise
        self.monitor.oauth_checked(provider, ok=True)
        return identity

    async def social_sign_in(
        self,
        *,
        provider: str,
        token: str,
        nonce: str,
        installation_id: UUID,
        authorization_code: str | None,
        background: BackgroundTasks,
    ) -> TokenPair:
        identity = await self._verify_provider(provider, token, nonce)
        subject = identity.subject

        async def work(s: DbSession) -> tuple[str, TokenPair | None, UUID | None, str | None]:
            existing = await auth_repo.find_identity(s, provider, subject)
            if existing is not None:
                if existing.status != "active":
                    return "inactive", None, None, None
                await s.set_actor(existing.user_id)
                pair = await self._issue(
                    s,
                    user_id=existing.user_id,
                    role=existing.role,
                    installation_id=installation_id,
                )
                return "ok", pair, existing.user_id, None
            if identity.email is None or not identity.email_verified:
                return "unverified", None, None, None
            outcome = await auth_repo.create_oauth_account(
                s,
                provider=provider,
                subject=subject,
                email=identity.email,
                installation_id=installation_id,
            )
            if outcome.status == "link_required":
                return "link_required", None, None, identity.email
            user_id: UUID = outcome["user_id"]
            await s.set_actor(user_id)
            pair = await self._issue(
                s, user_id=user_id, role="user", installation_id=installation_id
            )
            return "ok", pair, user_id, None

        status, pair, user_id, link_email = await self.db.run(work)
        if status == "link_required" and link_email is not None:
            link_token = self.tokens.issue_link(
                provider=provider, subject=subject, email=link_email
            )
            raise AppError(ErrorCode.LINK_REQUIRED, extra={"link_token": link_token})
        if pair is None or user_id is None:
            raise AppError(ErrorCode.UNAUTHENTICATED)
        if provider == "apple" and authorization_code and self.apple is not None:
            background.add_task(self.store_apple_token, user_id, subject, authorization_code)
        return pair

    async def store_apple_token(self, user_id: UUID, subject: str, authorization_code: str) -> None:
        """Background: exchange the code and keep Apple's refresh token for revocation (S15)."""
        if self.apple is None:
            return
        refresh = await self.apple.exchange_code(authorization_code)
        if refresh is None:
            return
        try:
            await self.db.run(
                lambda s: auth_repo.store_provider_token(
                    s,
                    user_id=user_id,
                    provider="apple",
                    subject=subject,
                    token=refresh,
                ),
                user_id=user_id,
            )
        except Exception as exc:  # background task: log and move on
            log.warning("apple_token_store_failed", exc_type=type(exc).__name__)

    async def link(
        self,
        *,
        link_token: str,
        password: str,
        installation_id: UUID,
        ip: str | None,
        background: BackgroundTasks,
    ) -> TokenPair:
        try:
            claims = self.tokens.verify_link(link_token)
        except TokenError:
            raise AppError(ErrorCode.UNAUTHENTICATED) from None
        account = await self.db.run(lambda s: auth_repo.find_account(s, claims.email))
        if account is not None and account.password_hash:
            password_ok = await self.passwords.verify_async(account.password_hash, password)
        else:
            password_ok = await self.passwords.verify_dummy(password)
        success = password_ok and account is not None and account.status == "active"

        async def work(s: DbSession) -> tuple[auth_repo.Outcome, TokenPair | None]:
            outcome = await auth_repo.record_login_attempt(
                s, email=claims.email, ip=ip, success=success
            )
            if not success or account is None:
                return outcome, None
            await s.set_actor(account.user_id)
            await auth_repo.link_identity(
                s,
                user_id=account.user_id,
                provider=claims.provider,
                subject=claims.subject,
                email=claims.email,
            )
            pair = await self._issue(
                s,
                user_id=account.user_id,
                role=account.role,
                installation_id=installation_id,
            )
            return outcome, pair

        outcome, pair = await self.db.run(work)
        if outcome.status == "locked":
            raise AppError(ErrorCode.ACCOUNT_LOCKED, extra={"retry_after_s": 60})
        if pair is None:
            raise AppError(ErrorCode.INVALID_CREDENTIALS)
        return pair

    # ------------------------------------------------------------------ sessions
    async def refresh(self, *, refresh_token: str, installation_id: UUID) -> TokenPair:
        new_token, new_hash = new_refresh_token()

        async def work(s: DbSession) -> tuple[auth_repo.Outcome, str | None, bool]:
            outcome = await auth_repo.rotate_refresh_token(
                s,
                token_hash=refresh_token_hash(refresh_token),
                new_token_hash=new_hash,
                installation_id=installation_id,
            )
            if outcome.status != "ok":
                return outcome, None, False
            user_id: UUID = outcome["user_id"]
            await s.set_actor(user_id)
            tier = (await entitlements.load(s, user_id)).tier
            profile = await profile_repo.get_profile(s, user_id)
            access = self.tokens.issue_access(
                user_id=user_id,
                role=str(outcome["role"]),
                session_id=outcome["family_id"],
                tier_hint=tier,
            )
            return outcome, access, profile is None or profile["onboarding_completed_at"] is None

        outcome, access, onboarding_required = await self.db.run(work)
        if access is None:
            log.info("refresh_rejected", status=outcome.status)
            raise AppError(ErrorCode.UNAUTHENTICATED)
        return TokenPair(
            access_token=access,
            access_expires_in_s=self.tokens.access_ttl_s,
            refresh_token=new_token,
            refresh_expires_in_s=self.settings.REFRESH_TOKEN_TTL_DAYS * 86400,
            onboarding_required=onboarding_required,
        )

    async def logout(self, principal: Principal) -> None:
        await self.db.run(
            lambda s: auth_repo.revoke_tokens(
                s,
                user_id=principal.user_id,
                scope="family",
                reason="logout",
                family_id=principal.session_id,
            ),
            user_id=principal.user_id,
        )
        await self.revocations.revoke_session(principal.session_id)

    async def logout_all(self, principal: Principal) -> None:
        await self.db.run(
            lambda s: auth_repo.revoke_tokens(
                s, user_id=principal.user_id, scope="all", reason="logout_all"
            ),
            user_id=principal.user_id,
        )
        await self.revocations.revoke_user(principal.user_id)

    # ------------------------------------------------------------------ re-authentication (S15)
    async def email_of(self, principal: Principal) -> str:
        profile = await self.db.run(
            lambda s: profile_repo.get_profile(s, principal.user_id), user_id=principal.user_id
        )
        if profile is None:
            raise AppError(ErrorCode.UNAUTHENTICATED)
        return str(profile["email"])

    async def start_reauth(self, principal: Principal, *, background: BackgroundTasks) -> UUID:
        """Emails a 6-digit code (purpose ``reauth``) for accounts without a password (Google /
        Apple sign-in) before an export or deletion. 30 s cooldown and 3 per hour per address."""
        email = await self.email_of(principal)
        await self.limiter.enforce("auth_password_forgot_email", email)
        code = new_otp()
        outcome = await self.db.run(
            lambda s: auth_repo.create_otp_challenge(s, email=email, purpose="reauth", code=code)
        )
        if outcome.status != "ok":
            raise _rate_limited(OTP_COOLDOWN_S)
        self._send(background, email, OTP_TEMPLATES["reauth"], code=code)
        return UUID(str(outcome["challenge_id"]))

    async def verify_reauth(
        self,
        principal: Principal,
        *,
        password: str | None,
        challenge_id: UUID | None,
        code: str | None,
        ip: str | None,
    ) -> None:
        """Raises unless the caller just proved it is them: the account password, or a ``reauth``
        code sent to their own address. Failed passwords count towards the login lockout."""
        if password is not None:
            email = await self.email_of(principal)
            account = await self.db.run(lambda s: auth_repo.find_account(s, email))
            if account is not None and account.password_hash:
                ok = await self.passwords.verify_async(account.password_hash, password)
            else:
                ok = await self.passwords.verify_dummy(password)
            if ok:
                return
            outcome = await self.db.run(
                lambda s: auth_repo.record_login_attempt(s, email=email, ip=ip, success=False)
            )
            if outcome.status == "locked":
                raise AppError(ErrorCode.ACCOUNT_LOCKED, extra={"retry_after_s": 60})
            raise AppError(ErrorCode.INVALID_CREDENTIALS, fields=["password"])
        if challenge_id is None or code is None:
            raise AppError(ErrorCode.VALIDATION_FAILED, fields=["password"])

        async def work(s: DbSession) -> auth_repo.Outcome:
            challenge = await auth_repo.get_otp_challenge(s, challenge_id)
            if (
                challenge is None
                or challenge.purpose != "reauth"
                or challenge.user_id != principal.user_id
            ):
                return auth_repo.Outcome({"status": "not_found"})
            code_ok = challenge.is_usable and self.code_matches(challenge.code, code)
            return await auth_repo.verify_otp(s, challenge_id=challenge_id, code_ok=code_ok)

        outcome = await self.db.run(work)
        if outcome.status != "ok":
            raise _otp_failure(outcome.status, outcome["attempts_left"])

    # ------------------------------------------------------------------ passwords
    async def forgot_password(self, *, email: str, background: BackgroundTasks) -> UUID:
        """Always answers with a challenge id; only a real account gets an email (OQ-26)."""
        await self.limiter.enforce("auth_password_forgot_email", email)
        code = new_otp()
        outcome = await self.db.run(
            lambda s: auth_repo.create_otp_challenge(
                s, email=email, purpose="password_reset", code=code
            )
        )
        if outcome.status == "ok":
            self._send(background, email, "password_reset", code=code)
            return UUID(str(outcome["challenge_id"]))
        return uuid.uuid4()

    async def reset_password(
        self,
        *,
        challenge_id: UUID,
        code: str,
        new_password: str,
        confirm_password: str,
        background: BackgroundTasks,
    ) -> None:
        check_confirmation(new_password, confirm_password)
        check_policy(new_password)
        new_hash = await self.passwords.hash_async(new_password)

        async def work(s: DbSession) -> tuple[auth_repo.Outcome, UUID | None, str | None]:
            challenge = await auth_repo.get_otp_challenge(s, challenge_id)
            if challenge is None or challenge.purpose != "password_reset":
                return auth_repo.Outcome({"status": "not_found"}), None, None
            code_ok = challenge.is_usable and self.code_matches(challenge.code, code)
            outcome = await auth_repo.verify_otp(s, challenge_id=challenge_id, code_ok=code_ok)
            if outcome.status != "ok":
                return outcome, None, None
            user_id: UUID = outcome["user_id"]
            await s.set_actor(user_id)
            history = await auth_repo.password_history(s, user_id)
            if await is_reused(self.passwords, history, new_password):
                raise AppError(ErrorCode.PASSWORD_REUSED, fields=["new_password"])
            await auth_repo.set_password(
                s, user_id=user_id, password_hash=new_hash, keep_family_id=None
            )
            profile = await profile_repo.get_profile(s, user_id)
            return outcome, user_id, str(profile["email"]) if profile else None

        outcome, user_id, email = await self.db.run(work)
        if user_id is None:
            raise _otp_failure(outcome.status, outcome["attempts_left"])
        await self.revocations.revoke_user(user_id)
        if email is not None:
            self._send(background, email, "password_changed")

    async def change_password(
        self,
        principal: Principal,
        *,
        current_password: str,
        new_password: str,
        confirm_password: str,
        ip: str | None,
        background: BackgroundTasks,
    ) -> None:
        check_confirmation(new_password, confirm_password)
        profile = await self.db.run(
            lambda s: profile_repo.get_profile(s, principal.user_id), user_id=principal.user_id
        )
        if profile is None:
            raise AppError(ErrorCode.UNAUTHENTICATED)
        email = str(profile["email"])
        check_policy(new_password, email=email)
        account = await self.db.run(lambda s: auth_repo.find_account(s, email))
        if account is not None and account.password_hash:
            current_ok = await self.passwords.verify_async(account.password_hash, current_password)
        else:
            current_ok = await self.passwords.verify_dummy(current_password)
        new_hash = await self.passwords.hash_async(new_password)

        async def work(s: DbSession) -> auth_repo.Outcome:
            if not current_ok:
                return await auth_repo.record_login_attempt(s, email=email, ip=ip, success=False)
            history = await auth_repo.password_history(s, principal.user_id)
            if await is_reused(self.passwords, history, new_password):
                raise AppError(ErrorCode.PASSWORD_REUSED, fields=["new_password"])
            await auth_repo.set_password(
                s,
                user_id=principal.user_id,
                password_hash=new_hash,
                keep_family_id=principal.session_id,
            )
            return auth_repo.Outcome({"status": "ok"})

        outcome = await self.db.run(work, user_id=principal.user_id)
        if outcome.status == "locked":
            raise AppError(ErrorCode.ACCOUNT_LOCKED, extra={"retry_after_s": 60})
        if outcome.status != "ok":
            raise AppError(ErrorCode.INVALID_CREDENTIALS, fields=["current_password"])
        # Other devices' refresh tokens are gone; end their access tokens now too (SEC-1.6).
        await self.revocations.revoke_user(principal.user_id, keep_session=principal.session_id)
        self._send(background, email, "password_changed")
