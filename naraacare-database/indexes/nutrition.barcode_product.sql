-- Indexes for nutrition.barcode_product. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_barcode_product__food_id ON nutrition.barcode_product (food_id) WHERE food_id IS NOT NULL;
COMMENT ON INDEX nutrition.ix_barcode_product__food_id IS 'serves: FK';
