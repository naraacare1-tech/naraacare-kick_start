-- Share an avatar inside NaraaCare (owner 2026-11-08, V029): never outside the app.
--   * Circles: the sender must be an active member; each circle gets a 'shared' card in Recent
--     Updates and members with circle_updates on get 'circle_avatar_shared'.
--   * People: accepted connections only (not blocked either way); each gets an 'avatar_shared'
--     notification. Strangers cannot be reached, so sharing cannot be used to spam.
--   * The snapshot is today's values from social.fn_avatar_state (numbers only), worked out here;
--     the app sends only the avatar and the recipients. Sleep needs STAR to share (as for circles).
-- Errors: 42501 not a member (404), P0001 USERNAME_REQUIRED / UPGRADE_REQUIRED,
--         22023 INVALID_AVATAR / RECIPIENTS_INVALID / RECIPIENT_INVALID.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE social.pr_share_avatar(
    p_user_id uuid,
    p_avatar_type text,
    p_circle_ids uuid[] DEFAULT '{}',
    p_user_ids uuid[] DEFAULT '{}',
    INOUT o_shared integer DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_username text;
    v_circles uuid[];
    v_users uuid[];
    v_circle uuid;
    v_state jsonb;
    v_summary jsonb;
    v_params jsonb;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    v_username := social.fn_require_username(p_user_id);
    IF p_avatar_type IS NULL OR NOT p_avatar_type = ANY (ARRAY['hydration', 'nutrition', 'sleep']) THEN
        RAISE EXCEPTION 'unknown avatar type' USING ERRCODE = '22023', DETAIL = 'INVALID_AVATAR';
    END IF;
    IF p_avatar_type = 'sleep' AND NOT social.fn_is_star(p_user_id) THEN
        RAISE EXCEPTION 'sharing the Sleep avatar needs STAR' USING ERRCODE = 'P0001', DETAIL = 'UPGRADE_REQUIRED';
    END IF;

    SELECT coalesce(array_agg(DISTINCT c), '{}') INTO v_circles
    FROM unnest(coalesce(p_circle_ids, '{}')) AS c WHERE c IS NOT NULL;
    SELECT coalesce(array_agg(DISTINCT u), '{}') INTO v_users
    FROM unnest(coalesce(p_user_ids, '{}')) AS u WHERE u IS NOT NULL;
    IF cardinality(v_circles) + cardinality(v_users) = 0
       OR cardinality(v_circles) > 10 OR cardinality(v_users) > 20 THEN
        RAISE EXCEPTION 'choose 1 to 10 circles and up to 20 people' USING ERRCODE = '22023', DETAIL = 'RECIPIENTS_INVALID';
    END IF;

    FOREACH v_circle IN ARRAY v_circles LOOP
        PERFORM social.fn_require_member(v_circle, p_user_id);
    END LOOP;
    IF EXISTS (
        SELECT 1 FROM unnest(v_users) AS u
        WHERE u = p_user_id
           OR social.fn_is_blocked(p_user_id, u)
           OR NOT EXISTS (
               SELECT 1 FROM social.connection AS c
               WHERE c.user_low = least(p_user_id, u) AND c.user_high = greatest(p_user_id, u)
                 AND c.status = 'accepted' AND c.deleted_at IS NULL
           )
    ) THEN
        RAISE EXCEPTION 'you can only share with your connections' USING ERRCODE = '22023', DETAIL = 'RECIPIENT_INVALID';
    END IF;

    -- Numbers only: drop anything that is not a number or a boolean (local_date is implied by the
    -- time of the event).
    v_state := coalesce(social.fn_avatar_state(p_user_id, p_avatar_type), '{}'::jsonb);
    SELECT coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) INTO v_summary
    FROM jsonb_each(v_state) AS e
    WHERE jsonb_typeof(e.value) IN ('number', 'boolean');

    FOREACH v_circle IN ARRAY v_circles LOOP
        INSERT INTO social.activity_event (actor_id, event_type, avatar_type, circle_id, summary)
        VALUES (p_user_id, 'shared', p_avatar_type, v_circle, v_summary);
        CALL social.pr_notify(
            social.fn_recipients(v_circle, 'circle_updates', p_user_id), v_circle, 'circles',
            'circle_avatar_shared',
            jsonb_build_object('user_id', p_user_id::text, 'avatar_type', p_avatar_type),
            social.fn_circle_link(v_circle, '/feed')
        );
    END LOOP;
    IF cardinality(v_users) > 0 THEN
        SELECT jsonb_build_object('user_id', p_user_id::text, 'username', v_username, 'avatar_type', p_avatar_type)
               || coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
        INTO v_params
        FROM jsonb_each(v_summary) AS e
        WHERE jsonb_typeof(e.value) = 'number';
        CALL social.pr_notify(v_users, NULL, 'connections', 'avatar_shared', v_params, 'naraacare://notifications');
    END IF;
    o_shared := cardinality(v_circles) + cardinality(v_users);
END
$$;

COMMENT ON PROCEDURE social.pr_share_avatar(uuid, text, uuid[], uuid[], integer) IS
'Share today''s avatar snapshot with own circles (feed card) and connections (notification)';
REVOKE ALL ON PROCEDURE social.pr_share_avatar(uuid, text, uuid[], uuid[], integer) FROM public;
GRANT EXECUTE ON PROCEDURE social.pr_share_avatar(uuid, text, uuid[], uuid[], integer) TO app_rw;
