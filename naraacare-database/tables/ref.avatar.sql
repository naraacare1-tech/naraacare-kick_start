CREATE TABLE ref.avatar (
    code common.code PRIMARY KEY,
    sex common.code NOT NULL CHECK (sex IN ('female', 'male')),
    body_type_code common.code NOT NULL REFERENCES ref.body_type (code),
    asset_key common.asset_key NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (sex, body_type_code)
);
COMMENT ON TABLE ref.avatar IS 'Base avatars: 2 sexes x 3 body types (OQ-56)';
