"""PDF report jobs (Session 14, doc 04 section 2.11). Run by the taskiq scheduler only; the database
functions they call are granted to the worker role alone.

* ``generate_reports`` (every minute): claims queued jobs (SKIP LOCKED, so parallel workers never
  build the same job), loads the daily aggregates, adds AI insights for STAR when still allowed and
  within the daily token allowance, builds the PDF, stores it under a random key and marks the job
  ready (the database writes the "report ready" notification). A failure is retried up to 3 times,
  then the job fails with a notification. Report contents are never logged.
* ``expire_reports`` (hourly): ready jobs older than 7 days become expired and their files are
  deleted.
"""

from __future__ import annotations

import dataclasses
from datetime import UTC, datetime
from functools import partial
from typing import Any

import structlog

from app.domain.ai.pricing import AiPrices
from app.domain.ai.rin_model import Usage
from app.domain.reports.builder import AdvancedInsights, ReportMeta, build_pdf, summarise
from app.domain.reports.insights import InsightModel, generate_insights
from app.integrations.storage import ObjectStorage, new_key
from app.repositories import report_repo
from app.repositories.base import Database

log = structlog.get_logger(__name__)

CLAIM_BATCH = 3
# Skip insights unless the month's AI cap still has room for a typical insight call.
INSIGHT_RESERVE = Usage(input_tokens=1500, output_tokens=1500)


@dataclasses.dataclass(slots=True)
class ReportStats:
    built: int = 0
    failed: int = 0


async def _build_one(
    db: Database,
    storage: ObjectStorage,
    job: dict[str, Any],
    *,
    insight_model: InsightModel | None,
    budget_micro_inr: int,
    prices: AiPrices,
) -> int:
    report_id = job["report_id"]
    sections: list[str] = list(job["sections"])
    days = [dict(r) for r in await db.run(lambda s: report_repo.report_days(s, report_id))]
    extras = await db.run(lambda s: report_repo.report_extras(s, report_id))
    tracker_sections = [s for s in sections if s != "insights"]

    advanced: AdvancedInsights | None = None
    if (
        insight_model is not None
        and "insights" in sections
        and job["insights_allowed"]
        and budget_micro_inr - int(job["ai_spend_month_micro_inr"])
        >= prices.cost_micro_inr(INSIGHT_RESERVE)
    ):
        summary = dataclasses.asdict(summarise(days, tracker_sections, extras))
        result = await generate_insights(insight_model, summary)
        if result is not None:
            advanced = AdvancedInsights(result.trend, result.recommendations)
            usage = result.usage
            await db.run(
                lambda s: report_repo.record_insight_usage(
                    s,
                    report_id,
                    model=result.model,
                    input_tokens=usage.input_tokens,
                    output_tokens=usage.output_tokens,
                    cache_write_tokens=usage.cache_write_tokens,
                    cache_read_tokens=usage.cache_read_tokens,
                    cost_micro_inr=prices.cost_micro_inr(usage),
                )
            )

    meta = ReportMeta(
        full_name=job["full_name"],
        username=job["username"],
        period_from=job["period_from"],
        period_to=job["period_to"],
        sections=tracker_sections,
        generated_on=datetime.now(UTC).date(),
        insights="insights" in sections,
    )
    pdf = build_pdf(meta, days, advanced, extras)
    key = new_key("reports", "pdf")
    await storage.put(key, pdf)
    await db.run(
        lambda s: report_repo.finish_job(
            s, report_id, ok=True, storage_key=key, size_bytes=len(pdf)
        )
    )
    return len(pdf)


async def generate_reports(
    *,
    db: Database,
    storage: ObjectStorage,
    insight_model: InsightModel | None,
    budget_micro_inr: int,
    prices: AiPrices,
) -> ReportStats:
    stats = ReportStats()
    jobs = [dict(j) for j in await db.run(lambda s: report_repo.claim_jobs(s, CLAIM_BATCH))]
    for job in jobs:
        report_id = job["report_id"]
        try:
            size = await _build_one(
                db,
                storage,
                job,
                insight_model=insight_model,
                budget_micro_inr=budget_micro_inr,
                prices=prices,
            )
            stats.built += 1
            log.info("report_built", report_id=str(report_id), size_bytes=size)
        except Exception as exc:  # one bad job never stops the batch
            stats.failed += 1
            log.warning("report_failed", report_id=str(report_id), error=type(exc).__name__)
            await db.run(
                partial(
                    report_repo.finish_job, report_id=report_id, ok=False, error_code="build_failed"
                )
            )
    return stats


async def expire_reports(*, db: Database, storage: ObjectStorage) -> int:
    rows = await db.run(lambda s: report_repo.expire_reports(s, 500))
    for row in rows:
        if row["storage_key"]:
            await storage.delete(str(row["storage_key"]))
    return len(rows)
