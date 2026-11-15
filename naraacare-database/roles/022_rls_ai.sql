-- Row-level security for the ai schema (Session 13): every row belongs to one user and only that
-- user (app.user_id of the transaction) can see or change it, as for the other personal tables
-- (roles/020_rls.sql). Rin never reads another user's data (OQ-37).
ALTER TABLE ai.conversation ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON ai.conversation TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE ai.message ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON ai.message TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE ai.memory_summary ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON ai.memory_summary TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE ai.pending_action ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON ai.pending_action TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE ai.usage_event ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON ai.usage_event TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());
