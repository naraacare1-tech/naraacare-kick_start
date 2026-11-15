-- V015__drop_food_request: remove "Request New Food" (decision 2026-10-29).
-- Its only Figma frames are hidden on the App Design page and the MVP document never mentions it,
-- so the feature is out of scope (doc 00 OQ-63). The table never held data (no API wrote to it yet).
-- Dropping the table also drops its indexes and its RLS policy.
DROP TABLE nutrition.food_request;
