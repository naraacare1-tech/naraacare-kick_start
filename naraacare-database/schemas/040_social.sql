-- Social schema (Session 12, doc 05 section 5.6): connections, blocks, Care Circles, chat, feed.
-- Same privilege model as the other schemas (roles/010_roles.sql): app roles may resolve names but
-- get no table privileges; api_definer owns the API routines and gets DML on new tables.
-- Data is stored in plain text (doc 07 section 6.1); only invite-link tokens are hashed (bearer
-- secrets, like refresh tokens).
CREATE SCHEMA IF NOT EXISTS social;
COMMENT ON SCHEMA social IS 'Connections, blocks, Care Circles, chat and the activity feed';

GRANT USAGE ON SCHEMA social TO api_definer, app_rw, app_worker, app_readonly;
GRANT CREATE ON SCHEMA social TO api_definer;

ALTER DEFAULT PRIVILEGES FOR ROLE migration_owner IN SCHEMA social
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO api_definer;
ALTER DEFAULT PRIVILEGES FOR ROLE migration_owner IN SCHEMA social
GRANT USAGE, SELECT ON SEQUENCES TO api_definer;
