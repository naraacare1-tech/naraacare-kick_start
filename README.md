# NaraaCare — Development Pre-requisites

Documentation and session-wise implementation plan for **NaraaCare**, an avatar-based hydration, nutrition and sleep tracking app (Android + iOS) with a free **STANDARD** tier and a paid **STAR** tier.

> Status: **pre-development**. No application code exists yet. Code is written session by session, following `sessions/`.
> Prepared: 2026-10-25.

## Sources analysed

| Source | Location | How it was read | Notes |
|---|---|---|---|
| Product document | `C:\Users\Sankalp Tiwari\Downloads\NaraaCare MVP.docx` | Full text + all 24 tables (incl. 10 inside content controls) | 4 equations were empty objects; reconstructed from worked examples (see OQ-02) |
| Figma (local export) | `D:\Figma images\` | 60 screen PNGs, 6 boards, `Ideation & Design.pdf` (full-file text) | Source of truth for UI |
| Figma (live file) | `figma.com/design/v0GxcMuSuXWsHBj311G0Oe`, **App Design page only** (`node-id=20-2`) | Page structure read 2026-10-29 (visible vs hidden frames); screenshots limited by the Starter-plan call limit | Hidden frames and other pages are ignored; tokens still sampled (OQ-01) |
| Old code | `D:\naraacare` (github.com/naraacare1-tech/naraacare) | Full read | Next.js landing page + waitlist only; reference for lessons, no reusable app code |

## Three independent projects

| Project | Stack | Talks to |
|---|---|---|
| `naraacare-mobile` | Flutter 3.47.7 / Dart 3.13.5, Riverpod, go_router, dio, drift | Backend REST + WebSocket only |
| `naraacare-backend` | Python 3.13, FastAPI 0.162, Pydantic 2.14, SQLAlchemy 2.1 (async core) + asyncpg | PostgreSQL via stored functions/procedures only |
| `naraacare-database` | PostgreSQL 18.6, Flyway 13.11.1, pgTAP 1.3.4 | — |

## Documentation (`docs/`)

| # | File | Purpose |
|---|---|---|
| 00 | [00-open-questions.md](docs/00-open-questions.md) | Conflicts, gaps and assumptions needing approval (**read first**) |
| 01 | [01-product-overview.md](docs/01-product-overview.md) | Features, roles, STANDARD vs STAR matrix |
| 02 | [02-screen-inventory.md](docs/02-screen-inventory.md) | Every Figma screen, fields + validator, API calls, design tokens |
| 03 | [03-system-architecture.md](docs/03-system-architecture.md) | Architecture diagrams, components, data flows |
| 04 | [04-api-specification.md](docs/04-api-specification.md) | Every endpoint with Safe* types, errors, tier |
| 05 | [05-database-design.md](docs/05-database-design.md) | ER diagram, tables, constraints, indexes, scaling |
| 06 | [06-business-rules-and-calculations.md](docs/06-business-rules-and-calculations.md) | All formulas with verified worked examples |
| 07 | [07-security-architecture.md](docs/07-security-architecture.md) | STRIDE threat model, controls, input-validation layers |
| 08 | [08-environment-and-config.md](docs/08-environment-and-config.md) | All environment variables, 3 projects |
| 09 | [09-coding-standards.md](docs/09-coding-standards.md) | Naming, folders, branching, commits, PR rules |
| 10 | [10-testing-strategy.md](docs/10-testing-strategy.md) | Unit → E2E, security payloads, performance |
| 11 | [11-deployment-and-devops.md](docs/11-deployment-and-devops.md) | CI/CD, environments, backups, monitoring |
| 12 | [12-lessons-from-old-code.md](docs/12-lessons-from-old-code.md) | Keep / avoid from the old repo |

## Implementation sessions (`sessions/`)

| # | Session | Projects |
|---|---|---|
| 01 | [Foundations: repos, tooling, CI, env](sessions/session-01-foundations-repos-tooling-ci.md) | all |
| 02 | [DB schemas, roles, core tables, seed](sessions/session-02-database-schemas-tables-seed.md) | DB |
| 03 | [DB functions, procedures, triggers, audit](sessions/session-03-database-functions-procedures-audit.md) | DB |
| 04 | [Backend core + security middleware + Safe* validators](sessions/session-04-backend-core-security-validators.md) | BE |
| 05 | [Authentication and user profile](sessions/session-05-auth-and-user-profile.md) | DB, BE |
| 06 | [Flutter foundation](sessions/session-06-flutter-foundation.md) | Mobile |
| 07 | [Onboarding and auth screens](sessions/session-07-flutter-onboarding-auth.md) | Mobile, BE |
| 08 | [Nutrition tracking](sessions/session-08-nutrition-tracking.md) | all |
| 09 | [Hydration tracking and reminders](sessions/session-09-hydration-and-reminders.md) | all |
| 10 | [Sleep avatar (STAR)](sessions/session-10-sleep-avatar.md) | all |
| 11 | [Tiers, subscriptions, receipt verification, referral](sessions/session-11-tiers-subscriptions-referral.md) | all |
| 12 | [Connections, Care Circles, chat, notifications](sessions/session-12-social-care-circles-chat.md) | all |
| 13 | [Rin AI (STAR)](sessions/session-13-rin-ai.md) | all |
| 14 | [Profile, streaks, reports, offline sync hardening](sessions/session-14-profile-streaks-reports-sync.md) | all |
| 15 | [Privacy: consent, export, deletion, retention](sessions/session-15-privacy-consent-export-deletion.md) | all |
| 16 | [Security hardening + full payload suite](sessions/session-16-security-hardening-testing.md) | all |
| 17 | [Performance, release builds, store readiness](sessions/session-17-performance-release-store.md) | all |

## Non-negotiable rules (summary)

1. Figma **App Design page, visible frames only** = UI source of truth; MVP document = business-rule **and flow** source of truth (screen order follows the document). Conflicts go to `docs/00-open-questions.md`.
2. No input anywhere (app, API, DB) accepts scripting or markup. Every string uses a shared validator (`input_validators.dart`, `Safe*` Pydantic types, DB `CHECK`).
3. Tier enforcement and all health calculations happen **server-side**.
4. No secrets in the app binary or in git. Production secrets come from the hosting provider's secret manager (hosting is vendor-neutral; no Docker, no AWS).
5. The app only reaches the DB through the backend; the backend only reaches tables through stored functions/procedures.

## Setup guides

- [Hosting setup (PDF)](setup/hosting-setup.pdf): accounts and services to connect for production, where every setting comes from, example backend / database / mobile env files, launch order.
- Local setup: [database](setup/database-setup.md), [frontend](setup/frontend-setup.md), [email OTP](setup/email-otp-setup.md), [STAR test user](setup/star-user-setup.md).
