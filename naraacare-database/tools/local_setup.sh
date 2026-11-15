#!/usr/bin/env bash
# First-time local setup on a native PostgreSQL 18.6 (no containers): creates the dev database,
# runs bootstrap/bootstrap.sql (migration_owner) and applies all migrations. Safe to re-run.
# Usage: tools/local_setup.sh            (requires .env; see README "Prerequisites")
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/pg_env.sh

DB="${PGDATABASE:-naraacare}"
if [[ -z "$(psql_su postgres -At -c "SELECT 1 FROM pg_database WHERE datname = '${DB}'")" ]]; then
  echo "==> Creating ${DB}"
  psql_su postgres -c "CREATE DATABASE \"${DB}\""
fi
echo "==> Bootstrap (migration_owner)"
psql_su "${DB}" -v mo_pw="${FLYWAY_PASSWORD}" -f bootstrap/bootstrap.sql
echo "==> Flyway migrate ${DB}"
flyway_on "${DB}" migrate
