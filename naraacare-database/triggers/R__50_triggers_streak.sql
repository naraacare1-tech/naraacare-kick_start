-- Streak refresh (Session 14): a new active day (any tracking procedure writes app.user_activity_day)
-- recomputes app.user_streak and may write a milestone notification (procedures/R__31_app.pr_recompute_streak.sql).
-- Updates of an existing day (another tracker on the same day) cannot change the streak.
DROP TRIGGER IF EXISTS trg_user_activity_day__streak ON app.user_activity_day;
CREATE TRIGGER trg_user_activity_day__streak
AFTER INSERT ON app.user_activity_day
FOR EACH ROW EXECUTE FUNCTION app.trg_fn_activity_day_streak();
