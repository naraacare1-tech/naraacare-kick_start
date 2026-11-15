CREATE TABLE hydration.intake (
    id uuid NOT NULL,
    logged_at timestamptz NOT NULL CHECK (logged_at >= '2026-01-01 00:00:00+00'),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    local_date date NOT NULL,
    drink_code common.code REFERENCES ref.drink_type (code),
    custom_drink_id uuid REFERENCES hydration.custom_drink (id),
    volume_ml integer NOT NULL,
    hydration_factor numeric(4, 3) NOT NULL CHECK (hydration_factor BETWEEN 0 AND 1),
    effective_ml numeric(7, 1) NOT NULL,
    source common.code NOT NULL CHECK (source IN ('swipe', 'manual', 'preset', 'rin')),
    version integer NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz,
    PRIMARY KEY (id, logged_at),
    CHECK (num_nonnulls(drink_code, custom_drink_id) = 1),
    CHECK (
        volume_ml BETWEEN 1 AND 3000
        OR (volume_ml = -100 AND source = 'swipe' AND drink_code = 'water')
    ),
    CHECK (effective_ml = round(volume_ml * hydration_factor, 1))
) PARTITION BY RANGE (logged_at);
COMMENT ON TABLE hydration.intake IS
'Drinks with factor snapshot; swipe-down is a -100 mL water adjustment (DOC section 4a). Monthly partitions';
