-- Food search, portions, nutrient maths, voice matching and the nutritionist food upsert (Session 08).
-- Uses the development sample foods (seed_sample_foods = true in local/CI test databases).
BEGIN;
SELECT no_plan();

\ir payloads/xss_payloads.psql

INSERT INTO auth.user_account (id, email, status, role) VALUES
('0192f000-0000-7000-8000-0000000002a1', 'ua1@example.test', 'active', 'user'),
('0192f000-0000-7000-8000-0000000002a2', 'ua2@example.test', 'active', 'nutritionist');
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000002a1', TRUE);

-- ===== Portions (doc 06 section 2.10) =====
SELECT is(
    (
        SELECT row(unit_code, size, quantity, basis)::text FROM nutrition.fn_food_portions(ARRAY['0192f000-0000-7000-8000-000000000001'::uuid])
        WHERE is_default
    ),
    '(piece,medium,150.0,g)', 'apple: default portion is 1 medium piece = 150 g'
);
SELECT is(
    (
        SELECT count(*)::integer FROM nutrition.fn_food_portions(ARRAY['0192f000-0000-7000-8000-000000000001'::uuid])
        WHERE is_default
    ),
    1, 'exactly one default portion per food'
);
SELECT is(
    (
        SELECT array_agg(row(size, quantity)::text) FROM nutrition.fn_food_portions(ARRAY['0192f000-0000-7000-8000-000000000006'::uuid])
        WHERE unit_code = 'piece'
    ),
    ARRAY['(standard,50.0)'], 'a food override replaces the category''s sizes for that unit'
);
SELECT ok(
    (
        SELECT is_default FROM nutrition.fn_food_portions(ARRAY['0192f000-0000-7000-8000-000000000006'::uuid])
        WHERE unit_code = 'piece'
    ),
    'the override becomes the default when the category default used that unit'
);
SELECT is(
    (
        SELECT label FROM nutrition.fn_food_portions(ARRAY['0192f000-0000-7000-8000-000000000004'::uuid])
        WHERE is_default
    ),
    'Medium Katori', 'portion labels combine size and unit'
);

-- ===== Nutrient maths =====
SELECT is(
    (
        SELECT row(round(calories_kcal), round(carbohydrates_g), round(vitamin_c_mg, 1), consumed_amount, consumed_basis)::text
        FROM nutrition.fn_item_nutrients('[{"food_id": "0192f000-0000-7000-8000-000000000001", "quantity": 1, "unit_code": "piece"}]')
    ),
    '(78,21,6.9,150.0,g)', 'DOC example: a 150 g apple = 78 kcal, 21 g carbs, 6.9 mg vitamin C'
);
SELECT is(
    (
        SELECT array_agg(round(calories_kcal / 105, 2) ORDER BY item_no)
        FROM nutrition.fn_item_nutrients('[
            {"food_id": "0192f000-0000-7000-8000-000000000004", "quantity": 1, "unit_code": "katori", "unit_size": "small"},
            {"food_id": "0192f000-0000-7000-8000-000000000004", "quantity": 1, "unit_code": "katori"},
            {"food_id": "0192f000-0000-7000-8000-000000000004", "quantity": 1, "unit_code": "katori", "unit_size": "large"},
            {"food_id": "0192f000-0000-7000-8000-000000000004", "quantity": 1, "unit_code": "bowl"},
            {"food_id": "0192f000-0000-7000-8000-000000000004", "quantity": 1, "unit_code": "tbsp"}
        ]')
    ),
    ARRAY[1.00, 1.50, 2.00, 3.00, 0.15], 'DOC dal multipliers: small 1.0, medium 1.5, large 2.0, bowl 3.0, tbsp 0.15'
);
SELECT is(
    (SELECT consumed_amount FROM nutrition.fn_item_nutrients('[{"food_id": "0192f000-0000-7000-8000-000000000007", "quantity": 1, "unit_code": "plate", "unit_size": "full"}]')),
    400.0, 'rice full plate = 400 g'
);
SELECT is(
    (SELECT consumed_amount FROM nutrition.fn_item_nutrients('[{"food_id": "0192f000-0000-7000-8000-000000000003", "quantity": 2.5, "unit_code": "piece"}]')),
    100.0, 'roti: 2.5 medium pieces = 100 g'
);
-- ml portion of a g-based food: converted with the food's density.
INSERT INTO nutrition.food_item (id, name, category_code, basis, density_g_per_ml, is_cooked, source_ref, calories_kcal)
VALUES ('0192f000-0000-7000-8000-0000000002f1', 'Thick Kheer', 'dal_gravy', 'g', 1.200, TRUE, 'pgtap', 100);
SELECT is(
    (SELECT row(consumed_amount, consumed_basis, calories_kcal)::text FROM nutrition.fn_item_nutrients('[{"food_id": "0192f000-0000-7000-8000-0000000002f1", "quantity": 1, "unit_code": "katori"}]')),
    '(180.0,g,180.000)', '150 ml of a g-based food with density 1.2 = 180 g'
);

SELECT throws_ok($$SELECT * FROM nutrition.fn_item_nutrients('[]')$$, '22023', NULL, 'a meal needs at least one item');
SELECT throws_ok(
    format('SELECT * FROM nutrition.fn_item_nutrients(%L)', (SELECT jsonb_agg(jsonb_build_object('food_id', '0192f000-0000-7000-8000-000000000001', 'quantity', 1, 'unit_code', 'piece')) FROM generate_series(1, 31))),
    '22023', NULL, 'at most 30 items'
);
SELECT throws_ok(
    $$SELECT * FROM nutrition.fn_item_nutrients('[{"food_id": "0192f000-0000-7000-8000-000000000001", "quantity": 0.3, "unit_code": "piece"}]')$$,
    '22023', NULL, 'quantity must be a multiple of 0.25'
);
SELECT throws_ok(
    $$SELECT * FROM nutrition.fn_item_nutrients('[{"food_id": "0192f000-0000-7000-8000-000000000001", "quantity": 20.25, "unit_code": "piece"}]')$$,
    '22023', NULL, 'quantity at most 20'
);
SELECT throws_ok(
    $$SELECT * FROM nutrition.fn_item_nutrients('[{"food_id": "0192f000-0000-7000-8000-000000000001", "quantity": "1", "unit_code": "piece"}]')$$,
    '22023', NULL, 'quantity must be a JSON number'
);
SELECT throws_ok(
    $$SELECT * FROM nutrition.fn_item_nutrients('[{"food_id": "0192f000-0000-7000-8000-000000000001", "quantity": 1, "unit_code": "plate"}]')$$,
    '22023', NULL, 'a unit the food does not offer is rejected'
);
SELECT throws_ok(
    $$SELECT * FROM nutrition.fn_item_nutrients('[{"food_id": "0192f000-0000-7000-8000-000000000001", "quantity": 1, "unit_code": "piece", "unit_size": "half"}]')$$,
    '22023', NULL, 'a size the food does not offer is rejected'
);
SELECT throws_ok(
    $$SELECT * FROM nutrition.fn_item_nutrients('[{"food_id": "0192f000-0000-7000-8000-0000000009ff", "quantity": 1, "unit_code": "piece"}]')$$,
    '22023', NULL, 'unknown foods are rejected'
);
UPDATE nutrition.food_item SET status = 'retired'
WHERE id = '0192f000-0000-7000-8000-0000000002f1';
SELECT throws_ok(
    $$SELECT * FROM nutrition.fn_item_nutrients('[{"food_id": "0192f000-0000-7000-8000-0000000002f1", "quantity": 1, "unit_code": "katori"}]')$$,
    '22023', NULL, 'retired foods cannot be logged'
);

-- ===== Search =====
SELECT is(
    (SELECT name FROM nutrition.fn_search_foods('chapati') LIMIT 1), 'Roti (Whole Wheat)',
    'Hinglish/English alias finds the food (chapati -> roti)'
);
SELECT is(
    (SELECT matched_alias FROM nutrition.fn_search_foods('chapati') LIMIT 1), 'Chapati', 'the matched alias is returned'
);
SELECT ok(
    (SELECT bool_and(name ILIKE '%moong%') FROM (SELECT name FROM nutrition.fn_search_foods('moong') LIMIT 3) AS t),
    'prefix matches rank first'
);
SELECT ok(
    EXISTS (
        SELECT 1 FROM nutrition.fn_search_foods('mung')
        WHERE name = 'Moong Dal (Cooked)'
    ),
    'spelling variant found (mung -> moong)'
);
SELECT ok(
    EXISTS (
        SELECT 1 FROM nutrition.fn_search_foods('banan')
        WHERE name = 'Banana'
    ),
    'typo-tolerant partial word'
);
SELECT is(
    (
        SELECT round(kcal_per_default) FROM nutrition.fn_search_foods('apple')
        WHERE name = 'Apple'
    ),
    78::numeric, 'results carry the kcal of the default portion'
);
SELECT is((SELECT count(*)::integer FROM nutrition.fn_search_foods('%')), 0, 'LIKE wildcards are matched literally');
SELECT is((SELECT count(*)::integer FROM nutrition.fn_search_foods('kheer')), 0, 'retired foods are not offered');
SELECT ok((SELECT count(*) FROM nutrition.fn_search_foods('a', 100)) <= 25, 'at most 25 results');
SELECT throws_ok($$SELECT * FROM nutrition.fn_search_foods('   ')$$, '22023', NULL, 'empty query rejected');
SELECT throws_ok(format('SELECT * FROM nutrition.fn_search_foods(%L)', repeat('a', 65)), '22023', NULL, 'query over 64 rejected');

-- ===== Detail =====
SELECT is(
    (SELECT row(name, basis, (nutrients ->> 'calories')::numeric, jsonb_array_length(portions) > 0, aliases)::text FROM nutrition.fn_food_detail('0192f000-0000-7000-8000-000000000003')),
    '("Roti (Whole Wheat)",g,297.000,t,"[""Chapati"", ""Phulka""]")', 'food detail: nutrients per 100 g, portions, aliases'
);
SELECT is((SELECT count(*)::integer FROM nutrition.fn_food_detail('0192f000-0000-7000-8000-0000000002f1')), 0, 'no detail for retired foods');

-- ===== Voice phrases (OQ-43) =====
SELECT is(
    (SELECT array_agg(coalesce(name, '-') ORDER BY phrase_no) FROM nutrition.fn_alias_match(ARRAY['roti', 'chawal', 'dahi', 'mung dal', 'pizza'])),
    ARRAY['Roti (Whole Wheat)', 'Rice (Cooked)', 'Curd', 'Moong Dal (Cooked)', '-'],
    'phrases match names and Hinglish aliases; unknown phrases stay unmatched'
);
SELECT throws_ok($$SELECT * FROM nutrition.fn_alias_match(ARRAY[]::text[])$$, '22023', NULL, 'at least one phrase');
SELECT throws_ok(format('SELECT * FROM nutrition.fn_alias_match(%L)', ARRAY[repeat('x', 61)]), '22023', NULL, 'phrases up to 60 characters');

-- ===== Nutritionist food upsert (OQ-42) =====
SELECT throws_ok(
    $$CALL nutrition.pr_admin_upsert_food('0192f000-0000-7000-8000-0000000002a1', NULL, 'Poha', 'rice_dish', 'g', NULL, TRUE, 'IFCT 2017', '{"calories": 130}', '["Chivda"]', 'hinglish', NULL)$$,
    '42501', NULL, 'a regular user cannot change the food database'
);
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000002a2', TRUE);
CREATE TEMP TABLE new_food (o_food_id uuid);
DO $$
DECLARE v uuid;
BEGIN
    CALL nutrition.pr_admin_upsert_food('0192f000-0000-7000-8000-0000000002a2', NULL, 'Poha', 'rice_dish', 'g', NULL, TRUE,
        'IFCT 2017', '{"calories": 130, "protein": 2.6, "carbohydrates": 26, "fat": 2.3, "iron": 2.7}', '["Chivda", "Aval"]', 'hinglish', v);
    INSERT INTO new_food VALUES (v);
END
$$;
SELECT is(
    (
        SELECT row(f.name, f.calories_kcal, f.iron_mg, f.sodium_mg, f.source_ref, f.created_by)::text FROM nutrition.food_item AS f
        WHERE f.id = (SELECT o_food_id FROM new_food)
    ),
    '(Poha,130.000,2.700,0.000,"IFCT 2017",0192f000-0000-7000-8000-0000000002a2)', 'nutritionist creates a food; missing nutrients are 0'
);
SELECT is(
    (SELECT name FROM nutrition.fn_search_foods('aval') LIMIT 1), 'Poha', 'new aliases are searchable at once'
);
DO $$
DECLARE v uuid := (SELECT o_food_id FROM new_food);
BEGIN
    CALL nutrition.pr_admin_upsert_food('0192f000-0000-7000-8000-0000000002a2', v, 'Poha (Kanda)', 'rice_dish', 'g', NULL, TRUE,
        'IFCT 2017', '{"calories": 140}', '["Chivda"]', 'hinglish', v);
END
$$;
SELECT is(
    (
        SELECT array_agg(alias ORDER BY alias) FROM nutrition.food_alias
        WHERE food_id = (SELECT o_food_id FROM new_food) AND deleted_at IS NULL
    ),
    ARRAY['Chivda']::common.safe_text[], 'the alias list is replaced (removed aliases are soft-deleted)'
);
SELECT throws_ok(
    $$CALL nutrition.pr_admin_upsert_food('0192f000-0000-7000-8000-0000000002a2', NULL, 'Upma', 'rice_dish', 'g', NULL, TRUE, 'IFCT', '{"kcal": 1}', NULL, 'en', NULL)$$,
    '22023', NULL, 'unknown nutrient keys are rejected'
);
SELECT throws_ok(
    $$CALL nutrition.pr_admin_upsert_food('0192f000-0000-7000-8000-0000000002a2', NULL, 'Upma', 'rice_dish', 'g', NULL, TRUE, 'IFCT', '{"protein": 101}', NULL, 'en', NULL)$$,
    '23514', NULL, 'nutrient ranges are enforced'
);
SELECT throws_ok(
    $$CALL nutrition.pr_admin_upsert_food('0192f000-0000-7000-8000-0000000002a2', NULL, 'Upma', 'not_a_category', 'g', NULL, TRUE, 'IFCT', '{}', NULL, 'en', NULL)$$,
    '23503', NULL, 'unknown categories are rejected'
);
-- Layer 3: no markup in food names, sources or aliases.
SELECT
    throws_ok(
        format(
            $$CALL nutrition.pr_admin_upsert_food('0192f000-0000-7000-8000-0000000002a2', NULL, %L, 'rice_dish', 'g', NULL, TRUE, 'IFCT', '{}', NULL, 'en', NULL)$$,
            payload
        ),
        '22023', NULL, format('payload #%s rejected as a food name', id)
    )
FROM test_payloads
WHERE char_length(payload) <= 120
ORDER BY id;
SELECT
    throws_ok(
        format(
            $$CALL nutrition.pr_admin_upsert_food('0192f000-0000-7000-8000-0000000002a2', NULL, 'Upma', 'rice_dish', 'g', NULL, TRUE, 'IFCT', '{}', %L, 'en', NULL)$$,
            jsonb_build_array(payload)
        ),
        '22023', NULL, format('payload #%s rejected as an alias', id)
    )
FROM test_payloads
WHERE char_length(payload) <= 60
ORDER BY id;

-- ===== Barcode cache (OQ-44) =====
CREATE TEMP TABLE bc (food_id uuid);
DO $$
DECLARE v uuid;
BEGIN
    CALL nutrition.pr_upsert_barcode_product('0192f000-0000-7000-8000-0000000002a2', '8901234567890', 'Masala Oats', 'Brand X', 38,
        '{"calories": 380, "protein": 12, "carbohydrates": 64, "fat": 8}', v);
    INSERT INTO bc VALUES (v);
END
$$;
SELECT isnt((SELECT food_id FROM bc), NULL, 'a product with calories gets a loggable packaged food');
SELECT is(
    (SELECT row(product_name, (nutrients ->> 'calories')::numeric, nutrients ? 'iron', food_id = (SELECT food_id FROM bc))::text FROM nutrition.fn_barcode_lookup('8901234567890')),
    '("Masala Oats",380.000,f,t)', 'lookup returns the cached product; unknown nutrients are omitted'
);
SELECT is(
    (SELECT round(calories_kcal) FROM nutrition.fn_item_nutrients(format('[{"food_id": "%s", "quantity": 1, "unit_code": "serving"}]', (SELECT food_id FROM bc))::jsonb)),
    144::numeric, 'one stated serving (38 g) of the packaged food'
);
SELECT is((SELECT count(*)::integer FROM nutrition.fn_search_foods('masala oats')), 0, 'packaged foods are not offered in name search');
DO $$
DECLARE v uuid;
BEGIN
    CALL nutrition.pr_upsert_barcode_product('0192f000-0000-7000-8000-0000000002a2', '8901234567891', 'Broken Data Bar', NULL, NULL,
        '{"calories": 500, "protein": 60, "carbohydrates": 60}', v);
    INSERT INTO bc VALUES (v);
END
$$;
SELECT is(
    (SELECT food_id FROM nutrition.fn_barcode_lookup('8901234567891')), NULL,
    'impossible values (macros over 100 g) leave the product cached but not loggable'
);
SELECT throws_ok(
    $$CALL nutrition.pr_upsert_barcode_product('0192f000-0000-7000-8000-0000000002a2', '12ab', 'X', NULL, NULL, '{}', NULL)$$,
    '23514', NULL, 'barcodes are 8-14 digits'
);
SELECT
    throws_ok(
        format(
            $$CALL nutrition.pr_upsert_barcode_product('0192f000-0000-7000-8000-0000000002a2', '8901234567892', %L, NULL, NULL, '{}', NULL)$$,
            payload
        ),
        '22023', NULL, format('payload #%s rejected as a product name', id)
    )
FROM test_payloads
WHERE char_length(payload) <= 160
ORDER BY id;

-- ===== Privileges =====
SELECT ok(NOT has_function_privilege('app_rw', 'nutrition.fn_item_nutrients(jsonb)', 'EXECUTE'), 'app_rw cannot call the internal nutrient maths');
SELECT ok(NOT has_function_privilege('app_rw', 'nutrition.pr_refresh_daily_summary(uuid, date)', 'EXECUTE'), 'app_rw cannot call the internal summary rebuild');
SELECT ok(has_function_privilege('app_rw', 'nutrition.fn_search_foods(text, integer)', 'EXECUTE'), 'app_rw can search foods');

SELECT * FROM finish();
ROLLBACK;
