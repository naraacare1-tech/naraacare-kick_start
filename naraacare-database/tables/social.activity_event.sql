CREATE TABLE social.activity_event (
    id uuid NOT NULL DEFAULT uuidv7(),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    actor_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    event_type common.code NOT NULL CONSTRAINT activity_event_event_type_check CHECK (event_type IN ('logged', 'goal_completed', 'joined', 'left', 'shared')),
    avatar_type common.code CHECK (avatar_type IN ('hydration', 'nutrition', 'sleep')),
    circle_id uuid REFERENCES social.care_circle (id) ON DELETE CASCADE,
    summary jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(summary) = 'object' AND pg_column_size(summary) < 1024),
    PRIMARY KEY (id, occurred_at),
    -- Avatar events belong to the actor (shown in every circle they share that avatar with);
    -- membership events and avatar cards shared on purpose (V029) belong to one circle.
    CONSTRAINT activity_event_check CHECK (
        (event_type IN ('logged', 'goal_completed') AND avatar_type IS NOT NULL AND circle_id IS NULL)
        OR (event_type IN ('joined', 'left') AND avatar_type IS NULL AND circle_id IS NOT NULL)
        OR (event_type = 'shared' AND avatar_type IS NOT NULL AND circle_id IS NOT NULL)
    )
) PARTITION BY RANGE (occurred_at);
COMMENT ON TABLE social.activity_event IS
'Recent Updates source (fan-out-on-read): summary holds display values only, never free text';
