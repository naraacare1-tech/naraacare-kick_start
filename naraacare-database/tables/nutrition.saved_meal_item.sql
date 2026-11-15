CREATE TABLE nutrition.saved_meal_item (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    saved_meal_id uuid NOT NULL REFERENCES nutrition.saved_meal (id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    food_id uuid NOT NULL REFERENCES nutrition.food_item (id),
    quantity numeric(5, 2) NOT NULL CHECK (quantity BETWEEN 0.25 AND 20),
    unit_code common.code NOT NULL REFERENCES ref.unit (code),
    unit_size common.code NOT NULL CHECK (unit_size IN ('standard', 'small', 'medium', 'large', 'half', 'full')),
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE nutrition.saved_meal_item IS 'Items of a saved meal; user_id duplicated so RLS needs no join';
