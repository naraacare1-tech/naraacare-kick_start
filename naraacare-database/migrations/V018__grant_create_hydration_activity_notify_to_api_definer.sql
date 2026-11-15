-- V018__grant_create_hydration_activity_notify_to_api_definer: Session 09 creates the hydration,
-- workout and notification API routines as api_definer (SET LOCAL ROLE api_definer in each R__
-- script, doc 05 section 7), which needs CREATE on those schemas. api_definer cannot log in and
-- runs only our function bodies (no dynamic SQL).
GRANT CREATE ON SCHEMA hydration, activity, notify TO api_definer;
