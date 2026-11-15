-- Append-only consent record (doc 07 SEC-7.1). Withdrawal is a new row with p_granted = false; rows
-- are never updated (privacy.trg_fn_append_only). For terms/privacy the policy version must be a
-- published ref.policy_document row, so consent always points at the exact text the user saw.
-- Other purposes are recorded against the privacy-policy version the app shows.
-- Errors: 22023 INVALID_PURPOSE / POLICY_VERSION_UNKNOWN.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE privacy.pr_record_consent(
    p_user_id uuid,
    p_purpose common.code,
    p_policy_version common.version_label,
    p_granted boolean,
    p_app_version common.app_version DEFAULT NULL,
    p_ip inet DEFAULT NULL,
    INOUT o_consent_id bigint DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_doc_id bigint;
    v_doc_type text := CASE p_purpose WHEN 'terms' THEN 'terms' ELSE 'privacy' END;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_purpose NOT IN ('terms', 'privacy', 'health_data', 'ai_processing', 'circle_sharing', 'marketing') THEN
        RAISE EXCEPTION 'unknown consent purpose' USING ERRCODE = '22023', DETAIL = 'INVALID_PURPOSE';
    END IF;
    IF p_granted IS NULL THEN
        RAISE EXCEPTION 'granted must be true or false' USING ERRCODE = '22023', DETAIL = 'INVALID_ARGUMENT';
    END IF;
    -- Session 15: the app cannot work without terms, privacy and health data; withdrawing them is
    -- the account deletion path (doc 07 SEC-7.2), not a consent toggle.
    IF NOT p_granted AND p_purpose IN ('terms', 'privacy', 'health_data') THEN
        RAISE EXCEPTION 'required consent' USING ERRCODE = '22023', DETAIL = 'CONSENT_WITHDRAWAL_BLOCKED';
    END IF;

    SELECT d.id INTO v_doc_id
    FROM ref.policy_document AS d
    WHERE d.doc_type = v_doc_type AND d.version = p_policy_version;
    IF v_doc_id IS NULL AND p_purpose IN ('terms', 'privacy') THEN
        RAISE EXCEPTION 'unknown policy version' USING ERRCODE = '22023', DETAIL = 'POLICY_VERSION_UNKNOWN';
    END IF;

    INSERT INTO privacy.consent_record (user_id, purpose, policy_document_id, policy_version, granted, app_version, ip)
    VALUES (p_user_id, p_purpose, v_doc_id, p_policy_version, p_granted, p_app_version, p_ip)
    RETURNING id INTO o_consent_id;
END
$$;

COMMENT ON PROCEDURE privacy.pr_record_consent (
    uuid, common.code, common.version_label, boolean, common.app_version, inet, bigint
) IS 'Append a consent grant/withdrawal tied to the policy version shown';
REVOKE ALL ON PROCEDURE privacy.pr_record_consent(
    uuid, common.code, common.version_label, boolean, common.app_version, inet, bigint
) FROM public;
GRANT EXECUTE ON PROCEDURE privacy.pr_record_consent(
    uuid, common.code, common.version_label, boolean, common.app_version, inet, bigint
) TO app_rw;
