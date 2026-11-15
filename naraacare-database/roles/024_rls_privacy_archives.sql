-- Erasure archives (Session 15): RLS on with no policy, so no API role can read or write them; only the
-- ops erasure and retention routines (owned by migration_owner, the table owner) touch them.
ALTER TABLE privacy.consent_archive ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.transaction_archive ENABLE ROW LEVEL SECURITY;
ALTER TABLE privacy.deletion_log ENABLE ROW LEVEL SECURITY;
