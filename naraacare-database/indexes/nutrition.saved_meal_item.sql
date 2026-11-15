-- Indexes for nutrition.saved_meal_item. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_saved_meal_item__saved_meal_id ON nutrition.saved_meal_item (saved_meal_id);
COMMENT ON INDEX nutrition.ix_saved_meal_item__saved_meal_id IS 'serves: FK; items of a saved meal';

CREATE INDEX ix_saved_meal_item__user_id ON nutrition.saved_meal_item (user_id);
COMMENT ON INDEX nutrition.ix_saved_meal_item__user_id IS 'serves: FK; account deletion';

CREATE INDEX ix_saved_meal_item__food_id ON nutrition.saved_meal_item (food_id);
COMMENT ON INDEX nutrition.ix_saved_meal_item__food_id IS 'serves: FK';
