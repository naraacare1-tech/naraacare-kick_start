-- Calculation constants, versions 2026.1 and 2026.2 (doc 06). Source of truth for domain calculators.
-- Constants of a released version are IMMUTABLE: this script inserts missing rows and raises if an
-- existing row differs. To change a value, add a new calc_version with the full constant set.

INSERT INTO ref.calc_version (code, effective_from, description, approved_by) VALUES
('2026.1', date '2026-10-01', 'Initial constants from NaraaCare MVP document (pending expert review OQ-12)', NULL),
-- 2026.2 (owner 2026-11-24): the 2026-11 MVP document. The constants below are unchanged; what changed
-- is reference data outside this table (TDEE multipliers 1.2-1.725 and four water activity levels in
-- R__11, net workout kcal (MET - 1) in activity.pr_log_workout, food water tied to logged kcal in the
-- API). Targets computed from this date carry 2026.2; earlier snapshots keep 2026.1.
('2026.2', date '2026-11-24', '2026-11 MVP document: standard TDEE multipliers, 4 water activity levels, net workout kcal, kcal-based food water (pending expert review OQ-12)', NULL)
ON CONFLICT (code) DO NOTHING;

DROP TABLE IF EXISTS pg_temp.seed_calc_constant;
CREATE TEMP TABLE seed_calc_constant (
    key text PRIMARY KEY,
    value numeric NOT NULL,
    unit text NOT NULL,
    source text NOT NULL,
    is_product_choice boolean NOT NULL
);

INSERT INTO seed_calc_constant (key, value, unit, source, is_product_choice) VALUES
-- Nutrition: Mifflin-St Jeor BMR (doc 06 section 2.1)
('nutr.bmr.weight_coeff', 10, 'kcal_per_kg', 'Mifflin-St Jeor 1990', FALSE),
('nutr.bmr.height_coeff', 6.25, 'kcal_per_cm', 'Mifflin-St Jeor 1990', FALSE),
('nutr.bmr.age_coeff', 5, 'kcal_per_year', 'Mifflin-St Jeor 1990', FALSE),
('nutr.bmr.male_offset', 5, 'kcal', 'Mifflin-St Jeor 1990', FALSE),
('nutr.bmr.female_offset', -161, 'kcal', 'Mifflin-St Jeor 1990', FALSE),
-- Goal adjustment, safety floor, macros (doc 06 sections 2.4 to 2.6)
('nutr.kcal_per_kg_fat', 7700, 'kcal', 'NaraaCare MVP doc', FALSE),
('nutr.floor.female_kcal', 1200, 'kcal', 'NaraaCare MVP doc', FALSE),
('nutr.floor.male_kcal', 1500, 'kcal', 'NaraaCare MVP doc', FALSE),
('nutr.macro.carbs_share', 0.55, 'ratio', 'NaraaCare MVP doc', TRUE),
('nutr.macro.fat_share', 0.25, 'ratio', 'NaraaCare MVP doc', TRUE),
('nutr.macro.protein_share', 0.20, 'ratio', 'NaraaCare MVP doc', TRUE),
('nutr.macro.carbs_kcal_per_g', 4, 'kcal_per_g', 'Atwater factors', FALSE),
('nutr.macro.fat_kcal_per_g', 9, 'kcal_per_g', 'Atwater factors', FALSE),
('nutr.macro.protein_kcal_per_g', 4, 'kcal_per_g', 'Atwater factors', FALSE),
-- Energy avatar states (doc 06 section 2.8)
('nutr.avatar.energized_from_pct', 50, 'percent', 'NaraaCare MVP doc', TRUE),
('nutr.avatar.goal_met_from_pct', 100, 'percent', 'NaraaCare MVP doc', TRUE),
('nutr.avatar.goal_met_to_pct', 105, 'percent', 'NaraaCare MVP doc', TRUE),
-- Hydration: lean body weight (Boer 1984, doc 06 section 3.2)
('hyd.lbw.male.weight_coeff', 0.407, 'ratio', 'Boer 1984', FALSE),
('hyd.lbw.male.height_coeff', 0.267, 'kg_per_cm', 'Boer 1984', FALSE),
('hyd.lbw.male.constant', -19.2, 'kg', 'Boer 1984', FALSE),
('hyd.lbw.female.weight_coeff', 0.252, 'ratio', 'Boer 1984', FALSE),
('hyd.lbw.female.height_coeff', 0.473, 'kg_per_cm', 'Boer 1984', FALSE),
('hyd.lbw.female.constant', -48.3, 'kg', 'Boer 1984', FALSE),
-- Daily water movement (Yamada et al. 2022, doc 06 section 3.3)
('hyd.twt.activity_coeff', 861.9, 'ml', 'Yamada et al. Science 2022', FALSE),
('hyd.twt.lbw_coeff', 37.34, 'ml_per_kg', 'Yamada et al. Science 2022', FALSE),
('hyd.twt.age_linear', 29.42, 'ml_per_year', 'Yamada et al. Science 2022', FALSE),
('hyd.twt.age_quadratic', -0.3625, 'ml_per_year2', 'Yamada et al. Science 2022', FALSE),
('hyd.twt.temp_quadratic', 1.937, 'ml_per_c2', 'Yamada et al. Science 2022', FALSE),
('hyd.twt.temp_linear', -23.15, 'ml_per_c', 'Yamada et al. Science 2022', FALSE),
('hyd.twt.constant', -665.4, 'ml', 'Yamada et al. Science 2022 (normal humidity, sea level, India)', FALSE),
-- Daily need and limits (doc 06 section 3.4)
('hyd.need.drink_food_share', 0.85, 'ratio', 'NaraaCare MVP doc', FALSE),
('hyd.need.min_ml', 1500, 'ml', 'NaraaCare MVP doc', TRUE),
('hyd.need.max_ml', 6000, 'ml', 'NaraaCare MVP doc', TRUE),
('hyd.temp.default_c', 25, 'celsius', 'NaraaCare MVP doc', TRUE),
('hyd.temp.min_c', 15, 'celsius', 'NaraaCare MVP doc', TRUE),
('hyd.temp.max_c', 40, 'celsius', 'NaraaCare MVP doc', TRUE),
-- Losses (doc 06 section 3.5)
('hyd.loss.insensible_ml_per_kg_day', 11, 'ml_per_kg_day', 'NaraaCare MVP doc', TRUE),
('hyd.loss.stool_ml_per_day', 150, 'ml', 'NaraaCare MVP doc', TRUE),
('hyd.loss.everyday_sweat_ml', 100, 'ml', 'NaraaCare MVP doc', TRUE),
('hyd.loss.heat_sweat_reference_ml', 632, 'ml', 'NaraaCare MVP doc (temperature effect at 25 C)', TRUE),
('hyd.loss.urine_min_ml', 500, 'ml', 'NaraaCare MVP doc', TRUE),
('hyd.sleep.default_hours', 8, 'hours', 'NaraaCare MVP doc', TRUE),
-- Fills and tank (doc 06 sections 3.6 and 3.7)
('hyd.food.share_of_need', 0.20, 'ratio', 'EFSA 2010', FALSE),
('hyd.food.meals_per_day', 3, 'count', 'NaraaCare MVP doc', TRUE),
('hyd.tank.body_weight_share', 0.02, 'ratio', 'ACSM 2007', FALSE),
('hyd.tank.extra_allowance_ml', 300, 'ml', 'NaraaCare MVP doc', TRUE),
('hyd.custom_drink.default_factor', 0.85, 'ratio', 'NaraaCare MVP doc', TRUE),
('hyd.quick_add_ml', 100, 'ml', 'NaraaCare MVP doc', TRUE),
-- Bands and headline states (doc 06 sections 3.7 and 3.8)
('hyd.band.well_from_pct', 80, 'percent', 'NaraaCare MVP doc', TRUE),
('hyd.band.drink_soon_from_pct', 50, 'percent', 'NaraaCare MVP doc', TRUE),
('hyd.band.low_from_pct', 20, 'percent', 'NaraaCare MVP doc', TRUE),
('hyd.state.goal_completed_max_ratio', 1.10, 'ratio', 'OQ-17 proposal', TRUE),
('hyd.state.overhydration_ratio', 1.5, 'ratio', 'OQ-55 proposal', TRUE),
('hyd.state.day_ending_soon_hours', 3, 'hours', 'NaraaCare MVP doc', TRUE),
-- Sleep (doc 06 section 4)
('sleep.onset_buffer_min', 15, 'minutes', 'NaraaCare MVP doc', TRUE),
('sleep.wake_buffer_min', 15, 'minutes', 'NaraaCare MVP doc', TRUE),
('sleep.waking_fallback_min', 10, 'minutes', 'NaraaCare MVP doc', TRUE),
('sleep.max_entry_hours', 16, 'hours', 'OQ-23 proposal', TRUE),
('sleep.label.good_from_pct', 90, 'percent', 'OQ-23 proposal', TRUE),
('sleep.label.fair_from_pct', 70, 'percent', 'OQ-23 proposal', TRUE),
-- Editing rules (doc 06 section 1)
('edit.last_entries', 2, 'count', 'NaraaCare MVP doc', FALSE),
('edit.window_days', 7, 'days', 'OQ-53 proposal', TRUE);

INSERT INTO ref.calc_constant (calc_version, key, value, unit, source, is_product_choice)
SELECT
    v.code AS calc_version,
    key,
    value,
    unit,
    source,
    is_product_choice
FROM seed_calc_constant
CROSS JOIN (VALUES ('2026.1'), ('2026.2')) AS v (code)
ON CONFLICT (calc_version, key) DO NOTHING;

DO $verify$
DECLARE
    drift text;
BEGIN
    SELECT string_agg(s.key, ', ' ORDER BY s.key) INTO drift
    FROM seed_calc_constant AS s
    JOIN ref.calc_constant AS c ON c.calc_version IN ('2026.1', '2026.2') AND c.key = s.key
    WHERE c.value <> s.value OR c.unit <> s.unit OR c.is_product_choice <> s.is_product_choice;
    IF drift IS NOT NULL THEN
        RAISE EXCEPTION 'calc_versions 2026.1/2026.2 are immutable; changed constants: %. Add a new calc_version.', drift;
    END IF;
END
$verify$;

DROP TABLE pg_temp.seed_calc_constant;
