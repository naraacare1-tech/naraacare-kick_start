-- Indexes for nutrition.food_item. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_food_item__name_trgm ON nutrition.food_item USING gin (name_normalized gin_trgm_ops) WHERE status = 'active';
COMMENT ON INDEX nutrition.ix_food_item__name_trgm IS 'serves: nutrition.fn_search_foods typo-tolerant search (moong / mung)';

CREATE INDEX ix_food_item__search_vector ON nutrition.food_item USING gin (search_vector);
COMMENT ON INDEX nutrition.ix_food_item__search_vector IS 'serves: word search on food names';

CREATE INDEX ix_food_item__category_code ON nutrition.food_item (category_code);
COMMENT ON INDEX nutrition.ix_food_item__category_code IS 'serves: admin filter by category';
