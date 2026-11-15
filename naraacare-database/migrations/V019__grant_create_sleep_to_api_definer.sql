-- V019__grant_create_sleep_to_api_definer: Session 10 creates the sleep API routines as api_definer
-- (SET LOCAL ROLE api_definer in each R__ script, doc 05 section 7), which needs CREATE on the schema.
-- api_definer cannot log in and runs only our function bodies (no dynamic SQL).
GRANT CREATE ON SCHEMA sleep TO api_definer;
