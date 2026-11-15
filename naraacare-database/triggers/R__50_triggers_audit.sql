-- Audit triggers on sensitive tables (doc 07 SEC-4.7): auth.user_account, app.user_profile,
-- billing.subscription, billing.entitlement_grant, privacy.*, nutrition.food_item and every ref.* table.
-- social.circle_member (Session 12). Primary-key columns are read from the catalog and
-- passed to audit.trg_fn_audit_row as trigger arguments (row_pk = values joined with ':').
-- Version: 2026.11.03-1 (bump to re-apply after adding tables to the list or to ref/privacy)
DO $triggers$
DECLARE
    t record;
BEGIN
    FOR t IN
        SELECT
            c.oid::regclass AS rel,
            (
                SELECT string_agg(quote_literal(a.attname), ', ' ORDER BY k.ord)
                FROM pg_constraint AS pk
                CROSS JOIN LATERAL unnest(pk.conkey) WITH ORDINALITY AS k (attnum, ord)
                INNER JOIN pg_attribute AS a ON a.attrelid = pk.conrelid AND a.attnum = k.attnum
                WHERE pk.conrelid = c.oid AND pk.contype = 'p'
            ) AS pk_args
        FROM pg_class AS c
        INNER JOIN pg_namespace AS n ON n.oid = c.relnamespace
        WHERE c.relkind IN ('r', 'p')
          AND NOT c.relispartition
          AND (
              n.nspname IN ('ref', 'privacy')
              OR (n.nspname, c.relname) IN (
                  ('auth', 'user_account'),
                  ('app', 'user_profile'),
                  ('billing', 'subscription'),
                  ('billing', 'entitlement_grant'),
                  ('social', 'circle_member'),
                  ('nutrition', 'food_item')
              )
          )
        ORDER BY 1::text
    LOOP
        EXECUTE format(
            'CREATE OR REPLACE TRIGGER trg_audit_row AFTER INSERT OR UPDATE OR DELETE ON %s '
            'FOR EACH ROW EXECUTE FUNCTION audit.trg_fn_audit_row(%s)',
            t.rel, t.pk_args
        );
    END LOOP;
END
$triggers$;
