-- Indexes for ref.food_category_unit. Each COMMENT names the query it serves (doc 05 section 6).
CREATE UNIQUE INDEX uq_food_category_unit__default ON ref.food_category_unit (category_code) WHERE is_default;
COMMENT ON INDEX ref.uq_food_category_unit__default IS 'serves: UNIQUE: at most one default portion per food category';
