-- Row-level security for the report and support schemas (Session 14): every row belongs to one user
-- and only that user (app.user_id of the transaction) can see or change it through the API routines,
-- as for the other personal tables (roles/020_rls.sql). Worker routines are owned by migration_owner
-- (the table owner, so RLS does not apply to them) and take no user input.
ALTER TABLE report.report_job ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON report.report_job TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE support.ticket ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON support.ticket TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE support.feature_request ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON support.feature_request TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());
