CREATE TABLE notify.notification (
    id uuid NOT NULL DEFAULT uuidv7(),
    created_at timestamptz NOT NULL DEFAULT now(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    circle_id uuid,
    category common.code NOT NULL,
    template_code common.code NOT NULL,
    params jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(params) = 'object' AND pg_column_size(params) < 2048),
    deep_link common.deep_link,
    read_at timestamptz,
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE notify.notification IS
'In-app notification list; template code + params (codes/numbers only), localised by the app';
