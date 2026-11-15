-- Row-Level Security on user-owned tables (doc 05 section 7, doc 07 SEC-4.4).
-- Policies apply to api_definer, which owns every API function, so a function that forgets
-- its WHERE user_id = ... still cannot read or write another user's rows.
-- RLS is ENABLED, not FORCED: the table owner (migration_owner) is exempt so that maintenance
-- procedures it owns (partitions, retention, account deletion) can work across users.

ALTER TABLE app.user_profile ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON app.user_profile TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE app.health_target_snapshot ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON app.health_target_snapshot TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE app.user_activity_day ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON app.user_activity_day TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE app.user_streak ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON app.user_streak TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE nutrition.meal ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON nutrition.meal TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE nutrition.meal_item ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON nutrition.meal_item TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE nutrition.daily_summary ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON nutrition.daily_summary TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE nutrition.saved_meal ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON nutrition.saved_meal TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE nutrition.saved_meal_item ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON nutrition.saved_meal_item TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE activity.workout ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON activity.workout TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE hydration.intake ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON hydration.intake TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE hydration.custom_drink ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON hydration.custom_drink TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE hydration.temperature_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON hydration.temperature_log TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE hydration.daily_summary ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON hydration.daily_summary TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE sleep.entry ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON sleep.entry TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE sleep.night_waking ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON sleep.night_waking TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE sleep.daily_summary ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON sleep.daily_summary TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE notify.device ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON notify.device TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE notify.notification_preference ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON notify.notification_preference TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE notify.reminder ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON notify.reminder TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE notify.notification ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON notify.notification TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE privacy.export_request ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON privacy.export_request TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE privacy.deletion_request ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON privacy.deletion_request TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());
