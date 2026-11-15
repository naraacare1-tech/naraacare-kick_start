-- AI schema (Session 13, doc 05 section 5.7): Rin AI conversations, messages, memory, proposed
-- logs (pending actions) and token usage. Same privilege model as the other schemas
-- (roles/010_roles.sql): app roles may resolve names only; api_definer owns the API routines.
-- Plain text (doc 07 section 6.1); every text column is common.safe_text (no markup). Model output
-- is sanitised to plain text by the API before it is stored.
CREATE SCHEMA IF NOT EXISTS ai;
COMMENT ON SCHEMA ai IS 'Rin AI: conversations, messages, memory, pending actions, token usage';

GRANT USAGE ON SCHEMA ai TO api_definer, app_rw, app_worker, app_readonly;
GRANT CREATE ON SCHEMA ai TO api_definer;

ALTER DEFAULT PRIVILEGES FOR ROLE migration_owner IN SCHEMA ai
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO api_definer;
ALTER DEFAULT PRIVILEGES FOR ROLE migration_owner IN SCHEMA ai
GRANT USAGE, SELECT ON SEQUENCES TO api_definer;
