"""What an AI call costs, for the monthly cap per user (owner 2026-11-07: Rs 10 a month).

The prices are configuration (Settings ``AI_PRICE_*`` and ``AI_USD_TO_INR``), so a price change is
an .env change, not a release. Costs are kept in integer micro-rupees (1 rupee = 1,000,000) and
rounded up, so the stored spend never under-counts.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import ROUND_CEILING, Decimal
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from app.core.config import Settings
    from app.domain.ai.rin_model import Usage

MICRO = 1_000_000


@dataclass(frozen=True, slots=True)
class AiPrices:
    input_usd_per_mtok: Decimal
    cached_input_usd_per_mtok: Decimal
    output_usd_per_mtok: Decimal
    usd_to_inr: Decimal

    @classmethod
    def from_settings(cls, settings: Settings) -> AiPrices:
        return cls(
            input_usd_per_mtok=settings.AI_PRICE_INPUT_USD_PER_MTOK,
            cached_input_usd_per_mtok=settings.AI_PRICE_CACHED_INPUT_USD_PER_MTOK,
            output_usd_per_mtok=settings.AI_PRICE_OUTPUT_USD_PER_MTOK,
            usd_to_inr=settings.AI_USD_TO_INR,
        )

    @classmethod
    def fallback_from_settings(cls, settings: Settings) -> AiPrices:
        """Prices of RIN_FALLBACK_MODEL (the lower model)."""
        return cls(
            input_usd_per_mtok=settings.AI_FALLBACK_PRICE_INPUT_USD_PER_MTOK,
            cached_input_usd_per_mtok=settings.AI_FALLBACK_PRICE_CACHED_INPUT_USD_PER_MTOK,
            output_usd_per_mtok=settings.AI_FALLBACK_PRICE_OUTPUT_USD_PER_MTOK,
            usd_to_inr=settings.AI_USD_TO_INR,
        )

    def cost_micro_inr(self, usage: Usage) -> int:
        # tokens x (USD per 1M tokens) = micro-USD; x the rate = micro-rupees.
        micro_usd = (
            usage.input_tokens * self.input_usd_per_mtok
            + usage.cache_read_tokens * self.cached_input_usd_per_mtok
            + usage.output_tokens * self.output_usd_per_mtok
        )
        return int((micro_usd * self.usd_to_inr).to_integral_value(rounding=ROUND_CEILING))


def inr_to_micro(amount: Decimal) -> int:
    return int(amount * MICRO)
