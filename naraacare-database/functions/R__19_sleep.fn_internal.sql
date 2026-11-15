-- Internal building blocks for sleep (doc 06 section 4, OQ-23). Not granted to any login role; called
-- from the definer functions/procedures, which run as api_definer under RLS (own rows only).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

-- The sleep constants of the calc_version in force (ref.calc_constant; never hard-coded).
CREATE OR REPLACE FUNCTION sleep.fn_constants()
RETURNS TABLE (
    calc_version common.version_label,
    onset_buffer_min integer,
    wake_buffer_min integer,
    waking_fallback_min integer,
    max_entry_hours integer,
    good_from_pct integer,
    fair_from_pct integer
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
    WITH v AS (
        SELECT max(cv.code) AS code FROM ref.calc_version AS cv WHERE cv.effective_from <= current_date
    )
    SELECT
        v.code,
        max(c.value) FILTER (WHERE c.key = 'sleep.onset_buffer_min')::integer,
        max(c.value) FILTER (WHERE c.key = 'sleep.wake_buffer_min')::integer,
        max(c.value) FILTER (WHERE c.key = 'sleep.waking_fallback_min')::integer,
        max(c.value) FILTER (WHERE c.key = 'sleep.max_entry_hours')::integer,
        max(c.value) FILTER (WHERE c.key = 'sleep.label.good_from_pct')::integer,
        max(c.value) FILTER (WHERE c.key = 'sleep.label.fair_from_pct')::integer
    FROM v
    INNER JOIN ref.calc_constant AS c ON c.calc_version = v.code
    GROUP BY v.code;
$$;

COMMENT ON FUNCTION sleep.fn_constants() IS 'Internal: sleep buffers, limits and label thresholds of the calc_version in force';
REVOKE ALL ON FUNCTION sleep.fn_constants() FROM public;

-- counted = (wake - wake buffer) - (start + onset buffer) - sum((back_asleep + fallback) - woke), >= 0.
-- p_wakings: [{"woke_at": ts, "back_asleep_at": ts}] (already validated by the caller).
CREATE OR REPLACE FUNCTION sleep.fn_counted_min(
    p_start timestamptz,
    p_wake timestamptz,
    p_wakings jsonb,
    p_onset_min integer,
    p_wake_min integer,
    p_fallback_min integer
)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT greatest(
        0,
        floor(
            extract(epoch FROM (
                (p_wake - make_interval(mins => p_wake_min))
                - (p_start + make_interval(mins => p_onset_min))
            )) / 60
            - coalesce((
                SELECT sum(
                    extract(epoch FROM (
                        (w ->> 'back_asleep_at')::timestamptz + make_interval(mins => p_fallback_min)
                        - (w ->> 'woke_at')::timestamptz
                    )) / 60
                )
                FROM jsonb_array_elements(coalesce(p_wakings, '[]'::jsonb)) AS w
            ), 0)
        )
    )::integer
$$;

COMMENT ON FUNCTION sleep.fn_counted_min(timestamptz, timestamptz, jsonb, integer, integer, integer) IS
'Internal: counted sleep minutes of one entry (doc 06 section 4)';
REVOKE ALL ON FUNCTION sleep.fn_counted_min(timestamptz, timestamptz, jsonb, integer, integer, integer) FROM public;

-- Edit window: the user's last 2 non-deleted entries (by wake time), within 7 days (OQ-53).
CREATE OR REPLACE FUNCTION sleep.fn_editable_entry_ids(p_user_id uuid)
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT e.id
    FROM (
        SELECT e.id, e.wake_time
        FROM sleep.entry AS e
        WHERE e.user_id = p_user_id AND e.deleted_at IS NULL
        ORDER BY e.wake_time DESC, e.id DESC
        LIMIT 2
    ) AS e
    WHERE e.wake_time > now() - interval '7 days';
$$;

COMMENT ON FUNCTION sleep.fn_editable_entry_ids(uuid) IS
'Internal: ids of the sleep entries still editable (last 2 by wake time, within 7 days)';
REVOKE ALL ON FUNCTION sleep.fn_editable_entry_ids(uuid) FROM public;
