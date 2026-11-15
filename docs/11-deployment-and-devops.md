# 11 — Deployment and DevOps

## 1. Environments

| Env | Where | Data | Purpose | Deploy trigger |
|---|---|---|---|---|
| `dev` | Developer laptop, **native installs, no containers**: PostgreSQL 18.6, Redis 8.8, Flyway CLI, the API and worker as local Python processes; files in `var/storage/`, email written to `var/outbox/` | synthetic | daily development | manual |
| `staging` | Hosting provider (chosen in S17), separate project/account, region in India | synthetic | integration, E2E, store sandbox, DAST, load tests | merge to `main` (auto) |
| `prod` | Same provider, separate project/account, region in India (backups copied to a second Indian region) | real | users | tag `v*` + manual approval |

**Hosting is vendor-neutral** (decision 2026-10-29, OQ-45): the docs and code name generic building blocks, and each one has a small interface in the backend with a local implementation. The provider is chosen at release time (S17) by checking it offers every block below in an Indian region; only the adapters for object storage (and, if wanted, a cloud key service behind the same key-unwrap interface) are then written. No containers are used anywhere: the API and workers are deployed as plain Python applications. Staging/prod are set up from versioned scripts or the provider's infrastructure-as-code tool, kept in the deploying repo; no click-ops.

## 2. Production topology (generic building blocks)

- Private network: the API, workers, database and Redis have no public addresses; only the load balancer is public.
- **API** (min 2 instances, autoscale on CPU 60 % / request rate) and **worker + scheduler** (min 1, autoscale on queue depth), run as an unprivileged user with `uv sync --frozen --no-dev` + uvicorn (`--no-server-header --no-access-log --proxy-headers`); a **PgBouncer** pool (2 instances) in front of the database.
- **Managed PostgreSQL 18**: high-availability standby in a second zone, 2 vCPU / 8 GB to start, storage autoscaling, TLS required (`sslmode=verify-full` with the provider's CA bundle), point-in-time recovery 35 days, deletion protection, storage encryption, 1 read replica.
- **Managed Redis 8** (1 replica, TLS + AUTH).
- **Private object storage**: `reports`, `exports`, `attachments` containers (no public access, encryption at rest, lifecycle rules, versioning on attachments); clients only get short-lived signed URLs from the API.
- **Load balancer** with a managed TLS certificate (TLS 1.2/1.3 only) and a **web application firewall** (managed common + known-bad-input rules, IP reputation, rate rule 2,000 req/5 min/IP).
- **Secret manager** holding every secret (doc 08), including the field-encryption master key (doc 07 §6.1); access limited to the API/worker identity and the deploy job.
- **Transactional email over SMTP** (any provider): domain verified, DKIM, SPF, DMARC `p=reject`.
- Egress: outbound allow-list (Google, Apple, Anthropic, FCM, Open Food Facts, the email and storage endpoints) enforced by firewall rules or a forward proxy (optional in MVP; recommended).
- Domain `naraacare.app` (DNS at the registrar or provider): `api.`, `mail.`, `naraacare.app/.well-known/assetlinks.json` and `apple-app-site-association` (static files behind a CDN) for deep links, plus the invite/referral landing page with store redirect.

Rough monthly cost at launch (estimate to confirm against the chosen provider's price list in S17): managed PostgreSQL with standby + replica ≈ $350–450; API/worker/PgBouncer compute ≈ $120–160; managed Redis ≈ $60–90; load balancer + firewall ≈ $40–60; storage, email, monitoring, secrets ≈ $40–60; **≈ $650–850/month** before Claude API usage (variable; capped by the Rin allowance) and Sentry.

## 3. CI/CD (GitHub Actions)

All CI jobs install what they need directly on the runner (PostgreSQL 18 from the official PGDG apt repository, Flyway CLI and pgTAP downloads verified by sha256, Python via uv); no container images are built or pulled.

### 3.1 `naraacare-database`
1. PR: sqlfluff → install PostgreSQL 18 + Flyway + pgTAP on the runner → `flyway migrate` from empty → pgTAP (`pg_prove`) → re-run is a no-op → drift check → routine catalogue fresh → payload tests → gitleaks.
2. Merge to main: `flyway migrate` on **staging** (the deploy job reads the `migration_owner` password from the secret manager) → pgTAP smoke against staging.
3. Tag: manual approval → `flyway info` + `flyway validate` → **pre-migration backup** of the prod database → `flyway migrate` → smoke. Migrations must be backward-compatible with the currently running API (expand/contract), so DB deploys go **before** API deploys.

### 3.2 `naraacare-backend`
1. PR: ruff, mypy, bandit, semgrep, pip-audit, gitleaks → unit → integration (PostgreSQL 18 installed on the runner and migrated from the database repo at a pinned tag; Redis replaced by fakeredis) → security tests → OpenAPI diff (`oasdiff`) → **start-up check** (runtime dependencies only, production uvicorn flags, `/health/live`).
2. Main: build a release artifact (source + `uv.lock`, tagged with the git SHA, checksum recorded) → deploy to staging instances (rolling, health checks on `/health/ready`) → smoke + ZAP baseline + Schemathesis (nightly) → k6 (weekly).
3. Tag: manual approval → **blue/green** (or canary: 10 % of traffic for 10 min watching 5xx/latency alerts → 100 %) using the provider's deployment tooling or a second instance group behind the load balancer → automatic rollback on alert.

### 3.3 `naraacare-mobile`
1. PR: `dart format --set-exit-if-changed`, `flutter analyze`, custom lints, `build_runner`, unit + widget + golden tests, OSV-Scanner, gitleaks.
2. Main: build `staging` flavor (Android AAB on ubuntu, iOS on macOS runner) → Firebase App Distribution / TestFlight internal → patrol E2E on a device farm (Firebase Test Lab for Android; iOS simulators on macOS) nightly.
3. Tag: `prod` flavor `--release --obfuscate --split-debug-info` → upload symbols to Sentry → Fastlane `supply` (Play internal track) and `pilot` (TestFlight) → manual promotion to production with staged rollout (Play 5 % → 20 % → 50 % → 100%; App Store phased release).
4. Store requirements are tracked in S17 (data safety form, privacy nutrition labels, account deletion URL, health-app declarations).

### 3.4 Shared
Dependabot weekly for all ecosystems in use (uv, pub, github-actions). Renovate optional. Required status checks per doc 10 §7.

## 4. Release process

1. Feature freeze → release branch not needed (trunk + tag).
2. DB migration tag → API tag → mobile release (the API stays compatible with the previous 2 app versions; `MIN_APP_VERSION_*` is used for forced updates only when necessary).
3. Release notes include migrations, new env vars (added to the secret manager **before** deploy), and feature-flag changes.

## 5. Backups and disaster recovery

| Item | Policy |
|---|---|
| PostgreSQL | provider-managed automated backups + PITR 35 days; daily backup copied to a second Indian region, encrypted with a separate key; monthly backup kept 12 months |
| Restore drill | **monthly**: restore the latest backup to an isolated instance, run `tools/verify_restore.sql` (row counts, latest timestamps, pgTAP smoke), record RTO/RPO in the runbook |
| Targets | RPO ≤ 5 min (PITR), RTO ≤ 2 h (zone or region failure: promote standby / restore) |
| Object storage | versioning on attachments; reports/exports are regenerable (no backup) |
| Secrets | secret manager replication, plus an encrypted offline copy of the field-encryption master key held by two named people (losing it makes encrypted fields unreadable) |
| Redis | cache/queue only; no backup needed (jobs are idempotent and rebuilt from DB) |
| Environment setup | scripts/IaC versioned; a second-region environment can be recreated in < 1 h |

## 6. Monitoring and alerting

| Signal | Tool | Alert |
|---|---|---|
| API 5xx rate, p95 latency per route | OpenTelemetry metrics + traces (OTLP to the chosen monitoring backend), load balancer metrics | 5xx > 1 % for 5 min; p95 > 2× SLO |
| Errors | Sentry (API + app) | new issue in prod; regression |
| DB CPU, connections, replica lag, deadlocks, long queries | provider database metrics + `pg_stat_statements` | CPU > 70 % 15 min; lag > 30 s; connections > 80 % |
| Partition coverage | worker job metric (`partitions_ahead`) | < 2 months ahead; any row in a DEFAULT partition |
| Queue depth / job failures | taskiq middleware metrics → OpenTelemetry | depth > 1,000; failure rate > 5 % |
| Security | `audit.security_event` aggregation, firewall metrics, provider audit log | refresh reuse spike, validation-reject spike, lockout spike, webhook rejects, admin console login |
| Billing | store notification processing lag; reconcile mismatches | lag > 15 min; mismatch > 0 |
| LLM | tokens/day, cost/day, error rate, refusal rate | daily cost > budget; error rate > 5 % |
| Mobile | Sentry crash-free sessions; Play vitals; App Store metrics | crash-free < 99.5 % |
| Synthetic | external uptime check: login + status every 5 min (test account) | 2 consecutive failures |

Dashboards: API overview, DB health, business KPIs (aggregated, no PII: DAU, logs/day, conversions), security.
On-call: PagerDuty/Opsgenie rotation (or email/SMS initially), runbooks in `naraacare-backend/runbooks/` (added in S16: DB failover, restore, key rotation, store webhook backlog, LLM outage → `RIN_ENABLED=false`, **personal data breach response** with the DPDP notification timeline and a contact list).

## 7. Operational jobs (taskiq worker + taskiq scheduler)

| Job | Schedule (IST) | Purpose |
|---|---|---|
| `ensure_partitions` | daily 02:00 | create next 3 monthly partitions |
| `apply_retention` | daily 03:00 | purge/drop per retention policy |
| `send_reminders` | every minute | due hydration/nutrition/sleep/check-in reminders (FCM) |
| `day_ending_soon` | every 15 min | nudge users within 3 h of bedtime below goal (respects prefs) |
| `streak_rollover` | hourly (per timezone midnight) | compute streak breaks, milestone notifications |
| `referral_tally` | daily 04:00 | active days, qualification, rewards |
| `subscription_reconcile` | every 6 h | re-verify subscriptions near expiry or in grace |
| `process_deletions` | hourly | complete deletions past grace |
| `generate_reports` / `generate_exports` | on demand (queue) | PDFs / ZIPs to object storage |
| `verify_daily_summaries` | daily 05:00 | recompute a sample, alert on drift |
| `rotate_dek` | quarterly | new data key; lazy re-encrypt |
