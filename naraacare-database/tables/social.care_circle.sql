CREATE TABLE social.care_circle (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    name common.safe_text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 50),
    wallpaper_code common.code REFERENCES ref.wallpaper (code),
    created_by_user uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    member_count smallint NOT NULL DEFAULT 0 CHECK (member_count BETWEEN 0 AND 50),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz
);
COMMENT ON TABLE social.care_circle IS
'Care Circles; member_count = active members (kept by the procedures, doc 05 section 8)';
