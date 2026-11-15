-- Report and support schemas (Session 14, doc 05 section 5.8). Same privilege model as the other
-- schemas (roles/010_roles.sql): app roles may resolve names only; api_definer owns the API routines;
-- worker routines are owned by migration_owner and granted to app_worker (doc 05 section 7).
--   * report: PDF report jobs (the file lives in object storage for 7 days) and the aggregated
--     report.v_* views, the only objects the BI login `reporting` may read.
--   * support: Help & Support tickets and feature requests (plain text, common.safe_text).
CREATE SCHEMA IF NOT EXISTS report;
COMMENT ON SCHEMA report IS 'PDF report jobs and aggregated reporting views';
CREATE SCHEMA IF NOT EXISTS support;
COMMENT ON SCHEMA support IS 'Help & Support tickets and feature requests';

GRANT USAGE ON SCHEMA report TO api_definer, app_rw, app_worker, app_readonly, reporting;
GRANT USAGE ON SCHEMA support TO api_definer, app_rw, app_worker, app_readonly;
GRANT CREATE ON SCHEMA report, support TO api_definer;

ALTER DEFAULT PRIVILEGES FOR ROLE migration_owner IN SCHEMA report
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO api_definer;
ALTER DEFAULT PRIVILEGES FOR ROLE migration_owner IN SCHEMA support
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO api_definer;
