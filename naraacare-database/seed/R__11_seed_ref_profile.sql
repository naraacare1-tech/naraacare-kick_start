-- Profile reference data (doc 06 sections 2-4). Idempotent upserts keyed by code; codes are never deleted.

INSERT INTO ref.subscription_tier (code, label, display_order) VALUES
('standard', 'STANDARD', 1),
('star', 'STAR', 2)
ON CONFLICT (code) DO UPDATE SET label = excluded.label, display_order = excluded.display_order, updated_at = now();

INSERT INTO ref.hydration_activity (code, label, activity_number, athlete_bonus_ml) VALUES
('sedentary', 'Sedentary (mostly sitting)', 1.55, 0),
('light', 'Lightly active (on your feet, moving)', 1.70, 0),
('active', 'Moderately active (on your feet all day)', 1.85, 0),
('athlete', 'Very active (training hard)', 2.00, 699.7)
ON CONFLICT (code) DO UPDATE SET
    label = excluded.label, activity_number = excluded.activity_number,
    athlete_bonus_ml = excluded.athlete_bonus_ml, updated_at = now();

-- Mapping onboarding answer -> TDEE multiplier + hydration activity (owner 2026-11-24: the 2026-11 MVP
-- document, nutrition step 2 and hydration step 3; replaces the OQ-12 / OQ-13 values 0.75 / 1.00 /
-- 1.02 / 1.07). Nutritionist sign-off still needed before launch (OQ-12).
INSERT INTO ref.activity_level (code, label, onboarding_label, tdee_multiplier, hydration_activity_code, display_order) VALUES
('sedentary', 'Sedentary', 'Little or no exercise', 1.200, 'sedentary', 1),
('lightly_active', 'Lightly active', 'Walks or light workouts 1-3 days', 1.375, 'light', 2),
('moderately_active', 'Moderately active', 'Exercise 3-5 days/week', 1.550, 'active', 3),
('very_active', 'Very active', 'Exercise most days / physical job', 1.725, 'athlete', 4)
ON CONFLICT (code) DO UPDATE SET
    label = excluded.label, onboarding_label = excluded.onboarding_label,
    tdee_multiplier = excluded.tdee_multiplier, hydration_activity_code = excluded.hydration_activity_code,
    display_order = excluded.display_order, updated_at = now();

INSERT INTO ref.body_type (code, label, lbw_factor, display_order) VALUES
('ectomorph', 'Ectomorph (lean, slim)', 0.97, 1),
('mesomorph', 'Mesomorph (athletic)', 1.00, 2),
('endomorph', 'Endomorph (fuller build)', 1.03, 3)
ON CONFLICT (code) DO UPDATE SET
    label = excluded.label, lbw_factor = excluded.lbw_factor, display_order = excluded.display_order, updated_at = now();

-- Owner 2026-11-07: only five goals are offered; the other three stay for existing profiles (V027).
INSERT INTO ref.weight_goal (code, label, kcal_delta, kg_per_week, direction, display_order, offered) VALUES
('aggressive_loss', 'Aggressive Loss', -1000, 1.00, 'loss', 1, FALSE),
('moderate_loss', 'Moderate Loss', -750, 0.75, 'loss', 2, FALSE),
('standard_loss', 'Standard Loss', -500, 0.50, 'loss', 3, TRUE),
('mild_loss', 'Mild Loss', -250, 0.25, 'loss', 4, TRUE),
('maintain', 'Maintain', 0, 0.00, 'maintain', 5, TRUE),
('mild_gain', 'Mild Gain', 250, 0.25, 'gain', 6, TRUE),
('standard_gain', 'Standard Gain', 500, 0.50, 'gain', 7, TRUE),
('aggressive_gain', 'Aggressive Gain', 750, 0.75, 'gain', 8, FALSE)
ON CONFLICT (code) DO UPDATE SET
    label = excluded.label, kcal_delta = excluded.kcal_delta, kg_per_week = excluded.kg_per_week,
    direction = excluded.direction, display_order = excluded.display_order, offered = excluded.offered,
    updated_at = now();

INSERT INTO ref.bmi_category (code, label, min_bmi, max_bmi_exclusive, blocked_goal_codes) VALUES
('underweight', 'Underweight', 0, 18.5, '{aggressive_loss,moderate_loss,standard_loss,mild_loss}'),
('normal', 'Normal weight', 18.5, 25.0, '{aggressive_loss}'),
('overweight_obese', 'Overweight / Obese', 25.0, NULL, '{}')
ON CONFLICT (code) DO UPDATE SET
    label = excluded.label, min_bmi = excluded.min_bmi, max_bmi_exclusive = excluded.max_bmi_exclusive,
    blocked_goal_codes = excluded.blocked_goal_codes, updated_at = now();

INSERT INTO ref.sleep_goal_by_age (min_age, max_age, goal_min) VALUES
(18, 64, 480),
(65, 100, 450)
ON CONFLICT (min_age) DO UPDATE SET max_age = excluded.max_age, goal_min = excluded.goal_min, updated_at = now();

INSERT INTO ref.avatar (code, sex, body_type_code, asset_key) VALUES
('female_ectomorph', 'female', 'ectomorph', 'avatars/female_ectomorph'),
('female_mesomorph', 'female', 'mesomorph', 'avatars/female_mesomorph'),
('female_endomorph', 'female', 'endomorph', 'avatars/female_endomorph'),
('male_ectomorph', 'male', 'ectomorph', 'avatars/male_ectomorph'),
('male_mesomorph', 'male', 'mesomorph', 'avatars/male_mesomorph'),
('male_endomorph', 'male', 'endomorph', 'avatars/male_endomorph')
ON CONFLICT (code) DO UPDATE SET
    sex = excluded.sex, body_type_code = excluded.body_type_code, asset_key = excluded.asset_key, updated_at = now();

-- PLACEHOLDER list until product supplies the final one (OQ-33). Not used in calculations.
INSERT INTO ref.medical_condition (code, label, kind, display_order) VALUES
('none', 'None', 'none', 0),
('diabetes', 'Diabetes', 'condition', 10),
('hypertension', 'High blood pressure', 'condition', 11),
('hypothyroidism', 'Hypothyroidism', 'condition', 12),
('pcos', 'PCOS', 'condition', 13),
('kidney_disease', 'Kidney disease', 'condition', 14),
('heart_disease', 'Heart disease', 'condition', 15),
('pregnancy', 'Pregnancy', 'condition', 16),
('allergy_peanut', 'Peanuts', 'allergy', 30),
('allergy_tree_nut', 'Tree nuts', 'allergy', 31),
('allergy_dairy', 'Milk / lactose', 'allergy', 32),
('allergy_gluten', 'Gluten', 'allergy', 33),
('allergy_egg', 'Egg', 'allergy', 34),
('allergy_shellfish', 'Shellfish', 'allergy', 35),
('allergy_soy', 'Soy', 'allergy', 36),
('allergy_berries', 'Berries', 'allergy', 37)
ON CONFLICT (code) DO UPDATE SET
    label = excluded.label, kind = excluded.kind, display_order = excluded.display_order, updated_at = now();
