#!/usr/bin/env bash
# Drift check: the schema built by Flyway migrations must equal the schema built from the
# canonical current-state files, applied in tools/canonical_order.txt order, then the repeatable
# objects (seed/ functions/ procedures/ views/ triggers/) in Flyway's order.
# Run after tools/run_pgtap.sh (which leaves a freshly migrated test database).
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/pg_env.sh

MIGRATED_DB="${TEST_DB}"
CANONICAL_DB="${TEST_DB}_canonical"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# -1: one transaction per file, like Flyway (R__ scripts use SET LOCAL ROLE). Flyway placeholders
# get dummy values: they only set role passwords and seed data, never the schema.
apply() {
  echo "   applying $1"
  sed -e 's/\${seed_sample_foods}/true/g' -e 's/\${[a-z_]*_password}/dummy/g' "$1" \
    | psql_mo "${CANONICAL_DB}" -1 > /dev/null
}

echo "==> Building ${CANONICAL_DB} from canonical files"
psql_su postgres -c "DROP DATABASE IF EXISTS \"${CANONICAL_DB}\" WITH (FORCE)"
psql_su postgres -c "CREATE DATABASE \"${CANONICAL_DB}\" OWNER migration_owner"
psql_su "${CANONICAL_DB}" -c "REVOKE CREATE ON SCHEMA public FROM PUBLIC"
# The migrated test DB has pgTAP (installed by run_pgtap.sh); mirror it so it is not reported as drift.
psql_su "${CANONICAL_DB}" -c "CREATE EXTENSION IF NOT EXISTS pgtap"

for file in $(grep -v -E '^\s*(#|\[|$)' tools/canonical_order.txt | tr -d '\r'); do apply "$file"; done
for f in $(ls seed/R__*.sql functions/R__*.sql procedures/R__*.sql views/R__*.sql triggers/R__*.sql 2> /dev/null \
  | awk -F'R__' '{print $2 "\t" $0}' | sort | cut -f2); do
  apply "$f"
done

dump() {
  PGPASSWORD="${POSTGRES_PASSWORD}" "$PG_DUMP" -U "${POSTGRES_USER:-postgres}" -d "$1" \
    --schema-only --no-owner --exclude-table=public.flyway_schema_history \
    | tr -d '\r' | grep -v -E '^(--|SET |SELECT pg_catalog.set_config|\\(un)?restrict )' | sed '/^$/d'
}

dump "${MIGRATED_DB}" > "$WORK/migrated.sql"
dump "${CANONICAL_DB}" > "$WORK/canonical.sql"

if diff -u "$WORK/migrated.sql" "$WORK/canonical.sql"; then
  echo "==> No drift: migrations and canonical DDL match ($(wc -l < "$WORK/migrated.sql") lines)."
else
  echo "==> DRIFT DETECTED: update the canonical files (or the migration) so they match." >&2
  exit 1
fi
