-- Reference data matches doc 06 (constants, tables, tier matrix).
BEGIN;
SELECT no_plan();

SELECT is((SELECT count(*)::int FROM ref.nutrient), 17, '17 nutrients');
SELECT is((
    SELECT count(*)::int FROM ref.nutrient
    WHERE tier_required = 'standard'
), 6, '6 STANDARD nutrients');
SELECT is((SELECT count(*)::int FROM ref.weight_goal), 8, '8 weight goals');
SELECT is((SELECT count(*)::int FROM ref.activity_level), 4, '4 activity levels');
SELECT is((SELECT count(*)::int FROM ref.body_type), 3, '3 body types');
SELECT is((SELECT count(*)::int FROM ref.workout_type), 6, '6 workout types');
SELECT is((SELECT count(*)::int FROM ref.avatar), 6, '6 base avatars');
SELECT is((SELECT count(*)::int FROM ref.food_category), 11, '10 DOC food categories + packaged (barcode products, OQ-44)');

-- TDEE multipliers and hydration mapping (OQ-12 / OQ-13)
SELECT results_eq(
    $$SELECT code::text, tdee_multiplier, hydration_activity_code::text FROM ref.activity_level ORDER BY display_order$$,
    $$VALUES ('sedentary', 0.750, 'sedentary'), ('lightly_active', 1.000, 'sedentary'),
             ('moderately_active', 1.020, 'active'), ('very_active', 1.070, 'active')$$,
    'activity levels: multipliers and hydration mapping'
);
SELECT results_eq(
    $$SELECT activity_number, athlete_bonus_ml FROM ref.hydration_activity ORDER BY activity_number$$,
    $$VALUES (1.55, 0.0), (1.85, 0.0), (2.20, 699.7)$$,
    'hydration activity numbers 1.55 / 1.85 / 2.20 (+699.7)'
);
SELECT results_eq(
    $$SELECT lbw_factor FROM ref.body_type ORDER BY display_order$$,
    $$VALUES (0.970), (1.000), (1.030)$$,
    'body type factors 0.97 / 1.00 / 1.03'
);
SELECT results_eq(
    $$SELECT code::text, kcal_delta FROM ref.weight_goal ORDER BY display_order$$,
    $$VALUES ('aggressive_loss', -1000), ('moderate_loss', -750), ('standard_loss', -500), ('mild_loss', -250),
             ('maintain', 0), ('mild_gain', 250), ('standard_gain', 500), ('aggressive_gain', 750)$$,
    'goal adjustment matrix'
);
SELECT is(
    (
        SELECT blocked_goal_codes::text[] FROM ref.bmi_category
        WHERE code = 'normal'
    ),
    ARRAY['aggressive_loss'],
    'normal BMI blocks only aggressive loss'
);
SELECT is(
    (
        SELECT cardinality(blocked_goal_codes) FROM ref.bmi_category
        WHERE code = 'underweight'
    ),
    4,
    'underweight BMI blocks all four loss goals'
);
SELECT results_eq(
    $$SELECT code::text, hydration_factor, tier_required::text FROM ref.drink_type ORDER BY display_order$$,
    $$VALUES ('water', 1.000, 'standard'), ('tea', 0.997, 'standard'), ('milk', 0.880, 'standard'),
             ('coconut_water', 0.950, 'standard'), ('coffee', 0.994, 'star'), ('juice', 0.885, 'star'),
             ('beer', 0.000, 'star')$$,
    'drink hydration factors and tiers (doc 06 section 3.6, OQ-05)'
);
SELECT results_eq(
    $$SELECT code::text, sweat_ml_per_kg_h FROM ref.workout_type ORDER BY display_order$$,
    $$VALUES ('walking', 5.0), ('gym', 7.5), ('cycling', 10.0), ('swimming', 10.0), ('running', 12.5), ('trekking', 15.0)$$,
    'workout sweat rates'
);

-- Calculation constants (spot checks across doc 06)
SELECT results_eq(
    $$SELECT key::text, value FROM ref.calc_constant WHERE calc_version = '2026.1' AND key IN (
          'nutr.floor.female_kcal', 'nutr.floor.male_kcal', 'hyd.need.drink_food_share', 'hyd.need.min_ml',
          'hyd.need.max_ml', 'hyd.loss.insensible_ml_per_kg_day', 'hyd.tank.body_weight_share',
          'hyd.tank.extra_allowance_ml', 'hyd.food.share_of_need', 'hyd.twt.constant')
      ORDER BY key$$,
    $$VALUES ('hyd.food.share_of_need', 0.20), ('hyd.loss.insensible_ml_per_kg_day', 11),
             ('hyd.need.drink_food_share', 0.85), ('hyd.need.max_ml', 6000), ('hyd.need.min_ml', 1500),
             ('hyd.tank.body_weight_share', 0.02), ('hyd.tank.extra_allowance_ml', 300),
             ('hyd.twt.constant', -665.4), ('nutr.floor.female_kcal', 1200), ('nutr.floor.male_kcal', 1500)$$,
    'key calculation constants (doc 06)'
);
SELECT ok(
    (
        SELECT count(*) FROM ref.calc_constant
        WHERE calc_version = '2026.1'
    ) >= 60,
    'complete constant set for calc_version 2026.1'
);

-- Portions: exactly one default per category; DOC-stated values marked confirmed
SELECT is(
    (
        SELECT count(*)::int FROM ref.food_category AS c
        WHERE (
            SELECT count(*) FROM ref.food_category_unit AS u
            WHERE u.category_code = c.code AND u.is_default
        ) <> 1
    ),
    0,
    'every food category has exactly one default portion'
);
SELECT results_eq(
    $$SELECT quantity, is_confirmed FROM ref.food_category_unit
      WHERE (category_code, unit_code, size) IN (('dal_gravy', 'katori', 'medium'), ('rice_dish', 'plate', 'full'), ('roti', 'piece', 'medium'))
      ORDER BY quantity$$,
    $$VALUES (40.0, true), (150.0, true), (400.0, true)$$,
    'DOC portions: roti 40 g, medium katori 150 ml, full plate 400 g'
);

-- Tier matrix (doc 04 section 3)
SELECT results_eq(
    $$SELECT tier_code::text, limit_value FROM ref.feature_entitlement WHERE feature_code = 'meal_logs_per_day' ORDER BY tier_code$$,
    $$VALUES ('standard', 4), ('star', 8)$$,
    'meal logs per day: 4 STANDARD / 8 STAR'
);
SELECT is(
    (
        SELECT count(*)::int
        FROM ref.feature_entitlement
        WHERE
            tier_code = 'standard' AND enabled
            AND feature_code IN ('sleep', 'rin_ai', 'voice_logging', 'barcode_logging', 'advanced_hydration', 'custom_report')
    ),
    0,
    'STAR-only features are disabled for STANDARD'
);
SELECT is((SELECT count(*)::int FROM billing.store_product), 4, '2 products x 2 stores');
SELECT is((SELECT count(*)::int FROM ops.partition_config), 11, '11 partitioned tables configured');

SELECT * FROM finish();
ROLLBACK;
