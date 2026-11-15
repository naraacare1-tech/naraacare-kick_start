## What and why

<!-- Summary. Link the session file and open-question IDs, e.g. "Refs: S02, OQ-12". -->

## Checklist (tick, or write N/A with a reason)

- [ ] Linked session file + acceptance-criteria items this PR satisfies
- [ ] Tests added/updated (pgTAP; security payload tests when touching text columns or procedures)
- [ ] **Every new text column uses `common.safe_text` (or another approved domain) + a `char_length` CHECK; every text parameter is validated in the function/procedure**
- [ ] New text columns added to the payload test matrix
- [ ] No secrets, no real user data in seeds or tests
- [ ] Ownership/actor check in every function that takes `p_user_id`; RLS policy on new user-owned tables
- [ ] `SECURITY DEFINER` objects set `search_path = pg_catalog, pg_temp`; `EXECUTE` revoked from PUBLIC
- [ ] Migration is additive / backward-compatible with the running API (expand → migrate → contract)
- [ ] Every new index has `COMMENT ON INDEX … IS 'serves: …'`
- [ ] Canonical files (`schemas/ tables/ indexes/ roles/`) updated — drift check passes
- [ ] Docs updated (doc 05 / 06) if the contract changed
