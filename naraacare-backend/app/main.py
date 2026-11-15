"""App factory. Run with:
    uvicorn app.main:create_app --factory --no-access-log --ws-max-size 8192 --proxy-headers
        --forwarded-allow-ips=<load balancer addresses>
One process only: rate limits, revocations, WebSocket tickets and fan-out are in memory.

Request pipeline, outer to inner (doc 03 §4):
    RequestId -> AccessLog -> SecurityHeaders -> ErrorShield -> TrustedHost -> DocsAuth
    -> BodySizeLimit -> CORS -> RateLimit -> router -> auth / entitlement dependencies
    -> Safe* validation -> domain
    -> repository (app.user_id / app.request_id per transaction, stored functions only)
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

import httpx2
import structlog
from fastapi import FastAPI
from starlette.middleware.cors import CORSMiddleware
from starlette.middleware.trustedhost import TrustedHostMiddleware

from app.api.v1.routers import (
    admin_foods,
    auth,
    billing,
    chat,
    circles,
    foods,
    health,
    hydration,
    me,
    meals,
    notifications,
    nutrition,
    people,
    privacy,
    reference,
    reports,
    rin,
    sleep,
)
from app.core.config import Settings, load_settings
from app.core.exceptions import install_exception_handlers
from app.core.logging import configure_logging
from app.core.memory_store import MemoryStore
from app.core.security.abuse import on_unsafe_input
from app.core.security.authz import Revocations
from app.core.security.hashing import password_hasher
from app.core.security.oauth import (
    AppleTokenClient,
    JwksCache,
    OAuthVerifier,
    http_fetcher,
    load_apple_private_key,
)
from app.core.security.tokens import build_token_service
from app.db.engine import create_engines
from app.domain.ai.drink_estimator import DrinkEstimator, OpenAIDrinkClient
from app.domain.ai.pricing import AiPrices, inr_to_micro
from app.domain.ai.rin_model import OpenAIRinModel, RinModel
from app.domain.ai.rin_service import RinService
from app.domain.auth.service import AuthService
from app.domain.billing.service import BillingService
from app.domain.entitlements.service import EntitlementService
from app.domain.hydration.service import HydrationService
from app.domain.notifications.service import NotificationService
from app.domain.nutrition.service import NutritionService
from app.domain.privacy.service import PrivacyService
from app.domain.profile.service import ProfileService
from app.domain.reference import ReferenceCache
from app.domain.referral.service import ReferralService
from app.domain.reports.service import ReportService
from app.domain.sleep.service import SleepService
from app.domain.social.realtime import Hub, TicketStore
from app.domain.social.service import SocialService
from app.domain.support.service import SupportContact, SupportService
from app.domain.sync.service import SyncService
from app.integrations.app_store import AppleJwsVerifier, load_roots
from app.integrations.email import EmailSender, OutboxSender, SmtpSender
from app.integrations.google_oauth import ServiceAccount
from app.integrations.google_play import GooglePlayClient
from app.integrations.open_food_facts import OpenFoodFacts
from app.integrations.pubsub_auth import PubSubVerifier
from app.integrations.storage import build_storage
from app.middleware.access_log import AccessLogMiddleware
from app.middleware.body_size_limit import BodySizeLimitMiddleware
from app.middleware.docs_auth import DocsBasicAuthMiddleware
from app.middleware.error_shield import ErrorShieldMiddleware
from app.middleware.rate_limit import RateLimiter, RateLimitMiddleware
from app.middleware.request_id import RequestIdMiddleware
from app.middleware.security_headers import DOCS_PREFIXES, SecurityHeadersMiddleware
from app.repositories.audit import SecurityEventWriter
from app.repositories.base import Database

log = structlog.get_logger(__name__)

API_PREFIX = "/api/v1"
# Routes allowed a larger body than MAX_BODY_BYTES (support attachments, Session 14).
UPLOAD_ROUTES = (f"{API_PREFIX}/support/tickets",)


def _secret(value: Any) -> str | None:
    return value.get_secret_value() if value is not None else None


def _email_sender(settings: Settings) -> EmailSender:
    if settings.EMAIL_BACKEND == "outbox":
        return OutboxSender(
            sender=settings.EMAIL_FROM_ADDRESS, directory=Path(settings.EMAIL_OUTBOX_DIR)
        )
    return SmtpSender(
        sender=settings.EMAIL_FROM_ADDRESS,
        host=settings.SMTP_HOST or "",
        port=settings.SMTP_PORT,
        username=settings.SMTP_USERNAME,
        password=_secret(settings.SMTP_PASSWORD),
    )


def _apple_client(settings: Settings, http: httpx2.AsyncClient) -> AppleTokenClient | None:
    key = load_apple_private_key(settings.APPLE_SIWA_PRIVATE_KEY_P8.get_secret_value())
    if key is None:
        if settings.APP_ENV != "dev":
            raise RuntimeError("APPLE_SIWA_PRIVATE_KEY_P8 is not a usable EC private key")
        log.warning("apple_code_exchange_disabled", reason="no Sign in with Apple key (dev)")
        return None
    return AppleTokenClient(
        http=http,
        token_url=settings.APPLE_TOKEN_URL,
        team_id=settings.APPLE_TEAM_ID,
        client_id=settings.APPLE_BUNDLE_ID,
        key_id=settings.APPLE_SIWA_KEY_ID,
        private_key=key,
    )


def _drink_estimator(settings: Settings) -> DrinkEstimator:
    """OpenAI when Rin is enabled with a real key; otherwise every estimate is the product
    default factor."""
    key = _secret(settings.OPENAI_API_KEY)
    client = (
        OpenAIDrinkClient(
            api_key=key, model=settings.RIN_MODEL, max_tokens=settings.RIN_MAX_OUTPUT_TOKENS
        )
        if settings.RIN_ENABLED and key and not key.startswith("dummy")
        else None
    )
    return DrinkEstimator(client)


def _init_auth(app: FastAPI) -> None:
    """Token, OAuth, email and the auth/profile services (Session 05)."""
    settings: Settings = app.state.settings
    state = app.state
    if getattr(state, "tokens", None) is None:
        state.tokens = build_token_service(
            private_key_pem=_secret(settings.JWT_PRIVATE_KEY_PEM),
            public_keys_json=_secret(settings.JWT_PUBLIC_KEYS_JSON),
            kid=settings.JWT_ACTIVE_KID,
            issuer=settings.JWT_ISSUER,
            audience=settings.JWT_AUDIENCE,
            access_ttl_s=settings.ACCESS_TOKEN_TTL_SECONDS,
            link_ttl_s=settings.LINK_TOKEN_TTL_SECONDS,
        )
    if getattr(state, "http", None) is None:
        state.http = httpx2.AsyncClient(follow_redirects=False)
    if getattr(state, "oauth", None) is None:
        fetch = http_fetcher(state.http)
        state.oauth = OAuthVerifier(
            google_keys=JwksCache(settings.GOOGLE_JWKS_URL, fetch),
            apple_keys=JwksCache(settings.APPLE_JWKS_URL, fetch),
            google_client_ids=settings.GOOGLE_OAUTH_CLIENT_IDS,
            apple_audiences=[settings.APPLE_BUNDLE_ID, settings.APPLE_SERVICE_ID],
        )
    if getattr(state, "email", None) is None:
        state.email = _email_sender(settings)
    if getattr(state, "revocations", None) is None:
        state.revocations = Revocations(state.store, settings.ACCESS_TOKEN_TTL_SECONDS)
    if getattr(state, "reference", None) is None:
        state.reference = ReferenceCache(state.db)
    if getattr(state, "entitlements", None) is None:
        state.entitlements = EntitlementService(state.db)
    if getattr(state, "auth_service", None) is None:
        state.auth_service = AuthService(
            settings=settings,
            db=state.db,
            tokens=state.tokens,
            password_hasher=getattr(state, "password_hasher", None)
            or password_hasher(
                memory_kib=settings.ARGON2_MEMORY_KIB,
                time_cost=settings.ARGON2_TIME_COST,
                parallelism=settings.ARGON2_PARALLELISM,
            ),
            oauth=state.oauth,
            apple=_apple_client(settings, state.http),
            email=state.email,
            rate_limiter=state.rate_limiter,
            revocations=state.revocations,
            store=state.store,
        )
    if getattr(state, "profile_service", None) is None:
        state.profile_service = ProfileService(db=state.db, reference=state.reference)


def _init_tracking(app: FastAPI) -> None:
    """Nutrition (S08), hydration and notifications (S09), sleep (S10)."""
    settings: Settings = app.state.settings
    state = app.state
    if getattr(state, "nutrition_service", None) is None:
        state.nutrition_service = NutritionService(
            db=state.db,
            reference=state.reference,
            entitlements=state.entitlements,
            open_food_facts=getattr(state, "open_food_facts", None)
            or OpenFoodFacts(
                state.http, settings.OPEN_FOOD_FACTS_BASE_URL, settings.OPEN_FOOD_FACTS_USER_AGENT
            ),
        )
    if getattr(state, "hydration_service", None) is None:
        state.hydration_service = HydrationService(
            db=state.db,
            reference=state.reference,
            entitlements=state.entitlements,
            estimator=getattr(state, "drink_estimator", None) or _drink_estimator(settings),
        )
    if getattr(state, "sleep_service", None) is None:
        state.sleep_service = SleepService(db=state.db, entitlements=state.entitlements)
    if getattr(state, "notification_service", None) is None:
        state.notification_service = NotificationService(db=state.db)


def _apple_verifier(settings: Settings) -> AppleJwsVerifier | None:
    try:
        roots = load_roots(settings.APPLE_ROOT_CA_PATHS)
    except OSError:
        log.warning("apple_verification_disabled", reason="no Apple root certificate (dev)")
        return None
    return AppleJwsVerifier(
        roots,
        bundle_id=settings.APPLE_BUNDLE_ID,
        environment=settings.APP_STORE_ENVIRONMENT,
    )


def _init_billing(app: FastAPI) -> None:
    """Store billing and referrals (S11). Without real store keys (dev) the store clients are
    disabled: purchases answer 422 PURCHASE_INVALID and webhooks 401; outside dev Settings refuse
    to start without them."""
    settings: Settings = app.state.settings
    state = app.state
    if getattr(state, "billing_service", None) is None:
        account = ServiceAccount.parse(settings.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON.get_secret_value())
        play = getattr(state, "play_client", None) or (
            GooglePlayClient(
                state.http,
                account,
                package_name=settings.GOOGLE_PLAY_PACKAGE_NAME,
                api_base_url=settings.GOOGLE_PLAY_API_BASE_URL,
                token_url=settings.GOOGLE_OAUTH_TOKEN_URL,
            )
            if account is not None
            else None
        )
        state.billing_service = BillingService(
            db=state.db,
            entitlements=state.entitlements,
            play=play,
            apple=getattr(state, "apple_verifier", None) or _apple_verifier(settings),
            pubsub=getattr(state, "pubsub_verifier", None)
            or PubSubVerifier(
                JwksCache(settings.GOOGLE_JWKS_URL, http_fetcher(state.http)),
                audience=settings.GOOGLE_RTDN_PUSH_AUDIENCE,
                service_account_email=settings.GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL,
            ),
            package_name=settings.GOOGLE_PLAY_PACKAGE_NAME,
            manage_urls={
                "android": settings.PLAY_MANAGE_SUBSCRIPTIONS_URL,
                "ios": settings.APP_STORE_MANAGE_SUBSCRIPTIONS_URL,
            },
        )
    if getattr(state, "referral_service", None) is None:
        state.referral_service = ReferralService(
            db=state.db, link_domain=settings.REFERRAL_LINK_DOMAIN
        )


def _init_social(app: FastAPI) -> None:
    """Connections, circles and chat (S12). Realtime tickets and sockets live in this process."""
    settings: Settings = app.state.settings
    state = app.state
    if getattr(state, "social_service", None) is None:
        state.social_service = SocialService(
            db=state.db,
            hub=Hub(),
            tickets=TicketStore(),
            link_domain=settings.REFERRAL_LINK_DOMAIN,
        )
    # A revoked session loses its open sockets at once, not when the client next disconnects.
    state.revocations.listeners.append(state.social_service.hub.end_sessions)


def _rin_model(settings: Settings, *, fallback: bool = False) -> RinModel | None:
    """OpenAI for Rin when enabled with a real key (the .env.example placeholder starts with
    "dummy"); without one Rin answers in the free basic mode. ``fallback``: the lower model
    (RIN_FALLBACK_MODEL) used when our account rate-limits or the main model fails."""
    key = _secret(settings.OPENAI_API_KEY)
    name = settings.RIN_FALLBACK_MODEL if fallback else settings.RIN_MODEL
    if not settings.RIN_ENABLED or not key or key.startswith("dummy") or not name:
        if not fallback:
            log.warning("rin_basic_only", reason="RIN_ENABLED is false or no OpenAI key")
        return None
    return OpenAIRinModel(
        api_key=key,
        model=name,
        effort=settings.RIN_EFFORT,
        max_tokens=settings.RIN_MAX_OUTPUT_TOKENS,
    )


def _init_rin(app: FastAPI) -> None:
    """Rin AI (S13): STAR chat on OpenAI with the monthly AI cap per user (also metering the
    drink estimates)."""
    settings: Settings = app.state.settings
    state = app.state
    if getattr(state, "rin_service", None) is None:
        state.rin_service = RinService(
            db=state.db,
            model=getattr(state, "rin_model", None) or _rin_model(settings),
            nutrition=state.nutrition_service,
            hydration=state.hydration_service,
            budget_micro_inr=inr_to_micro(settings.RIN_MONTHLY_BUDGET_INR),
            prices=AiPrices.from_settings(settings),
            enabled=settings.RIN_ENABLED,
            fallback_model=getattr(state, "rin_fallback_model", None)
            or _rin_model(settings, fallback=True),
            fallback_prices=AiPrices.fallback_from_settings(settings),
        )
    state.hydration_service.ai_meter = state.rin_service


def _init_profile_tab(app: FastAPI) -> None:
    """Streak, reports, Help & Support and sync (S14)."""
    settings: Settings = app.state.settings
    state = app.state
    if getattr(state, "storage", None) is None:
        state.storage = build_storage(settings)
    if getattr(state, "report_service", None) is None:
        state.report_service = ReportService(
            db=state.db, storage=state.storage, download_prefix=API_PREFIX
        )
    if getattr(state, "support_service", None) is None:
        state.support_service = SupportService(
            db=state.db,
            storage=state.storage,
            entitlements=state.entitlements,
            contact=SupportContact(
                email=settings.SUPPORT_CONTACT_EMAIL or settings.SUPPORT_INBOX_ADDRESS,
                phone=settings.SUPPORT_PHONE,
                phone_hours=settings.SUPPORT_PHONE_HOURS,
                email_response=settings.SUPPORT_EMAIL_RESPONSE,
            ),
        )
    if getattr(state, "sync_service", None) is None:
        state.sync_service = SyncService(db=state.db)
    if getattr(state, "privacy_service", None) is None:
        state.privacy_service = PrivacyService(
            db=state.db, auth=state.auth_service, storage=state.storage, download_prefix=API_PREFIX
        )


async def _init_state(app: FastAPI) -> None:
    """Create shared resources unless a test already put them on app.state."""
    settings: Settings = app.state.settings
    state = app.state
    if getattr(state, "db", None) is None:
        state.db = Database(*create_engines(settings))
    if getattr(state, "store", None) is None:
        # Rate limits, logout deny-list, lockout-notice dedupe: in memory (no Redis in the API).
        state.store = MemoryStore()
    if getattr(state, "rate_limiter", None) is None:
        state.rate_limiter = RateLimiter(state.store)
    if getattr(state, "security_events", None) is None:
        state.security_events = SecurityEventWriter(state.db)
    state.security_events.start()
    _init_auth(app)
    _init_tracking(app)
    _init_billing(app)
    _init_social(app)
    _init_rin(app)
    _init_profile_tab(app)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    await _init_state(app)
    try:
        yield
    finally:
        await app.state.social_service.hub.close_all()
        await app.state.security_events.stop()
        await app.state.http.aclose()
        await app.state.db.dispose()
        await app.state.store.aclose()


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or load_settings()
    configure_logging(settings.LOG_LEVEL)

    docs_enabled = settings.API_DOCS_ENABLED
    app = FastAPI(
        title="NaraaCare API",
        version=settings.APP_VERSION,
        docs_url=f"{API_PREFIX}/docs" if docs_enabled else None,
        redoc_url=None,
        openapi_url=f"{API_PREFIX}/docs/openapi.json" if docs_enabled else None,
        lifespan=lifespan,
    )
    app.state.settings = settings
    install_exception_handlers(app, on_unsafe_input=on_unsafe_input)

    # add_middleware wraps: the LAST one added is the OUTERMOST. Listed here inner -> outer.
    app.add_middleware(RateLimitMiddleware)
    if settings.CORS_ALLOWED_ORIGINS:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.CORS_ALLOWED_ORIGINS,
            allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
            allow_headers=["Authorization", "Content-Type", "X-Request-ID", "Idempotency-Key"],
        )
    app.add_middleware(
        BodySizeLimitMiddleware,
        max_bytes=settings.MAX_BODY_BYTES,
        overrides=dict.fromkeys(UPLOAD_ROUTES, settings.MAX_UPLOAD_BYTES),
    )
    if docs_enabled and settings.API_DOCS_BASIC_AUTH is not None:
        app.add_middleware(
            DocsBasicAuthMiddleware,
            prefixes=DOCS_PREFIXES,
            credential=settings.API_DOCS_BASIC_AUTH.get_secret_value(),
        )
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=settings.ALLOWED_HOSTS)
    app.add_middleware(ErrorShieldMiddleware)
    app.add_middleware(SecurityHeadersMiddleware)
    app.add_middleware(AccessLogMiddleware)
    app.add_middleware(RequestIdMiddleware)

    for router in (
        health.router,
        auth.router,
        me.router,
        reference.router,
        privacy.router,
        foods.router,
        meals.router,
        nutrition.router,
        admin_foods.router,
        hydration.router,
        notifications.router,
        sleep.router,
        billing.router,
        people.router,
        circles.router,
        chat.router,
        rin.router,
        reports.router,
    ):
        app.include_router(router, prefix=API_PREFIX)
    return app
