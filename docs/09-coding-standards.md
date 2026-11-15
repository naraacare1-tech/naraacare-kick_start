# 09 — Coding Standards

## 1. Repositories and branching

- Repos: `naraacare-mobile`, `naraacare-backend`, `naraacare-database` (+ this docs folder as `naraacare-docs`). GitHub org `naraacare1-tech`.
- Trunk-based: `main` is always releasable; short-lived branches ≤ 3 days.
- Branch names: `feat/<session-no>-<short-topic>`, `fix/<issue>-<topic>`, `chore/…`, `sec/…`, `db/…` (e.g. `feat/s08-meal-logging`).
- Releases: tags `vMAJOR.MINOR.PATCH` (semver). Mobile build number = CI run number. DB migrations are versioned by Flyway `V###`.
- Protected `main`: PR required, CI green, linear history (squash merge), signed commits, no force push. CODEOWNERS: `security/`, `auth/`, `billing/`, `migrations/` need 2 approvals (one from the security owner).

## 2. Commits

Conventional Commits: `type(scope): summary` (imperative, ≤ 72 chars). Types: `feat, fix, sec, perf, refactor, test, docs, build, ci, chore, db`.
Example: `feat(hydration): compute tank level piecewise across temperature changes`.
Body: what and why; reference the session file and OQ IDs (`Refs: S09, OQ-17`). Never include secrets, real user data or tokens.

## 3. Pull requests

PR template checklist (all must be ticked or marked N/A with a reason):
- [ ] Linked session file + acceptance-criteria items this PR satisfies
- [ ] Tests added/updated (unit + integration; security tests when touching inputs/auth)
- [ ] **Every new string field uses a shared validator**: Flutter `InputValidators.*` + `maxLength`; backend `Safe*` type; DB `common.safe_text` + length CHECK. **A string field without a Safe* validator fails review.**
- [ ] New text fields added to the payload test matrix
- [ ] No secrets, no PII in logs, no health values in analytics/crash reports
- [ ] Object-level authorisation checked (user from token; ownership in DB function)
- [ ] Tier rule enforced server-side (if feature is STAR)
- [ ] DB: migration is additive / backward-compatible; indexes have `COMMENT` with the query they serve
- [ ] API: OpenAPI updated; error codes from the catalogue; pagination limits
- [ ] Docs updated (04/05/06) if contracts or rules changed; OQ decisions referenced
- [ ] Screenshots for UI changes (iOS + Android)

PR size: ≤ 400 changed lines preferred; larger PRs need a reason. Review SLA: 1 working day.

## 4. Python (backend)

- Python 3.13, `from __future__ import annotations` not needed. Type hints everywhere; `mypy --strict` passes.
- ruff (lint + format, line length 100), rules: `E,F,W,I,N,UP,B,S,ASYNC,DTZ,T20,SIM,RUF,PL`. `print` banned (T20). `datetime.now()` without tz banned (DTZ).
- Naming: modules `snake_case`, classes `PascalCase`, constants `UPPER_SNAKE`, Pydantic request models `XxxRequest`, responses `XxxResponse`.
- Layers: `routers` (HTTP only) → `domain` (pure logic, no I/O imports) → `repositories` (DB only). Routers never call repositories directly for business flows; domain never imports FastAPI.
- Repositories call **only** stored functions/procedures with bound parameters: `await conn.execute(text("SELECT * FROM nutrition.fn_daily_summary(:uid, :d)"), {...})`. No ORM table models. No string-built SQL (Semgrep rule `no-sql-string-building`).
- Schemas: `ConfigDict(extra="forbid", strict=True)`. Every `str` → `Safe*` (Semgrep rule `no-bare-str-in-schemas`). Numbers via `Annotated[int, Field(ge=, le=)]`.
- Money/nutrition maths in `Decimal`; hydration in `float`; rounding helpers in `domain/common/rounding.py`.
- Errors: raise `AppError` subclasses with a catalogue code; never return raw exceptions.
- Async everywhere on I/O; no blocking calls in request path (Pillow/ReportLab run in worker or `run_in_threadpool`).
- Logging: `structlog.get_logger()`; event names `snake_case`; never log request bodies, tokens or PII.

## 5. Dart / Flutter (mobile)

- `very_good_analysis` + project rules; `flutter analyze` zero warnings; `dart format` (80 cols).
- Naming: files `snake_case.dart`, classes `PascalCase`, providers `xxxProvider` (generated), private members `_x`.
- Feature-first Clean Architecture (doc 03 §3). Presentation may depend on domain; domain is pure Dart (no Flutter imports); data implements domain contracts.
- State: Riverpod with `@riverpod` code generation; no global singletons; side effects in notifiers, not widgets.
- Models: `freezed` + `json_serializable`; DTOs ≠ entities.
- UI: only design tokens from `core/theme/tokens.dart` (no hex literals or magic numbers in widgets; custom lint). Text via `l10n` (no hard-coded user-facing strings).
- Inputs: only `NcTextField` (requires `validator` from `InputValidators` and `maxLength`); raw `TextField`/`TextFormField` banned outside the shared widget (custom lint + test).
- No `print`; use `AppLogger` (no-op in release). No WebView. No `dart:mirrors`.
- Navigation via named routes from `app_router.dart`; deep links validated in `deep_link_validator.dart`.

## 6. SQL (database)

- sqlfluff (dialect `postgres`), uppercase keywords, `snake_case` identifiers, explicit schema on every object.
- File naming: `tables/<schema>.<table>.sql`, `indexes/<schema>.<table>.sql`, `functions/R__20_<schema>.fn_<name>.sql`, `procedures/R__30_<schema>.pr_<name>.sql`, `views/R__40_<schema>.v_<name>.sql`, `triggers/R__50_<schema>.trg_<name>.sql`, `migrations/V###__<verb>_<object>.sql` (e.g. `V012__create_hydration_intake.sql`).
- Prefixes: functions `fn_` (reads; `STABLE`/`IMMUTABLE`, `RETURNS TABLE`/`SETOF`), procedures `pr_` (writes; `CREATE PROCEDURE`, `INOUT` outputs), triggers `trg_`, views `v_`, indexes `ix_<table>__<cols>`, unique `uq_…`, checks `ck_<table>__<rule>`, FKs `fk_<table>__<ref>`.
- Every function: `SECURITY DEFINER` only when needed; `SET search_path = pg_catalog, pg_temp`; validates parameters (cast text to `common.safe_text`; ranges) and raises with `ERRCODE` mapped in the backend (`22023` invalid input → 422, `42501` → 404/403, `P0001` with `DETAIL` code → business error, `40001` → retry).
- Every index file includes `COMMENT ON INDEX … IS 'serves: <function/query>'`.
- No dynamic SQL except in `ops` using `format('%I', …)`.
- `V` migrations are immutable after merge; fix forward.

## 7. Folder rules (all projects)

- Follow the layouts in doc 03 exactly; new top-level folders need a PR note.
- Tests mirror source paths (`app/domain/hydration/calculator.py` → `tests/unit/domain/hydration/test_calculator.py`).
- Generated code (`*.g.dart`, `*.freezed.dart`) committed? **No** — generated in CI via `build_runner`; `.gitignore` excludes them.

## 8. Documentation in code

- Comment density: explain *why*, not *what*. Formula code cites the doc section (`# doc 06 §3.4`).
- Public functions in `domain/` have docstrings with units (`weight_kg: float`).
- Each project README contains: setup, run, test, env-var table, troubleshooting.

## 9. Definition of Done (every story)

Code + tests merged, CI green (lint, types, unit, integration, security, SAST, secret scan), acceptance criteria in the session file ticked, docs updated, no new high/critical vulnerabilities, feature behind a flag if incomplete.
