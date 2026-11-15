-- Indexes for nutrition.meal_item. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_meal_item__meal ON nutrition.meal_item (meal_id, meal_logged_at);
COMMENT ON INDEX nutrition.ix_meal_item__meal IS 'serves: FK; items of a meal';

CREATE INDEX ix_meal_item__user_food_recent ON nutrition.meal_item (user_id, food_id, meal_logged_at DESC);
COMMENT ON INDEX nutrition.ix_meal_item__user_food_recent IS 'serves: recent foods chips on Add Meal';

CREATE INDEX ix_meal_item__food_id ON nutrition.meal_item (food_id);
COMMENT ON INDEX nutrition.ix_meal_item__food_id IS 'serves: FK; food retirement checks';
