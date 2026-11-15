-- V026 (hand-written, 2026-11-07): Rin AI moves from Claude to OpenAI GPT-5 mini with a monthly
-- spend cap per user (owner: Rs 10 a month, Rin pauses until the next local month when it is used
-- up). Prices change, so the API works out each call's cost from its configured prices and stores
-- it here in micro-rupees (1 rupee = 1,000,000); the cap is the month's sum. Tokens stay recorded.
ALTER TABLE ai.usage_event
    ADD COLUMN cost_micro_inr bigint NOT NULL DEFAULT 0 CHECK (cost_micro_inr >= 0);
COMMENT ON COLUMN ai.usage_event.cost_micro_inr IS
'Cost of the call in micro-rupees, from the API''s configured model prices at call time';

-- The routines below get a cost parameter / a monthly total; the repeatable scripts recreate them
-- (a changed argument list or result type cannot be replaced in place).
DROP PROCEDURE ai.pr_record_usage(uuid, text, text, integer, integer, integer, integer);
DROP PROCEDURE ops.pr_record_insight_usage(uuid, text, integer, integer, integer, integer);
DROP FUNCTION ai.fn_usage_today(uuid);
DROP FUNCTION ops.fn_claim_report_jobs(integer);

COMMENT ON INDEX ai.ix_usage_event__user_day IS 'serves: fn_usage_month (monthly cap), fn_claim_report_jobs; FK cascade';
