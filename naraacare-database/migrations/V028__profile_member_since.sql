-- V028 (hand-written, 2026-11-07): GET /me returns the account's sign-up date in the user's own
-- timezone (member_since), so the monthly report picker starts at the month the account was created
-- (owner); report.pr_create_report_job refuses earlier months. A new result column cannot be added
-- in place, so the repeatable script recreates the function.
DROP FUNCTION app.fn_get_profile(uuid);
