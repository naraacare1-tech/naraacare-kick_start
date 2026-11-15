-- Indexes for hydration.custom_drink. Each COMMENT names the query it serves (doc 05 section 6).
CREATE UNIQUE INDEX uq_custom_drink__user_name ON hydration.custom_drink (user_id, lower(name::text)) WHERE deleted_at IS NULL;
COMMENT ON INDEX hydration.uq_custom_drink__user_name IS 'serves: UNIQUE: a custom drink name is saved once per user';
