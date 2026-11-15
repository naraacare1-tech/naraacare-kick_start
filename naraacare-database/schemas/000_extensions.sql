-- Canonical current-state DDL: extensions.
-- Must stay equivalent to migrations/V001__extensions.sql (enforced by tools/drift_check.sh).

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS citext;
