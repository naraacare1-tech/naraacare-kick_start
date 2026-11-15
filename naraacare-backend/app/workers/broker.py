"""taskiq broker + scheduler (doc 11 §7).

Worker:    taskiq worker app.workers.broker:broker --max-async-tasks $WORKER_CONCURRENCY
Scheduler: taskiq scheduler app.workers.broker:scheduler
Jobs: reminders and pushes (S09/S12), billing (S11), reports and support forwarding (S14),
exports, account erasure and retention (S15).
"""

from __future__ import annotations

from pathlib import Path

import httpx2
import redis.asyncio as redis_asyncio
from taskiq import TaskiqScheduler
from taskiq.schedule_sources import LabelScheduleSource
from taskiq_redis import RedisStreamBroker

from app.core.config import SettingsLoadError, load_settings
from app.core.logging import configure_logging
from app.core.security.oauth import AppleTokenClient, load_apple_private_key
from app.db.engine import create_engines
from app.domain.ai.pricing import AiPrices, inr_to_micro
from app.domain.reference import ReferenceCache
from app.domain.reports.insights import InsightModel, OpenAIInsightModel
from app.integrations.app_store import AppleJwsVerifier, AppStoreApiClient, load_roots
from app.integrations.email import OutboxSender, SmtpSender
from app.integrations.fcm import FcmClient
from app.integrations.google_oauth import ServiceAccount
from app.integrations.google_play import GooglePlayClient
from app.integrations.storage import ObjectStorage, build_storage
from app.repositories.base import Database
from app.workers.jobs import billing as billing_jobs
from app.workers.jobs import privacy as privacy_jobs
from app.workers.jobs import reminders
from app.workers.jobs import reports as report_jobs
from app.workers.jobs import social as social_jobs
from app.workers.jobs import support as support_jobs

_settings = load_settings()
configure_logging(_settings.LOG_LEVEL)

# Redis Streams give at-least-once delivery with acknowledgements, so jobs must be idempotent.
# Only the worker needs Redis (the API runs without it).
if _settings.REDIS_URL is None:
    raise SettingsLoadError("REDIS_URL is required to run the background worker")
_REDIS_URL = _settings.REDIS_URL.get_secret_value()
broker = RedisStreamBroker(url=_REDIS_URL, queue_name="naraacare")
scheduler = TaskiqScheduler(broker=broker, sources=[LabelScheduleSource(broker)])


@broker.task(task_name="ops.heartbeat", schedule=[{"cron": "*/5 * * * *"}])
async def heartbeat() -> str:
    """Trivial scheduled job proving the queue and scheduler round-trip works."""
    return "ok"


# --- Session 09: reminder pushes. The worker's DATABASE_URL uses the app_worker login, the only
# role granted the ops reminder functions. Resources are built once per worker process.
class _Push:
    db: Database
    redis: redis_asyncio.Redis
    sender: FcmClient | None


_push: _Push | None = None


def _push_resources() -> _Push:
    global _push  # noqa: PLW0603 - one set of clients per worker process
    if _push is None:
        push = _Push()
        account = ServiceAccount.parse(_settings.FCM_SERVICE_ACCOUNT_JSON.get_secret_value())
        push.db = Database(*create_engines(_settings))
        push.redis = redis_asyncio.from_url(_REDIS_URL)
        # Dev without a service-account key: push is disabled (refused outside dev by Settings).
        push.sender = (
            FcmClient(
                httpx2.AsyncClient(follow_redirects=False),
                account,
                api_base_url=_settings.FCM_API_BASE_URL,
                token_url=_settings.GOOGLE_OAUTH_TOKEN_URL,
            )
            if account is not None
            else None
        )
        _push = push
    return _push


@broker.task(task_name="notify.send_reminders", schedule=[{"cron": "* * * * *"}])
async def send_reminders_job() -> str:
    push = _push_resources()
    if push.sender is None:
        return "push disabled"
    stats = await reminders.send_reminders(db=push.db, sender=push.sender, dedup=push.redis)
    return f"sent {stats.sent}"


@broker.task(task_name="notify.day_ending_soon", schedule=[{"cron": "*/15 * * * *"}])
async def day_ending_soon_job() -> str:
    push = _push_resources()
    if push.sender is None:
        return "push disabled"
    ctx = await ReferenceCache(push.db).calc_context()
    stats = await reminders.day_ending_soon(
        db=push.db,
        sender=push.sender,
        dedup=push.redis,
        hours=ctx.const("hyd.state.day_ending_soon_hours"),  # doc 06 section 3.8
    )
    return f"sent {stats.sent}"


# --- Session 12: social pushes (worker role: ops.fn_social_pushes).
@broker.task(task_name="notify.send_social_pushes", schedule=[{"cron": "* * * * *"}])
async def send_social_pushes_job() -> str:
    push = _push_resources()
    if push.sender is None:
        return "push disabled"
    stats = await social_jobs.send_social_pushes(db=push.db, sender=push.sender, store=push.redis)
    return f"sent {stats.sent}"


# --- Session 11: billing jobs (worker role: ops.pr_tally_referrals,
# ops.fn_subscriptions_to_reconcile).
@broker.task(task_name="billing.tally_referrals", schedule=[{"cron": "30 21 * * *"}])
async def tally_referrals_job() -> str:
    """Nightly at 03:00 IST (21:30 UTC)."""
    qualified, rewarded = await billing_jobs.tally_referrals(_push_resources().db)
    return f"qualified {qualified}, rewarded {rewarded}"


@broker.task(task_name="billing.reconcile_subscriptions", schedule=[{"cron": "15 */6 * * *"}])
async def reconcile_subscriptions_job() -> str:
    push = _push_resources()
    account = ServiceAccount.parse(_settings.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON.get_secret_value())
    http = httpx2.AsyncClient(follow_redirects=False)
    try:
        play = (
            GooglePlayClient(
                http,
                account,
                package_name=_settings.GOOGLE_PLAY_PACKAGE_NAME,
                api_base_url=_settings.GOOGLE_PLAY_API_BASE_URL,
                token_url=_settings.GOOGLE_OAUTH_TOKEN_URL,
            )
            if account is not None
            else None
        )
        try:
            apple: AppleJwsVerifier | None = AppleJwsVerifier(
                load_roots(_settings.APPLE_ROOT_CA_PATHS),
                bundle_id=_settings.APPLE_BUNDLE_ID,
                environment=_settings.APP_STORE_ENVIRONMENT,
            )
        except OSError:
            apple = None
        app_store = AppStoreApiClient(
            http,
            base_url=_settings.APP_STORE_API_BASE_URL
            if _settings.APP_STORE_ENVIRONMENT == "Production"
            else _settings.APP_STORE_SANDBOX_API_BASE_URL,
            issuer_id=_settings.APP_STORE_ISSUER_ID,
            key_id=_settings.APP_STORE_KEY_ID,
            private_key_p8=_settings.APP_STORE_PRIVATE_KEY_P8.get_secret_value(),
            bundle_id=_settings.APPLE_BUNDLE_ID,
        )
        stats = await billing_jobs.reconcile_subscriptions(
            db=push.db,
            play=play,
            app_store=app_store if apple is not None else None,
            apple=apple,
        )
    finally:
        await http.aclose()
    return f"updated {stats.updated} of {stats.checked}"


# --- Session 14: PDF reports and support forwarding (worker role: ops report/support functions).
class _ProfileJobs:
    storage: ObjectStorage
    insight_model: InsightModel | None
    email: OutboxSender | SmtpSender  # plain (support) and template (deletion) emails


_profile_jobs: _ProfileJobs | None = None


def _profile_resources() -> _ProfileJobs:
    global _profile_jobs  # noqa: PLW0603 - one set of clients per worker process
    if _profile_jobs is None:
        jobs = _ProfileJobs()
        jobs.storage = build_storage(_settings)
        key = (
            _settings.OPENAI_API_KEY.get_secret_value()
            if _settings.OPENAI_API_KEY is not None
            else ""
        )
        # Same switch as Rin: no real key (the .env.example placeholder starts with "dummy") ->
        # reports are built without insights instead of failing.
        jobs.insight_model = (
            OpenAIInsightModel(api_key=key, model=_settings.RIN_MODEL)
            if _settings.RIN_ENABLED and key and not key.startswith("dummy")
            else None
        )
        jobs.email = (
            OutboxSender(
                sender=_settings.EMAIL_FROM_ADDRESS, directory=Path(_settings.EMAIL_OUTBOX_DIR)
            )
            if _settings.EMAIL_BACKEND == "outbox"
            else SmtpSender(
                sender=_settings.EMAIL_FROM_ADDRESS,
                host=_settings.SMTP_HOST or "",
                port=_settings.SMTP_PORT,
                username=_settings.SMTP_USERNAME,
                password=_settings.SMTP_PASSWORD.get_secret_value()
                if _settings.SMTP_PASSWORD is not None
                else None,
            )
        )
        _profile_jobs = jobs
    return _profile_jobs


@broker.task(task_name="reports.generate", schedule=[{"cron": "* * * * *"}])
async def generate_reports_job() -> str:
    jobs = _profile_resources()
    stats = await report_jobs.generate_reports(
        db=_push_resources().db,
        storage=jobs.storage,
        insight_model=jobs.insight_model,
        budget_micro_inr=inr_to_micro(_settings.RIN_MONTHLY_BUDGET_INR),
        prices=AiPrices.from_settings(_settings),
    )
    return f"built {stats.built}, failed {stats.failed}"


@broker.task(task_name="reports.expire", schedule=[{"cron": "7 * * * *"}])
async def expire_reports_job() -> str:
    count = await report_jobs.expire_reports(
        db=_push_resources().db, storage=_profile_resources().storage
    )
    return f"expired {count}"


@broker.task(task_name="support.forward", schedule=[{"cron": "*/5 * * * *"}])
async def forward_support_job() -> str:
    sent = await support_jobs.forward_support(
        db=_push_resources().db,
        sender=_profile_resources().email,
        inbox=_settings.SUPPORT_INBOX_ADDRESS,
    )
    return f"forwarded {sent}"


# --- Session 15: exports, account erasure and retention (worker role: ops privacy functions).
class _AppleRevoker:
    """Sign in with Apple token revocation with the configured revoke URL."""

    def __init__(self, client: AppleTokenClient, revoke_url: str) -> None:
        self._client = client
        self._url = revoke_url

    async def revoke(self, refresh_token: str) -> bool:
        return await self._client.revoke(refresh_token, self._url)


def _apple_revoker(http: httpx2.AsyncClient) -> _AppleRevoker | None:
    key = load_apple_private_key(_settings.APPLE_SIWA_PRIVATE_KEY_P8.get_secret_value())
    if key is None or not _settings.APPLE_REVOKE_URL:
        return None  # dev without a Sign in with Apple key: nothing to revoke
    client = AppleTokenClient(
        http=http,
        token_url=_settings.APPLE_TOKEN_URL,
        team_id=_settings.APPLE_TEAM_ID,
        client_id=_settings.APPLE_BUNDLE_ID,
        key_id=_settings.APPLE_SIWA_KEY_ID,
        private_key=key,
    )
    return _AppleRevoker(client, _settings.APPLE_REVOKE_URL)


@broker.task(task_name="privacy.generate_exports", schedule=[{"cron": "* * * * *"}])
async def generate_exports_job() -> str:
    stats = await privacy_jobs.generate_exports(
        db=_push_resources().db, storage=_profile_resources().storage
    )
    return f"built {stats.done}, failed {stats.failed}"


@broker.task(task_name="privacy.expire_exports", schedule=[{"cron": "17 * * * *"}])
async def expire_exports_job() -> str:
    count = await privacy_jobs.expire_exports(
        db=_push_resources().db, storage=_profile_resources().storage
    )
    return f"expired {count}"


@broker.task(task_name="privacy.process_deletions", schedule=[{"cron": "27 * * * *"}])
async def process_deletions_job() -> str:
    http = httpx2.AsyncClient(follow_redirects=False)
    try:
        stats = await privacy_jobs.process_deletions(
            db=_push_resources().db,
            storage=_profile_resources().storage,
            email=_profile_resources().email,
            apple=_apple_revoker(http),
        )
    finally:
        await http.aclose()
    return f"erased {stats.done}, failed {stats.failed}"


@broker.task(task_name="privacy.apply_retention", schedule=[{"cron": "45 20 * * *"}])
async def apply_retention_job() -> str:
    """Daily at 02:15 IST (20:45 UTC)."""
    counts = await privacy_jobs.apply_retention(
        db=_push_resources().db, storage=_profile_resources().storage
    )
    return f"purged {sum(counts.values())}"
