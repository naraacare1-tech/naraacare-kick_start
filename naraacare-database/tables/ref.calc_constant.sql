CREATE TABLE ref.calc_constant (
    calc_version common.version_label NOT NULL REFERENCES ref.calc_version (code),
    key common.code NOT NULL,
    value numeric NOT NULL,
    unit common.code NOT NULL,
    source common.safe_text NOT NULL CHECK (char_length(source) BETWEEN 1 AND 200),
    is_product_choice boolean NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (calc_version, key)
);
COMMENT ON TABLE ref.calc_constant IS 'Every formula constant from doc 06; is_product_choice = needs expert review';
