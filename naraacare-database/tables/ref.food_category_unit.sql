CREATE TABLE ref.food_category_unit (
    category_code common.code NOT NULL REFERENCES ref.food_category (code),
    unit_code common.code NOT NULL REFERENCES ref.unit (code),
    size common.code NOT NULL CHECK (size IN ('standard', 'small', 'medium', 'large', 'half', 'full')),
    quantity numeric(6, 1) NOT NULL CHECK (quantity > 0 AND quantity <= 2000),
    basis common.code NOT NULL CHECK (basis IN ('g', 'ml')),
    is_default boolean NOT NULL DEFAULT FALSE,
    is_confirmed boolean NOT NULL DEFAULT FALSE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (category_code, unit_code, size)
);
COMMENT ON TABLE ref.food_category_unit IS
'Default portion per category, unit and size; is_confirmed=false marks proposals awaiting sign-off (OQ-59)';
