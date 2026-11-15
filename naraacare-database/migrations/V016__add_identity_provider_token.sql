-- V016__add_identity_provider_token: intentionally empty.
-- auth.identity_link.provider_refresh_token (plain text) is created by V005 since the 2026-11-03
-- plain-text storage change; nothing was deployed before it, so the baseline was regenerated.
SELECT 1;
