-- V020__add_subscription_purchase_token: intentionally empty.
-- billing.subscription.purchase_token (plain text, unique per platform) is created by V009 since the
-- 2026-11-03 plain-text storage change; nothing was deployed before it, so the baseline was regenerated.
SELECT 1;
