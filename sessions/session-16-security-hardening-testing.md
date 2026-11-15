# Session 16 — Security Hardening and Testing (incl. full XSS/Script Payload Suite)

## Goal and scope
Run a full security pass across the three projects: complete and enforce the payload suite on every field, IDOR/authz matrix, auth attacks, rate limits, webhook forgery, upload attacks, prompt injection, mobile MASVS checks, DAST, dependency/secret/SAST gates, hosting hardening (firewall, egress, secret-manager access, least-privilege identities), optional device attestation, and an external penetration test readiness pack.

**In:** tests and fixes in all repos; hosting hardening checklist (provider-neutral); security runbooks.
**Out:** new features.

## Prerequisites
S01–S15 complete (feature-complete beta). OQ-49, OQ-50 decided.

## Files to create / modify
```
naraacare-backend/tests/security/
  test_payload_sweep.py            # ALL routes × ALL string fields (body/query/path/header) × ALL payloads → 422; log assertion
  test_authz_matrix.py             # generated: every route × roles (anon, user A, user B, nutritionist, support, admin) × tiers → expected status table (yaml)
  test_idor_all_ids.py             # every {id} route with another user's ids → 404
  test_jwt_attacks.py              # alg none, kid confusion, HS/EdDSA confusion, expired, wrong aud/iss, replay after logout
  test_rate_limits.py test_lockout.py test_enumeration.py
  test_webhooks_forgery.py test_receipt_reuse.py
  test_uploads.py test_sse_ws_limits.py test_mass_assignment.py
  payloads/xss.txt (v1.x final) payloads/sqli.txt payloads/path_traversal.txt payloads/csv_injection.txt payloads/prompt_injection.yaml
naraacare-backend/semgrep/rules.yml   # final rule set; CI fails on any finding
naraacare-database/tests/950_security_payloads_all_columns.sql   # catalog-driven: every safe_text column via its procedure
naraacare-database/tests/960_privileges_audit.sql               # role/privilege snapshot vs expected
naraacare-mobile/test/security/{all_forms_payload_test.dart, no_raw_textfield_test.dart, no_webview_test.dart, release_config_test.dart}
naraacare-mobile/tool/masvs_checklist.md   # evidence per control
naraacare-backend/docs/hosting_hardening.md   # firewall rules, egress allow-list, provider audit log + threat alerts, least-privilege identities, secret-manager access policy
naraacare-backend/runbooks/{incident_response.md, data_breach_dpdp.md, key_rotation.md, token_revocation.md}
docs/pentest-scope.md (in docs repo)
```

## Step-by-step tasks
1. Freeze payload list v1.x (≥ 300 vectors incl. encoded/obfuscated variants) and sync to all repos; CI parity check.
2. Payload sweep: auto-discover string inputs from OpenAPI (including headers used as data and path params) → assert 422, no payload in logs/DB/Sentry breadcrumbs. Same for WS frames and SSE inputs.
3. Authz matrix YAML reviewed by product (who can do what); generated tests; fix any deviation.
4. Auth attacks and lockout/enumeration behaviour per OQ-26 decision.
5. Uploads, CSV/PDF output encoding, email templates (autoescape), push texts.
6. Prompt injection red-team set run against Rin (staging); fix guardrails/prompt; record results.
7. Mobile: MobSF scan of release builds; verify obfuscation, pinning (mitmproxy), cleartext blocked, `allowBackup=false`, no secrets (`strings`), FLAG_SECURE scope, root warning, deep-link fuzzing, local DB encrypted, logs silent in release.
8. Optional (OQ-49): Play Integrity API + App Attest verification on sign-up, purchase verify and referral attribution (server-side), soft-fail mode first.
9. DAST: ZAP full scan + Schemathesis on staging; fix findings.
10. Hosting (checklist applied to the chosen provider in S17): firewall rules tuned (rate-based, managed rules), egress allow-list, network rules least privilege, database not public, object storage with no public access, secret-manager access limited to the API/worker identity and the deploy job (separation of duties for the master key), provider audit log + threat-detection alerts, no unused identities or keys.
11. Secrets rotation drill (JWT key rotation with `kid` overlap; DB password rotation; DEK rotation).
12. Incident and DPDP breach runbooks; tabletop exercise.
13. Pen-test pack: scope, test accounts (STANDARD/STAR/staff), environments, rules of engagement; schedule an external pen test before launch.

## DB objects
No new business objects; test files and possibly constraint fixes.

## API endpoints
None new (fixes only).

## Screens
None new (fixes only).

## Security checks
All of doc 07 (SEC-1 … SEC-8), OWASP API Top 10 mapping, MASVS evidence, STRIDE T1–T27 each with at least one automated test or documented control evidence.

## Input-validation checklist (final audit)
- [ ] Inventory generated from code: every Flutter `NcTextField` (validator + maxLength), every API string input (Safe* type), every DB text column (`common.safe_text` + length) — exported as `security/input-inventory.csv` and reviewed; zero gaps.
- [ ] Every inventory row is covered by the payload tests in its layer.
- [ ] No rich-text or HTML rendering anywhere (no WebView test, no `flutter_html`/markdown packages in pubspec).

## Tests to write
Listed above; all run in CI (fast subset per PR, full sweep nightly).

## Acceptance criteria / Definition of done
- [ ] Zero high/critical findings in SAST, dependency scans, DAST, MobSF.
- [ ] Payload sweep 100 % pass across all three layers; input inventory has no gaps.
- [ ] Authz matrix tests pass; IDOR suite pass.
- [ ] Mobile MASVS checklist complete with evidence.
- [ ] Hosting hardening checklist complete (no public resources except the load balancer and the static deep-link files).
- [ ] Runbooks reviewed; rotation drill done; external pen test scheduled (or completed with fixes).

## Estimated effort
8–10 developer-days (shared across team) + external pen test.
