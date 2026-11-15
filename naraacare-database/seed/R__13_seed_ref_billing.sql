-- Tier matrix, store products, policies, flags, wallpapers (doc 04 section 3, OQ-06, OQ-47).

INSERT INTO ref.feature_entitlement (tier_code, feature_code, enabled, limit_value) VALUES
('standard', 'nutrients_visible', TRUE, 6),
('star', 'nutrients_visible', TRUE, 17),
('standard', 'meal_logs_per_day', TRUE, 4),
('star', 'meal_logs_per_day', TRUE, 8),
('standard', 'voice_logging', FALSE, NULL),
('star', 'voice_logging', TRUE, NULL),
('standard', 'barcode_logging', FALSE, NULL),
('star', 'barcode_logging', TRUE, NULL),
('standard', 'meal_breakdown', FALSE, NULL),
('star', 'meal_breakdown', TRUE, NULL),
('standard', 'advanced_hydration', FALSE, NULL),
('star', 'advanced_hydration', TRUE, NULL),
('standard', 'premium_drinks', FALSE, NULL),
('star', 'premium_drinks', TRUE, NULL),
('standard', 'custom_drinks', FALSE, NULL),
('star', 'custom_drinks', TRUE, NULL),
('standard', 'sleep', FALSE, NULL),
('star', 'sleep', TRUE, NULL),
('standard', 'rin_ai', FALSE, NULL),
('star', 'rin_ai', TRUE, 100000),
('standard', 'custom_report', FALSE, NULL),
('star', 'custom_report', TRUE, NULL),
('standard', 'report_insights', FALSE, NULL),
('star', 'report_insights', TRUE, NULL)
ON CONFLICT (tier_code, feature_code) DO UPDATE SET
    enabled = excluded.enabled, limit_value = excluded.limit_value, updated_at = now();

-- Display fallback only; real prices come from the stores (OQ-06).
INSERT INTO billing.store_product (platform, product_id, tier_code, period, display_price_inr) VALUES
('google_play', 'star_monthly', 'star', 'p1m', 199.00),
('google_play', 'star_yearly', 'star', 'p1y', 1899.00),
('app_store', 'star_monthly', 'star', 'p1m', 199.00),
('app_store', 'star_yearly', 'star', 'p1y', 1899.00)
ON CONFLICT (platform, product_id) DO UPDATE SET
    tier_code = excluded.tier_code, period = excluded.period,
    display_price_inr = excluded.display_price_inr, updated_at = now();

-- Draft placeholders until legal publishes the documents (OQ-47).
INSERT INTO ref.policy_document (doc_type, version, url) VALUES
('terms', '0.0-draft', 'https://naraacare.app/terms'),
('privacy', '0.0-draft', 'https://naraacare.app/privacy'),
('licenses', '0.0-draft', 'https://naraacare.app/licenses')
ON CONFLICT (doc_type, version) DO NOTHING;

INSERT INTO ref.feature_flag (key, enabled, description) VALUES
('voice_logging', TRUE, 'STAR voice meal logging'),
('barcode_logging', TRUE, 'STAR barcode meal logging'),
('rin_ai', TRUE, 'Rin AI assistant (kill switch)')
ON CONFLICT (key) DO UPDATE SET description = excluded.description, updated_at = now();

-- Placeholder wallpapers until design delivers assets.
INSERT INTO ref.wallpaper (code, label, asset_key) VALUES
('default', 'Default', 'wallpapers/default'),
('sunrise', 'Sunrise', 'wallpapers/sunrise'),
('ocean', 'Ocean', 'wallpapers/ocean'),
('forest', 'Forest', 'wallpapers/forest')
ON CONFLICT (code) DO UPDATE SET label = excluded.label, asset_key = excluded.asset_key, updated_at = now();
