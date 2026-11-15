# Session 01 — Foundations: Repos, Folder Structure, Tooling, CI, Env

## Goal and scope
Create the three independent repositories with the folder layouts from doc 03, pinned toolchains, linting, pre-commit hooks, CI pipelines, `.env.example` files and a working local environment from native installs (no containers). No features.

**In:** repo creation, skeletons, tooling, CI, local setup scripts for native PostgreSQL/Redis, gitleaks, Dependabot, PR template, CODEOWNERS. Hosting is vendor-neutral and set up in S17 (OQ-45).
**Out:** any table, endpoint or screen (from S02 onward).

## Prerequisites
- Decisions recorded or accepted as defaults: OQ-45 (vendor-neutral hosting in an Indian region, no Docker, no AWS; provider chosen in S17), OQ-46 (Sentry).
- GitHub org `naraacare1-tech` admin access; Apple Developer + Google Play Console accounts (needed by S07/S11, start enrolment now — Apple can take days).

## Files to create

### naraacare-database
```
README.md  .env.example  .gitignore  .sqlfluff  .pre-commit-config.yaml  .gitleaks.toml
bootstrap/bootstrap.sql   # creates migration_owner on any environment (idempotent)
flyway.conf.example
schemas/ tables/ indexes/ functions/ procedures/ views/ triggers/ seed/ roles/ migrations/ tests/ tools/
migrations/V001__extensions.sql            # pgcrypto, pg_trgm, btree_gist, unaccent, citext (only)
tests/000_smoke.sql                          # pgTAP: extensions present
tests/payloads/xss.txt                       # copy of canonical list (header payload-list-version: 1.0.0)
tools/local_setup.sh  tools/install_pgtap.sh  tools/run_pgtap.sh  tools/drift_check.sh   # native PostgreSQL 18.6 + Flyway CLI
.github/workflows/ci.yml  .github/dependabot.yml  .github/pull_request_template.md  CODEOWNERS
```

### naraacare-backend
```
README.md  .env.example  .gitignore  .pre-commit-config.yaml  .gitleaks.toml  pyproject.toml  uv.lock
app/__init__.py app/main.py (app factory + /health/live only)
app/api/v1/routers/health.py
app/core/ app/core/security/ app/domain/ app/repositories/ app/schemas/ app/middleware/ app/integrations/ app/workers/
tests/unit/test_health.py tests/integration/ tests/security/payloads/xss.txt tests/contract/
semgrep/rules.yml  # no-bare-str-in-schemas, no-sql-string-building, no-print
.github/workflows/ci.yml  .github/dependabot.yml  .github/pull_request_template.md  CODEOWNERS
```
`pyproject.toml` pins exact versions from doc 03 §2 (dependency manager: **uv**, lockfile committed).

### naraacare-mobile
```
README.md  .env.example  .gitignore  .pre-commit-config.yaml  analysis_options.yaml  pubspec.yaml (exact pins)
env/dev.env.example
lib/main_dev.dart lib/main_staging.dart lib/main_prod.dart lib/app.dart
lib/core/{config,theme,routing,network,errors,security,storage,sync,l10n,utils}/   (empty placeholders + README)
lib/features/  lib/shared/
android/ (productFlavors dev/staging/prod, applicationIdSuffix, network_security_config.xml cleartext off)
ios/ (schemes + xcconfigs Dev/Staging/Prod, bundle IDs, ATS default)
test/  integration_test/  test/security/payloads/xss.txt
.github/workflows/ci.yml  .github/dependabot.yml  .github/pull_request_template.md  CODEOWNERS
```

## Step-by-step tasks
1. Create repos with branch protection (doc 09 §1), CODEOWNERS, PR template (doc 09 §3), Dependabot.
2. Add pre-commit: gitleaks 8.30.1, end-of-file/trailing whitespace, ruff (backend), `dart format` (mobile), sqlfluff (database).
3. Database: native PG 18.6 (`shared_preload_libraries` none), Flyway CLI (pin the exact version, record it in README), `V001__extensions.sql`, pgTAP install script, `run_pgtap.sh`, CI job installing PostgreSQL/Flyway/pgTAP on the runner (migrate from empty → pgTAP → sqlfluff → gitleaks).
4. Backend: `uv init`, pin deps, `Settings` skeleton with fail-fast (doc 08 §6) for the keys used so far, `/health/live`, CI (ruff, mypy --strict, bandit, semgrep, pip-audit, pytest, gitleaks, start-up check of the plain Python app with production flags).
5. Mobile: `flutter create --org com.naraacare --platforms=android,ios`, flavors (Gradle `productFlavors` + iOS schemes/xcconfig), `main_<flavor>.dart` reading `String.fromEnvironment` keys, assert `API_BASE_URL` starts with `https://` except dev localhost, `very_good_analysis`, CI (format, analyze, test, build dev APK).
6. Verify `flutter run --flavor dev -t lib/main_dev.dart --dart-define-from-file=env/dev.env` works with `.env` format; if not, switch to JSON and update doc 08.
7. Write each README env-var table from doc 08.
8. Canonical payload list `xss.txt` v1.0.0 (doc 07 §4.7) committed to all three repos; CI step verifies the version header matches `1.0.0`.

## DB objects
`V001__extensions.sql` only.

## API endpoints
`GET /health/live`.

## Screens
Blank app shell per flavor showing an environment ribbon (non-prod).

## Security checks
SEC-8.1 (gitleaks pre-commit + CI), SEC-8.2 (Dependabot, pip-audit, OSV), SEC-8.3 (Bandit, Semgrep incl. custom rules), SEC-8.4, SEC-8.6 (unprivileged runtime, no dev tools installed), SEC-5.2 (cleartext off from day one), SEC-5.7 (no secrets in mobile env), `.gitignore` covers secrets.

## Input-validation checklist
- [ ] Semgrep rule `no-bare-str-in-schemas` exists and fails on a sample bad schema (test fixture).
- [ ] Payload list v1.0.0 present in all 3 repos.
- [ ] Custom Dart lint/test placeholder that will fail on raw `TextFormField` usage (activated in S06).

## Tests to write
Backend `test_health.py`; mobile smoke widget test (app builds per flavor); pgTAP smoke (extensions).

## Acceptance criteria / Definition of done
- [ ] Three repos exist with protected `main`, CODEOWNERS, PR template.
- [ ] With native PG 18.6 and Redis running, the API starts with `uv run uvicorn …`; `curl localhost:8000/api/v1/health/live` → `{"status":"ok"}`.
- [ ] Backend fails to start with a clear message when a required env var is missing (test).
- [ ] Flutter app builds and runs for dev/staging/prod flavors with distinct app IDs.
- [ ] CI green on all repos; a commit containing a fake API key is blocked by gitleaks (pre-commit and CI).
- [ ] All versions pinned exactly; lockfiles committed.
- [ ] `.env.example` + README env tables complete for each project.

## Estimated effort
4 developer-days (1 backend, 1 mobile, 0.5 database tooling in parallel).

## Implementation status (2026-10-27)

Repos scaffolded locally under `D:\Naara Care\` (`naraacare-database`, `-backend`, `-mobile`), each `git init`-ed on `main`, **not yet committed or pushed**.

**Update 2026-10-29:** Docker and AWS removed everywhere (owner decision, OQ-45). The Docker Compose stacks, Dockerfile and the `naraacare-infra` (AWS Terraform) repo were deleted; local development and CI now use native installs (`naraacare-database/tools/local_setup.sh`, `install_pgtap.sh`; backend CI `startup` job). The table below reflects that.

| Acceptance criterion | Status |
|---|---|
| Repos with protected `main`, CODEOWNERS, PR template | ⚠️ Local repos + PR templates + Dependabot done; CODEOWNERS has placeholder teams (commented). GitHub repos/branch protection **not created** (needs owner action) |
| Local stack + health endpoint | ✅ native PostgreSQL 18.6 + Flyway CLI verified with the repo scripts; health endpoint verified by tests and by the CI `startup` job (plain Python app) |
| Backend fails fast on missing env var | ✅ tested (names only, never values) |
| Flutter builds for 3 flavors with distinct IDs | ⚠️ Android flavors configured; analyze + 18 tests pass; APK build runs in CI (no Android SDK locally). iOS flavors need `tool/ios/setup_flavors.rb` run once on a Mac |
| CI green; gitleaks blocks a fake key | ⚠️ Workflows written; all checks pass locally (backend: ruff, mypy strict, bandit, pip-audit, Semgrep incl. rule self-tests, 24 tests at 100 % coverage; mobile: analyze, 18 tests). gitleaks flags a planted fake key and finds nothing in repo content. First real CI run happens after the push |
| Exact pins + lockfiles | ✅ `uv.lock`, `pubspec.lock`; CI downloads (Flyway, pgTAP, gitleaks) sha256-verified; Actions pinned by commit SHA |
| `.env.example` + README env tables | ✅ all repos (backend test fails if `.env.example` and `Settings` drift) |

Deviations from the original plan (docs updated): **taskiq** replaces arq (arq caps redis-py < 6); **httpx2** replaces httpx (Starlette TestClient requirement); **Flyway 13.11.1** (not 11); dev object storage is a local folder and dev email an outbox folder (no emulators); Android release signing deferred to S17.
