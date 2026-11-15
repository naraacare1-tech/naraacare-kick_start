CREATE TABLE ref.wallpaper (
    code common.code PRIMARY KEY,
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 40),
    asset_key common.asset_key NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.wallpaper IS 'Care Circle wallpapers (assets pending design)';
