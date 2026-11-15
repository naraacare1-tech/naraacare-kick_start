#!/usr/bin/env bash
# Rebuilds the pgTAP test database from scratch, applies all Flyway migrations, and runs pgTAP.
# Usage: tools/run_pgtap.sh   (requires .env, a running local PostgreSQL 18.6 with pgTAP installed
#                              by tools/install_pgtap.sh, and flyway on PATH; see README)
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/pg_env.sh

echo "==> Recreating ${TEST_DB}"
psql_su postgres -c "DROP DATABASE IF EXISTS \"${TEST_DB}\" WITH (FORCE)"
psql_su postgres -c "CREATE DATABASE \"${TEST_DB}\" OWNER migration_owner"
psql_su postgres -c "REVOKE ALL ON DATABASE \"${TEST_DB}\" FROM PUBLIC"
psql_su "${TEST_DB}" -c "REVOKE CREATE ON SCHEMA public FROM PUBLIC"

echo "==> Migrating ${TEST_DB}"
flyway_on "${TEST_DB}" migrate

echo "==> Installing pgTAP (test database only)"
psql_su "${TEST_DB}" -c "CREATE EXTENSION IF NOT EXISTS pgtap"

echo "==> Running pgTAP"
if command -v pg_prove >/dev/null 2>&1; then
  PGPASSWORD="${POSTGRES_PASSWORD}" pg_prove -U "${POSTGRES_USER:-postgres}" -d "${TEST_DB}" \
    --ext .sql -r tests
  exit
fi
# Without pg_prove (e.g. Windows): run each file with psql and read the TAP output.
fail=0
for t in tests/*.sql; do
  rc=0
  out="$(PGPASSWORD="${POSTGRES_PASSWORD}" "$PSQL" -X -q -At -v ON_ERROR_STOP=1 \
    -U "${POSTGRES_USER:-postgres}" -d "${TEST_DB}" -f "$t" 2>&1)" || rc=$?
  out="$(tr -d '\r' <<<"$out")"
  oks=$(grep -c '^ok ' <<<"$out" || true)
  if [[ $rc -ne 0 ]] || grep -qE '^not ok|ERROR|Looks like' <<<"$out"; then
    fail=1
    echo "FAIL $t ($oks ok)"
    grep -E -A6 '^not ok|ERROR|Looks like' <<<"$out" | head -60
  else
    echo "ok   $t ($oks assertions)"
  fi
done
exit $fail
