-- Purges expired authentication artifacts (doc 05 section 9) using the ages in privacy.retention_policy:
--   auth.otp_challenge  created more than N days ago
--   auth.login_attempt  attempted more than N days ago
--   auth.refresh_token  expired or revoked more than N days ago
-- Deletes at most p_batch rows per table per call (one short transaction each), so a backlog never
-- holds long locks or produces one huge WAL burst; the worker calls again while o_deleted > 0.
-- A table without a retention_policy row is skipped (no silent default).
-- Owned by migration_owner (cross-user maintenance).
CREATE OR REPLACE PROCEDURE ops.pr_purge_auth_artifacts(
    p_as_of timestamptz DEFAULT NULL,
    p_batch integer DEFAULT 10000,
    INOUT o_deleted integer DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_as_of timestamptz := coalesce(p_as_of, now());
    v_days integer;
    v_count integer;
BEGIN
    o_deleted := 0;
    IF p_batch IS NULL OR p_batch NOT BETWEEN 1 AND 100000 THEN
        RAISE EXCEPTION 'p_batch must be 1..100000' USING ERRCODE = '22023', DETAIL = 'INVALID_ARGUMENT';
    END IF;

    SELECT retention_days INTO v_days FROM privacy.retention_policy WHERE table_name = 'auth.otp_challenge';
    IF v_days IS NOT NULL THEN
        DELETE FROM auth.otp_challenge
        WHERE id IN (
            SELECT id FROM auth.otp_challenge
            WHERE created_at < v_as_of - make_interval(days => v_days)
            LIMIT p_batch
        );
        GET DIAGNOSTICS v_count = ROW_COUNT;
        o_deleted := o_deleted + v_count;
    END IF;

    v_days := NULL;
    SELECT retention_days INTO v_days FROM privacy.retention_policy WHERE table_name = 'auth.login_attempt';
    IF v_days IS NOT NULL THEN
        DELETE FROM auth.login_attempt
        WHERE id IN (
            SELECT id FROM auth.login_attempt
            WHERE attempted_at < v_as_of - make_interval(days => v_days)
            LIMIT p_batch
        );
        GET DIAGNOSTICS v_count = ROW_COUNT;
        o_deleted := o_deleted + v_count;
    END IF;

    v_days := NULL;
    SELECT retention_days INTO v_days FROM privacy.retention_policy WHERE table_name = 'auth.refresh_token';
    IF v_days IS NOT NULL THEN
        DELETE FROM auth.refresh_token
        WHERE id IN (
            SELECT id FROM auth.refresh_token
            WHERE expires_at < v_as_of - make_interval(days => v_days)
               OR revoked_at < v_as_of - make_interval(days => v_days)
            LIMIT p_batch
        );
        GET DIAGNOSTICS v_count = ROW_COUNT;
        o_deleted := o_deleted + v_count;
    END IF;
END
$$;

COMMENT ON PROCEDURE ops.pr_purge_auth_artifacts (timestamptz, integer, integer) IS
'Batched purge of old OTP challenges, login attempts and refresh tokens per privacy.retention_policy';
REVOKE ALL ON PROCEDURE ops.pr_purge_auth_artifacts(timestamptz, integer, integer) FROM public;
GRANT EXECUTE ON PROCEDURE ops.pr_purge_auth_artifacts(timestamptz, integer, integer) TO app_worker;
