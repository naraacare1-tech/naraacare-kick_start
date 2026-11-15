-- Referral programme (doc 04 section 2.12, doc 06 section 6, OQ-39, Session 11).
--   * pr_ensure_referral_code: the caller's code (8 characters from an unambiguous A-Z/2-9 set),
--     created once; collisions retry.
--   * pr_attribute_referral (POST /referrals/attribute): attributes the caller to a referrer. The
--     endpoint answers 204 whatever happens, so o_status only feeds the logs: 'attributed', or
--     'ignored_*' for an unknown code, self-referral, an account older than 7 days, an account already
--     attributed, or an installation already seen on another account (anti-fraud, doc 06 section 6).
--   * fn_referral_progress (GET /referrals/me): code, qualified count, friends (initial or username,
--     active days, status) and the reward. Friends' real names are never shown.
-- Errors: 42501 not the actor, 23514 malformed code (common.referral_code domain; the API upper-cases).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE billing.pr_ensure_referral_code(p_user_id uuid, INOUT o_code text DEFAULT NULL)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    v_bytes bytea;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT c.code INTO o_code FROM billing.referral_code AS c WHERE c.user_id = p_user_id;
    IF FOUND THEN
        RETURN;
    END IF;
    FOR attempt IN 1..10 LOOP
        v_bytes := public.gen_random_bytes(8);
        o_code := '';
        FOR i IN 0..7 LOOP
            o_code := o_code || substr(v_alphabet, get_byte(v_bytes, i) % 32 + 1, 1);
        END LOOP;
        BEGIN
            INSERT INTO billing.referral_code (user_id, code) VALUES (p_user_id, o_code);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- Code taken (or a concurrent call created ours): re-read, else try another code.
            SELECT c.code INTO o_code FROM billing.referral_code AS c WHERE c.user_id = p_user_id;
            IF FOUND THEN
                RETURN;
            END IF;
        END;
    END LOOP;
    RAISE EXCEPTION 'could not allocate a referral code' USING ERRCODE = 'P0001', DETAIL = 'INTERNAL';
END
$$;

COMMENT ON PROCEDURE billing.pr_ensure_referral_code (uuid, text) IS 'The caller''s referral code, created once';
REVOKE ALL ON PROCEDURE billing.pr_ensure_referral_code(uuid, text) FROM public;
GRANT EXECUTE ON PROCEDURE billing.pr_ensure_referral_code(uuid, text) TO app_rw;

CREATE OR REPLACE PROCEDURE billing.pr_attribute_referral(
    p_user_id uuid,
    p_code common.referral_code,
    p_installation_id uuid,
    INOUT o_status text DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_referrer uuid;
    v_created timestamptz;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT a.created_at INTO v_created FROM auth.user_account AS a WHERE a.id = p_user_id;
    IF v_created < now() - interval '7 days' THEN
        o_status := 'ignored_too_old';
        RETURN;
    END IF;
    IF EXISTS (SELECT 1 FROM billing.referral AS r WHERE r.referred_user_id = p_user_id) THEN
        o_status := 'ignored_already_attributed';
        RETURN;
    END IF;
    SELECT c.user_id INTO v_referrer FROM billing.referral_code AS c WHERE c.code = upper(p_code);
    IF NOT FOUND THEN
        o_status := 'ignored_unknown_code';
        RETURN;
    END IF;
    IF v_referrer = p_user_id THEN
        o_status := 'ignored_self';
        RETURN;
    END IF;
    IF p_installation_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM auth.user_account AS a
        WHERE a.id <> p_user_id AND a.installation_id = p_installation_id
    ) THEN
        o_status := 'ignored_device_seen';
        RETURN;
    END IF;
    INSERT INTO billing.referral (referrer_id, referred_user_id)
    VALUES (v_referrer, p_user_id)
    ON CONFLICT ON CONSTRAINT uq_referral__referred_user DO NOTHING;
    o_status := CASE WHEN FOUND THEN 'attributed' ELSE 'ignored_already_attributed' END;
END
$$;

COMMENT ON PROCEDURE billing.pr_attribute_referral (uuid, common.referral_code, uuid, text) IS
'Attribute the caller (account <= 7 days old) to a referrer; self, duplicate device and repeats ignored';
REVOKE ALL ON PROCEDURE billing.pr_attribute_referral(uuid, common.referral_code, uuid, text) FROM public;
GRANT EXECUTE ON PROCEDURE billing.pr_attribute_referral(uuid, common.referral_code, uuid, text) TO app_rw;

CREATE OR REPLACE FUNCTION billing.fn_referral_progress(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN jsonb_build_object(
        'code', (SELECT c.code FROM billing.referral_code AS c WHERE c.user_id = p_user_id),
        'required', 5,
        'qualified', (
            SELECT count(*) FROM billing.referral AS r WHERE r.referrer_id = p_user_id AND r.status = 'qualified'
        ),
        'friends', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
                'display', coalesce('@' || p.username, upper(left(coalesce(p.username, 'N'), 1))),
                'active_days', r.active_days,
                'status', r.status
            ) ORDER BY r.attributed_at)
            FROM billing.referral AS r
            LEFT JOIN app.user_profile AS p ON p.user_id = r.referred_user_id
            WHERE r.referrer_id = p_user_id
        ), '[]'::jsonb),
        'reward_days', (SELECT w.reward_days FROM billing.referral_reward AS w WHERE w.referrer_id = p_user_id),
        'reward_granted_at', (SELECT w.granted_at FROM billing.referral_reward AS w WHERE w.referrer_id = p_user_id)
    );
END
$$;

COMMENT ON FUNCTION billing.fn_referral_progress(uuid) IS
'The caller''s referral code, friends'' progress (no real names) and reward';
REVOKE ALL ON FUNCTION billing.fn_referral_progress(uuid) FROM public;
GRANT EXECUTE ON FUNCTION billing.fn_referral_progress(uuid) TO app_rw;
