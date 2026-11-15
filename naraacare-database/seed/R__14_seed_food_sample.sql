-- DEVELOPMENT SAMPLE FOODS — approximate values for building and testing only.
-- Loaded only when the Flyway placeholder seed_sample_foods = 'true' (dev/staging). NEVER in prod.
-- The real food database comes from the nutritionist with mandatory source references (OQ-42).

DO $sample$
BEGIN
    IF '${seed_sample_foods}' <> 'true' THEN
        RETURN;
    END IF;

    INSERT INTO nutrition.food_item (
        id, name, category_code, basis, is_cooked, source_ref,
        calories_kcal, protein_g, carbohydrates_g, fat_g, dietary_fiber_g, total_sugar_g,
        iron_mg, calcium_mg, vitamin_c_mg
    ) VALUES
        ('0192f000-0000-7000-8000-000000000001', 'Apple', 'whole_fruit', 'g', false, 'dev-sample (approximate, not for production)', 52, 0.3, 14, 0.2, 2.4, 10.4, 0.1, 6, 4.6),
        ('0192f000-0000-7000-8000-000000000002', 'Banana', 'whole_fruit', 'g', false, 'dev-sample (approximate, not for production)', 89, 1.1, 22.8, 0.3, 2.6, 12.2, 0.3, 5, 8.7),
        ('0192f000-0000-7000-8000-000000000003', 'Roti (Whole Wheat)', 'roti', 'g', true, 'dev-sample (approximate, not for production)', 297, 9.8, 46, 7.5, 9.5, 1.5, 3.2, 30, 0),
        ('0192f000-0000-7000-8000-000000000004', 'Moong Dal (Cooked)', 'dal_gravy', 'ml', true, 'dev-sample (approximate, not for production)', 105, 7, 19, 0.4, 7.6, 2, 1.4, 27, 1),
        ('0192f000-0000-7000-8000-000000000005', 'Moong Dal (Tadka)', 'dal_gravy', 'ml', true, 'dev-sample (approximate, not for production)', 130, 7, 18, 3.5, 7, 2, 1.4, 27, 1),
        ('0192f000-0000-7000-8000-000000000006', 'Moong Dal Chilla', 'roti', 'g', true, 'dev-sample (approximate, not for production)', 180, 10, 22, 6, 5, 1.5, 2, 30, 2),
        ('0192f000-0000-7000-8000-000000000007', 'Rice (Cooked)', 'rice_dish', 'g', true, 'dev-sample (approximate, not for production)', 130, 2.7, 28, 0.3, 0.4, 0.1, 0.2, 10, 0),
        ('0192f000-0000-7000-8000-000000000008', 'Curd', 'dal_gravy', 'ml', false, 'dev-sample (approximate, not for production)', 61, 3.5, 4.7, 3.3, 0, 4.7, 0.1, 121, 0.5),
        ('0192f000-0000-7000-8000-000000000009', 'Aloo Sabzi', 'dry_sabzi', 'g', true, 'dev-sample (approximate, not for production)', 110, 2, 15, 5, 2, 1, 0.6, 15, 9),
        ('0192f000-0000-7000-8000-000000000010', 'Milk (Toned)', 'milk_juice', 'ml', false, 'dev-sample (approximate, not for production)', 58, 3.1, 4.7, 3, 0, 4.7, 0, 120, 0),
        ('0192f000-0000-7000-8000-000000000011', 'Tea with Milk and Sugar', 'tea_coffee', 'ml', false, 'dev-sample (approximate, not for production)', 40, 1, 6, 1.2, 0, 5.5, 0, 35, 0),
        ('0192f000-0000-7000-8000-000000000012', 'Ghee', 'oil_sugar_seed', 'g', false, 'dev-sample (approximate, not for production)', 900, 0, 0, 100, 0, 0, 0, 0, 0)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO nutrition.food_alias (food_id, alias, language) VALUES
        ('0192f000-0000-7000-8000-000000000003', 'Chapati', 'en'),
        ('0192f000-0000-7000-8000-000000000003', 'Phulka', 'hinglish'),
        ('0192f000-0000-7000-8000-000000000004', 'Mung Dal', 'en'),
        ('0192f000-0000-7000-8000-000000000008', 'Dahi', 'hinglish'),
        ('0192f000-0000-7000-8000-000000000011', 'Chai', 'hinglish'),
        ('0192f000-0000-7000-8000-000000000007', 'Chawal', 'hinglish')
    ON CONFLICT (food_id, alias_normalized) WHERE deleted_at IS NULL DO NOTHING;

    INSERT INTO nutrition.food_unit_override (food_id, unit_code, size, quantity, basis) VALUES
        ('0192f000-0000-7000-8000-000000000006', 'piece', 'standard', 50, 'g')
    ON CONFLICT (food_id, unit_code, size) DO NOTHING;
END
$sample$;
