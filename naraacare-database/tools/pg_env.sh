#!/usr/bin/env bash
# Shared settings for the local/CI tools (sourced, not run). Everything runs natively: psql,
# pg_dump, flyway and (optionally) pg_prove must be on PATH, or set PSQL / PG_DUMP / FLYWAY.
set -a; source .env; set +a
TEST_DB="${PGTAP_DATABASE:-naraacare_test}"
PSQL="${PSQL:-psql}"
PG_DUMP="${PG_DUMP:-pg_dump}"
FLYWAY="${FLYWAY:-flyway}"
export PGHOST PGPORT

# Superuser (local/CI only): creates databases and installs pgTAP.
psql_su() {
  PGPASSWORD="${POSTGRES_PASSWORD}" "$PSQL" -X -q -v ON_ERROR_STOP=1 \
    -U "${POSTGRES_USER:-postgres}" -d "$1" "${@:2}"
}
# migration_owner: everything the migrations would do.
psql_mo() {
  PGPASSWORD="${FLYWAY_PASSWORD}" "$PSQL" -X -q -v ON_ERROR_STOP=1 -U "${FLYWAY_USER}" -d "$1" "${@:2}"
}
# Flyway reads the other FLYWAY_* settings from the environment (.env).
flyway_on() {
  "$FLYWAY" -url="jdbc:postgresql://${PGHOST}:${PGPORT}/$1?sslmode=disable" "${@:2}"
}
