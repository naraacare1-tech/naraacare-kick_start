## What and why

<!-- Summary. Link the session file and open-question IDs, e.g. "Refs: S05, OQ-26". -->

## Checklist (tick, or write N/A with a reason)

- [ ] Linked session file + acceptance-criteria items this PR satisfies
- [ ] Tests added/updated (unit + integration; security tests when touching inputs/auth)
- [ ] **Every new string field uses a `Safe*` type** (no bare `str` in `app/schemas/` — Semgrep enforces) with a max length; the DB column uses `common.safe_text`; the app field uses `InputValidators` + `maxLength`
- [ ] New text fields are covered by the payload sweep (auto-discovered from OpenAPI from S04)
- [ ] No secrets, no PII in logs, no health values in analytics/crash reports
- [ ] Object-level authorisation: user comes from the token; ownership checked in the DB function
- [ ] STAR-only behaviour enforced server-side
- [ ] Repositories call only stored functions/procedures with bound parameters
- [ ] OpenAPI updated; error codes from the catalogue; pagination limits on list endpoints
- [ ] New env vars added to `.env.example`, `Settings`, README table and doc 08
- [ ] Docs updated (04/06) if contracts or rules changed; OQ decisions referenced
