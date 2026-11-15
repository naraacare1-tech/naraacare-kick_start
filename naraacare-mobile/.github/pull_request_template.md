## What and why

<!-- Summary. Link the session file and open-question IDs, e.g. "Refs: S07, OQ-26". -->

## Checklist (tick, or write N/A with a reason)

- [ ] Linked session file + acceptance-criteria items this PR satisfies
- [ ] Tests added/updated (unit + widget; golden tests for UI; payload widget tests for every new text field)
- [ ] **Only `NcTextField` for text input**, with a validator from `InputValidators` and a `maxLength`; numeric fields use input formatters; rejected input is never echoed
- [ ] The matching backend field uses a `Safe*` type (link the backend PR)
- [ ] User and AI text rendered with `Text` only (no WebView / HTML / markdown widgets)
- [ ] No hard-coded colours/sizes (design tokens only); no user-facing strings outside ARB files
- [ ] No secrets in code or `env/*`; tokens only in secure storage; no PII/health values in logs or crash reports
- [ ] No business calculation in the app (server returns goals, levels, states)
- [ ] STAR-only UI handles `403 UPGRADE_REQUIRED` from the server (UI hiding is cosmetic)
- [ ] Screenshots for iOS (390×844) and Android (412×917)
- [ ] Docs updated (02 screen inventory) if screens or fields changed
