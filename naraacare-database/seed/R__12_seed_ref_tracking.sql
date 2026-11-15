-- Tracking reference data: drinks, workouts, nutrients, units and portions (doc 06 sections 2.10, 3.6).

INSERT INTO ref.drink_type (code, label, hydration_factor, tier_required, is_alcohol, display_order) VALUES
('water', 'Water', 1.000, 'standard', FALSE, 1),
('tea', 'Tea', 0.997, 'standard', FALSE, 2),
('milk', 'Milk', 0.880, 'standard', FALSE, 3),
('coconut_water', 'Coconut Water', 0.950, 'standard', FALSE, 4),
('coffee', 'Coffee', 0.994, 'star', FALSE, 5),
('juice', 'Juice', 0.885, 'star', FALSE, 6),
('beer', 'Beer', 0.000, 'star', TRUE, 7)
ON CONFLICT (code) DO UPDATE SET
    label = excluded.label, hydration_factor = excluded.hydration_factor, tier_required = excluded.tier_required,
    is_alcohol = excluded.is_alcohol, display_order = excluded.display_order, updated_at = now();

-- Sweat rates from the DOC; MET values are the OQ-16 proposal.
INSERT INTO ref.workout_type (code, label, sweat_ml_per_kg_h, met, display_order) VALUES
('walking', 'Walking', 5.0, 3.5, 1),
('gym', 'Gym', 7.5, 5.0, 2),
('cycling', 'Cycling', 10.0, 7.5, 3),
('swimming', 'Swimming', 10.0, 7.0, 4),
('running', 'Running', 12.5, 9.8, 5),
('trekking', 'Trekking', 15.0, 6.0, 6)
ON CONFLICT (code) DO UPDATE SET
    label = excluded.label, sweat_ml_per_kg_h = excluded.sweat_ml_per_kg_h, met = excluded.met,
    display_order = excluded.display_order, updated_at = now();

INSERT INTO ref.nutrient (code, label, unit, tier_required, display_order) VALUES
('calories', 'Calories', 'kcal', 'standard', 1),
('protein', 'Protein', 'g', 'standard', 2),
('carbohydrates', 'Carbohydrates', 'g', 'standard', 3),
('fat', 'Fat', 'g', 'standard', 4),
('dietary_fiber', 'Dietary Fiber', 'g', 'standard', 5),
('total_sugar', 'Total Sugar', 'g', 'standard', 6),
('iron', 'Iron', 'mg', 'star', 7),
('calcium', 'Calcium', 'mg', 'star', 8),
('saturated_fat', 'Saturated Fat', 'g', 'star', 9),
('polyunsaturated_fat', 'Polyunsaturated Fat', 'g', 'star', 10),
('monounsaturated_fat', 'Monounsaturated Fat', 'g', 'star', 11),
('trans_fat', 'Trans Fat', 'g', 'star', 12),
('cholesterol', 'Cholesterol', 'mg', 'star', 13),
('potassium', 'Potassium', 'mg', 'star', 14),
('vitamin_a', 'Vitamin A', 'mcg', 'star', 15),
('vitamin_c', 'Vitamin C', 'mg', 'star', 16),
('sodium', 'Sodium', 'mg', 'star', 17)
ON CONFLICT (code) DO UPDATE SET
    label = excluded.label, unit = excluded.unit, tier_required = excluded.tier_required,
    display_order = excluded.display_order, updated_at = now();

INSERT INTO ref.food_category (code, label) VALUES
('dal_gravy', 'Dal, Sambar, Kadhi (liquid gravies)'),
('dry_sabzi', 'Dry Sabzi / Poriyal (vegetables)'),
('rice_dish', 'Rice, Biryani and Pulao'),
('roti', 'Roti, Chapati and Bhakri'),
('naan', 'Naan, Kulcha and Bhatura'),
('meat_paneer', 'Meat, Chicken and Paneer'),
('milk_juice', 'Milk, Chaas, Juices (beverages)'),
('tea_coffee', 'Tea and Coffee'),
('oil_sugar_seed', 'Oils, Ghee, Sugar, Seeds'),
('whole_fruit', 'Whole Fruits'),
('packaged', 'Packaged Products (barcode)')
ON CONFLICT (code) DO UPDATE SET label = excluded.label, updated_at = now();

INSERT INTO ref.unit (code, label) VALUES
('katori', 'Katori'),
('bowl', 'Bowl'),
('tbsp', 'Tablespoon'),
('tsp', 'Teaspoon'),
('cup', 'Cup'),
('glass', 'Glass'),
('mug', 'Mug'),
('cutting', 'Cutting'),
('piece', 'Piece'),
('plate', 'Plate'),
('gram', 'Gram'),
('ml', 'ml'),
('serving', 'Serving')
ON CONFLICT (code) DO UPDATE SET label = excluded.label, updated_at = now();

-- is_confirmed = true: quantity stated in the DOC. false: proposal awaiting product sign-off (OQ-59).
INSERT INTO ref.food_category_unit (category_code, unit_code, size, quantity, basis, is_default, is_confirmed) VALUES
('dal_gravy', 'katori', 'small', 100, 'ml', FALSE, TRUE),
('dal_gravy', 'katori', 'medium', 150, 'ml', TRUE, TRUE),
('dal_gravy', 'katori', 'large', 200, 'ml', FALSE, TRUE),
('dal_gravy', 'bowl', 'standard', 300, 'ml', FALSE, TRUE),
('dal_gravy', 'tbsp', 'standard', 15, 'ml', FALSE, TRUE),
('dal_gravy', 'cup', 'standard', 200, 'ml', FALSE, FALSE),
('dry_sabzi', 'katori', 'medium', 110, 'g', TRUE, FALSE),
('dry_sabzi', 'tbsp', 'standard', 15, 'g', FALSE, TRUE),
('dry_sabzi', 'cup', 'standard', 150, 'g', FALSE, FALSE),
('rice_dish', 'katori', 'medium', 150, 'g', TRUE, TRUE),
('rice_dish', 'plate', 'half', 200, 'g', FALSE, TRUE),
('rice_dish', 'plate', 'full', 400, 'g', FALSE, TRUE),
('rice_dish', 'tbsp', 'standard', 15, 'g', FALSE, TRUE),
('rice_dish', 'cup', 'standard', 200, 'g', FALSE, FALSE),
('roti', 'piece', 'small', 30, 'g', FALSE, FALSE),
('roti', 'piece', 'medium', 40, 'g', TRUE, TRUE),
('roti', 'piece', 'large', 55, 'g', FALSE, FALSE),
('naan', 'piece', 'standard', 100, 'g', TRUE, TRUE),
('naan', 'piece', 'half', 50, 'g', FALSE, TRUE),
('meat_paneer', 'piece', 'standard', 35, 'g', TRUE, FALSE),
('meat_paneer', 'katori', 'medium', 150, 'g', FALSE, FALSE),
('meat_paneer', 'cup', 'standard', 200, 'g', FALSE, FALSE),
('milk_juice', 'glass', 'standard', 200, 'ml', TRUE, TRUE),
('milk_juice', 'cup', 'standard', 150, 'ml', FALSE, FALSE),
('milk_juice', 'mug', 'standard', 250, 'ml', FALSE, FALSE),
('tea_coffee', 'cup', 'standard', 150, 'ml', TRUE, TRUE),
('tea_coffee', 'mug', 'standard', 250, 'ml', FALSE, FALSE),
('tea_coffee', 'cutting', 'standard', 75, 'ml', FALSE, FALSE),
('oil_sugar_seed', 'tsp', 'standard', 5, 'g', TRUE, TRUE),
('oil_sugar_seed', 'tbsp', 'standard', 15, 'g', FALSE, TRUE),
('whole_fruit', 'piece', 'small', 100, 'g', FALSE, FALSE),
('whole_fruit', 'piece', 'medium', 150, 'g', TRUE, TRUE),
('whole_fruit', 'piece', 'large', 200, 'g', FALSE, FALSE),
('whole_fruit', 'cup', 'standard', 150, 'g', FALSE, FALSE),
-- Barcode products (OQ-44): 100 g unless the product states its serving (food_unit_override).
('packaged', 'serving', 'standard', 100, 'g', TRUE, TRUE)
ON CONFLICT (category_code, unit_code, size) DO UPDATE SET
    quantity = excluded.quantity, basis = excluded.basis, is_default = excluded.is_default,
    is_confirmed = excluded.is_confirmed, updated_at = now();
