"""Monthly AI cap maths (owner 2026-11-07: Rs 10 per user per month on GPT-5 mini)."""

from __future__ import annotations

from decimal import Decimal
from types import SimpleNamespace

from app.domain.ai.pricing import AiPrices, inr_to_micro
from app.domain.ai.rin_model import Usage, usage_of

PRICES = AiPrices(
    input_usd_per_mtok=Decimal("0.25"),
    cached_input_usd_per_mtok=Decimal("0.025"),
    output_usd_per_mtok=Decimal("2.00"),
    usd_to_inr=Decimal(88),
)


def test_cost_of_a_typical_turn() -> None:
    # 3,000 fresh input + 400 output: 750 + 800 = 1,550 micro-USD = 136,400 micro-rupees (Rs 0.14).
    assert PRICES.cost_micro_inr(Usage(input_tokens=3000, output_tokens=400)) == 136_400


def test_cached_input_costs_a_tenth() -> None:
    fresh = PRICES.cost_micro_inr(Usage(input_tokens=2000))
    cached = PRICES.cost_micro_inr(Usage(cache_read_tokens=2000))
    assert cached * 10 == fresh


def test_cost_rounds_up() -> None:
    assert PRICES.cost_micro_inr(Usage(input_tokens=1)) == 22  # 0.25 x 88 = 22 exactly
    assert PRICES.cost_micro_inr(Usage(cache_read_tokens=1)) == 3  # 2.2 -> 3, never under-counts


def test_budget_in_micro_rupees() -> None:
    assert inr_to_micro(Decimal(10)) == 10_000_000


def test_openai_usage_splits_cached_tokens() -> None:
    raw = SimpleNamespace(
        prompt_tokens=3000,
        completion_tokens=500,
        prompt_tokens_details=SimpleNamespace(cached_tokens=2048),
    )
    assert usage_of(raw) == Usage(input_tokens=952, output_tokens=500, cache_read_tokens=2048)
    assert usage_of(None) == Usage()
