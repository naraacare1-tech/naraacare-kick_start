# 10 — Testing Strategy

## 1. Test pyramid and targets

| Level | Project | Tooling | Coverage target | Runs |
|---|---|---|---|---|
| DB unit | database | pgTAP 1.3.4 + `pg_prove` on PG 18.6 container | every function/procedure, every CHECK, RLS policy, grant | every PR |
| Backend unit | backend | pytest 9.1, hypothesis (property tests for calculators) | ≥ 90 % lines on `domain/`, ≥ 80 % overall | every PR |
| Backend integration | backend | pytest + a natively installed PostgreSQL 18 with migrations applied (`NARAACARE_TEST_DATABASE_URL`) + fakeredis + httpx `AsyncClient` | every endpoint happy path + main errors | every PR |
| Contract | backend ↔ mobile | OpenAPI snapshot (`openapi.json` committed); `oasdiff` breaking-change check; mobile DTO tests against example payloads | 100 % of endpoints | every PR |
| Mobile unit | mobile | `flutter_test`, mocktail | ≥ 80 % on domain + data | every PR |
| Mobile widget | mobile | `flutter_test`, golden tests for key screens (iPhone 390×844, Android 412×917) | every screen in doc 02 | every PR |
| Mobile integration/E2E | mobile | `integration_test` + patrol 4.10 (native dialogs: permissions, store sheets) against the staging API | critical journeys (§3) | nightly + release |
| Security | all | see §4 | — | every PR + nightly DAST |
| Performance | backend/DB | k6 (load), `EXPLAIN (ANALYZE, BUFFERS)` plan tests, Flutter DevTools frame timing | §5 SLOs | weekly + pre-release |

## 2. Calculation tests (doc 06 is the oracle)

Every example in doc 06 becomes a fixed test case (`tests/unit/domain/*/test_examples.py`):
- Nutrition Example 1 (male, 2214 kcal, 304/62/111 g, 50 % energized) and Example 2 (female, floor 1200, override, 165/33/60 g, 103.6 % goal_met).
- Apple 150 g → 78 kcal / 21 g / 6.9 mg; dal portions (tbsp 0.15 … bowl 3.0).
- Hydration Kompal: LBW 46.05, TWT 3592, need 3053, rates 29.79 / 175.93, timeline levels 81.7 / 74.9 / 82.6 / 55.5 / 70.9, left to drink 2753, 22 °C → 2880, 35 °C → 3844.
- Sahil: need 5047, workout drop 62.5 %.
- Sleep: 450 min / 94 %; 7h45 → 97 %; one waking → 420 min / 88 %.
- Boundary tables: BMI 18.49/18.5/24.99/25.0; avatar fill 0/0.1/49.9/50/99.9/100/105/105.1; hydration bands 19.9/20/49.9/50/79.9/80; need clamps 1499→1500, 6001→6000; temperature 14.9 rejected, 15 and 40 accepted, 40.1 rejected.
- Property tests (hypothesis): level ∈ [0,100]; need ∈ [1500,6000]; more temperature → need non-decreasing; macro kcal sum ≈ base target (±10 kcal rounding).
- Version tests: changing a `ref.calc_constant` in a new `calc_version` does not change a stored past snapshot.

## 3. Critical E2E journeys

1. Sign up → OTP (wrong code, resend, correct) → onboarding 1–6 (unit toggles, back) → result → save → Home shows 3 avatars.
2. Quit at onboarding step 4 → relaunch → resumes at step 4.
3. Sign in, forgot password → OTP → reset → old sessions logged out.
4. Log water by swipe (+/−) and sheet; edit last entry; 3rd-last entry not editable.
5. Log meal by search (katori), see Today's Nutrition (6 nutrients + upsell); hit 4/day limit.
6. Offline: airplane mode → log 3 water + 1 meal → relaunch → online → synced once (no duplicates).
7. Upgrade to STAR in store sandbox → entitlement refresh → 17 nutrients, sleep, Rin unlocked → cancel → access until period end (sandbox accelerated time).
8. Create circle, invite by username, accept on second device, chat with @mention, share/unshare avatars, leave.
9. Rin: ask "I ate 2 roti and dal" → action card → Add to Avatar → meal appears.
10. Report: monthly report generates and downloads; custom report blocked on STANDARD.
11. Delete account → grace → cancel by sign-in; complete deletion (time-travelled in staging) → cannot sign in.

## 4. Security testing

| Area | Test | Where |
|---|---|---|
| XSS/script payload sweep | every payload × every string field × every endpoint → 422; payload never logged | `backend/tests/security/test_payload_sweep.py` (fields auto-discovered from OpenAPI) |
| Flutter validators | each `NcTextField` validator rejects every payload; `maxLength` set; lint test: no raw `TextField` | `mobile/test/security/` |
| DB CHECK constraints | every payload via procedures into every `safe_text` column → exception | `database/tests/security_payloads.sql` |
| Payload list parity | the 3 repos' `xss.txt` share the same `payload-list-version` header | CI step in each repo |
| Auth bypass | missing/expired/tampered JWT (alg `none`, wrong `kid`, wrong `aud`, HS256 with public key) → 401 | backend security tests |
| Token reuse | refresh twice → second fails, whole family revoked | backend |
| IDOR/BOLA | user B requests user A's meal/intake/sleep/circle/report/export/conversation by ID → 404; generated across all `{id}` routes | backend |
| Mass assignment | extra fields (`role`, `tier`, `user_id`) → 422 | backend |
| Tier bypass | STANDARD calls every STAR endpoint → 403 `UPGRADE_REQUIRED`; daily-summary returns 6 nutrients only | backend |
| Rate limits | login, OTP, signup, chat, search exceed limits → 429 + `Retry-After` | backend |
| Lockout | 5 bad passwords → 423; backoff schedule | backend |
| Webhook forgery | unsigned/invalid-signature RTDN/ASSN → 401, nothing changes; replayed notification id → no-op | backend |
| Receipt reuse | same purchase token on a second account → rejected | backend |
| Upload | non-image, polyglot, 11 MB, decompression bomb, `../` filename → rejected | backend |
| RLS | connecting as `app_rw` and selecting a table directly → permission denied; function with mismatched `app.user_id` → exception | pgTAP |
| SQL injection | Semgrep rule + payload sweep includes SQLi strings; DB functions tested with quotes/semicolons | CI |
| Secrets | gitleaks on PR + full history weekly | CI |
| Dependencies | pip-audit, OSV-Scanner — fail on high/critical | CI |
| DAST | OWASP ZAP baseline + Schemathesis (`--checks all`) against staging | nightly |
| Mobile | MobSF static scan of release APK/IPA; verify cleartext blocked, pinning active (mitmproxy test fails to intercept), no secrets in binary (`strings` scan), backups disabled | pre-release |
| Prompt injection | Rin red-team set (ignore instructions, exfiltrate other users, HTML output, tool abuse) → safe outputs, no cross-user data | S13 + nightly eval |

## 5. Performance

| SLO (p95, staging at production-like size) | Target |
|---|---|
| `GET /hydration/status`, `GET /nutrition/daily-summary` | ≤ 150 ms |
| `POST /hydration/intakes`, `POST /meals` | ≤ 250 ms |
| `GET /foods/search` | ≤ 200 ms |
| Chat message fan-out (send → other member WS) | ≤ 500 ms |
| Rin first token | ≤ 3 s |
| Report generation (monthly) | ≤ 30 s |
| App cold start (mid-range Android, e.g. 4 GB RAM) | ≤ 2.5 s to Home |
| Scroll / animations | 60 fps, no jank frames > 16 ms in avatar carousel |

k6 scenario: 2,000 virtual users, mix 50 % status reads, 25 % water logs, 10 % meals, 10 % search, 5 % chat, for 30 min. The DB is seeded with 100k users × 90 days of data (synthetic generator `tools/seed_synthetic.py`, no real data). Pass criteria: SLOs met, error rate < 0.1 %, DB CPU < 60 %, no lock waits > 100 ms.
Plan tests: the key functions are asserted to use the intended index (`EXPLAIN (FORMAT JSON)` contains `Index Only Scan` / partition pruning to 1–2 partitions).

## 6. Test data and environments

- Never use production data in non-prod. Synthetic data generators per schema.
- Store sandboxes: Google Play license testers + App Store sandbox accounts (documented in a password manager, not in repos).
- Anthropic: a separate staging workspace with low spend limits; the CI uses recorded responses (VCR-style cassettes, scrubbed) for unit/integration; live calls only in the nightly eval.

## 7. Quality gates (CI must pass to merge)

Lint/format · type check · unit · integration · contract (no breaking change without version bump) · security tests · Semgrep/Bandit · gitleaks · dependency audit · coverage thresholds · migration drift check (database) · golden tests (mobile).
