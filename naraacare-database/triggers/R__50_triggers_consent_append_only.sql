-- privacy.consent_record is append-only (doc 07 SEC-7.1). The API role also lacks UPDATE/DELETE on it
-- (V014); this trigger additionally stops every other role except the owner's maintenance path.
CREATE OR REPLACE TRIGGER trg_append_only
BEFORE UPDATE OR DELETE ON privacy.consent_record
FOR EACH ROW EXECUTE FUNCTION privacy.trg_fn_append_only();
