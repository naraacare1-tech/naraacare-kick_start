-- GET /reference/policies (doc 04 section 2.3): the current version of each policy document. The
-- newest published version wins; before anything is published (development), the newest draft.
-- The app shows these versions at sign-up and sends them back with the consents, so every consent
-- record points at the exact text the user saw (privacy.pr_record_consent).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION ref.fn_policies()
RETURNS TABLE (
    doc_type common.code,
    version common.version_label,
    url common.https_url,
    published_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT DISTINCT ON (d.doc_type) d.doc_type, d.version, d.url, d.published_at
    FROM ref.policy_document AS d
    ORDER BY d.doc_type, (d.published_at IS NOT NULL) DESC, d.published_at DESC NULLS LAST, d.created_at DESC
$$;

COMMENT ON FUNCTION ref.fn_policies() IS 'Current version of each policy document (newest published, else newest draft)';
REVOKE ALL ON FUNCTION ref.fn_policies() FROM public;
GRANT EXECUTE ON FUNCTION ref.fn_policies() TO app_rw, app_worker, app_readonly;
