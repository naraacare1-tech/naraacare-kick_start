CREATE TABLE nutrition.food_unit_override (
    food_id uuid NOT NULL REFERENCES nutrition.food_item (id) ON DELETE CASCADE,
    unit_code common.code NOT NULL REFERENCES ref.unit (code),
    size common.code NOT NULL CHECK (size IN ('standard', 'small', 'medium', 'large', 'half', 'full')),
    quantity numeric(6, 1) NOT NULL CHECK (quantity > 0 AND quantity <= 2000),
    basis common.code NOT NULL CHECK (basis IN ('g', 'ml')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (food_id, unit_code, size)
);
COMMENT ON TABLE nutrition.food_unit_override IS 'Food-specific portion overriding the category default';
