-- Indexes for nutrition.food_alias. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_food_alias__alias_trgm ON nutrition.food_alias USING gin (alias_normalized gin_trgm_ops);
COMMENT ON INDEX nutrition.ix_food_alias__alias_trgm IS 'serves: search + voice parsing on Hindi/Hinglish aliases (chapati -> roti)';

CREATE INDEX ix_food_alias__food_id ON nutrition.food_alias (food_id);
COMMENT ON INDEX nutrition.ix_food_alias__food_id IS 'serves: FK; aliases of a food';

CREATE UNIQUE INDEX uq_food_alias__food_alias ON nutrition.food_alias (food_id, alias_normalized) WHERE deleted_at IS NULL;
COMMENT ON INDEX nutrition.uq_food_alias__food_alias IS 'serves: UNIQUE: one alias spelling per food; idempotent alias imports';
