# Every .env variable, explained simply

Checked on 2026-11-11. This covers the three files the project uses:

| File | Used by | Holds secrets? |
|---|---|---|
| `naraacare-backend/.env` | the API and the background worker | **Yes**. Never commit it, never share it. |
| `naraacare-database/.env` | the database setup scripts (Flyway, psql) | **Yes** (database passwords) |
| `naraacare-mobile/env/dev.env` | the app, when it is built | **No**. Everything in it ends up inside the app, so **never** put a secret there. |

The `.env.example` files next to them are the templates. They only hold dummy values and are safe to commit. `naraacare-mobile/env/test.env` is a committed copy with dummy values for the tests; leave it alone.

**Staging and prod do not use `.env` files.** Each value is typed into the hosting provider's "environment variables" or "secrets" screen instead. The names stay the same.

Each variable below is tagged:

- 🔴 **Change now**: holds your personal details.
- 🟠 **Create before launch**: you need an account or key from a service. Dev works with the dummy value until then.
- 🟢 **Leave as is**: the current value is right. Only change it if you know why.

---

## 1. Your personal email: change these first 🔴

Right now `EMAIL_FROM_ADDRESS`, `SMTP_USERNAME` and `SMTP_PASSWORD` in `naraacare-backend/.env` are your personal Gmail and its app password. Every OTP email goes out from your own inbox. Replace them with a sending address that belongs to NaraaCare.

### Step 1. Get a domain (one time)

Buy `naraacare.app` (or whatever name you choose) from any domain registrar. Every NaraaCare address will end in it, like `no-reply@naraacare.app`. You need it for the website, the API address, deep links and email anyway.

### Step 2. Pick a "transactional email" service

This is a service built to send app emails (OTP codes, receipts) quickly and without landing in spam. Gmail is not built for that: it limits how much you can send each day, and your personal account gets flagged if users mark mail as spam.

Any provider that offers **SMTP** works with the backend, so you can switch later without changing code. Examples: Brevo, Postmark, Mailgun, Zoho ZeptoMail. Most have a free tier that covers early testing. Check the price per email and where the provider stores data before you pick one.

### Step 3. Prove you own the domain

The provider shows a few DNS records (called **SPF**, **DKIM** and usually **DMARC**). Log in to your domain registrar, open **DNS settings**, and add each record exactly as shown. Then click **Verify** on the provider's page. This can take from a few minutes to a day.

*Why:* these records are like a signed letter from your domain saying "this service may send mail for me". Without them, Gmail and Outlook put your OTP emails in spam.

### Step 4. Get the SMTP details

On the provider's site, find **SMTP settings** or **SMTP credentials**. It shows a host, a port, a username and a password (sometimes called an "SMTP key"). Copy them.

### Step 5. Paste them into `naraacare-backend/.env`

| Variable | What to put | Where it comes from |
|---|---|---|
| `EMAIL_BACKEND` | `smtp` to send real email, `outbox` to save emails as files (no setup) | You choose |
| `EMAIL_FROM_ADDRESS` | `no-reply@naraacare.app` | Your domain. The provider must have verified it (step 3). |
| `SMTP_HOST` | for example `smtp-relay.brevo.com` | The provider's SMTP page |
| `SMTP_PORT` | `587` (already set) | The provider's SMTP page. Almost always 587. |
| `SMTP_USERNAME` | the SMTP login | The provider's SMTP page. Often not your email address. |
| `SMTP_PASSWORD` | the SMTP password or key | The provider's SMTP page. **Secret.** |

Restart the backend. Then sign up in the app with an address you can open, and check the OTP arrives.

### Step 6. Delete the Gmail app password

Go to https://myaccount.google.com/apppasswords and delete the "Naaracare" app password. Once it's deleted, the old Gmail details stop working everywhere.

### The other email addresses in the backend

| Variable | What it's for | What to put |
|---|---|---|
| `SUPPORT_INBOX_ADDRESS` 🟠 | Where help-and-support messages from users go | A real inbox you read, like `support@naraacare.app`. Create it with any email host on your domain (Zoho Mail, Google Workspace, Microsoft 365, or your registrar's email). |
| `SUPPORT_CONTACT_EMAIL` 🟢 | The email shown on the app's Help screen | Leave empty to show `SUPPORT_INBOX_ADDRESS`. Set it only if you want a different public address. |
| `OPEN_FOOD_FACTS_USER_AGENT` 🟢 | Tells the free food database who is calling it (they ask for a contact email) | `NaraaCare/0.1 (support@naraacare.app)` is already right once that inbox exists |

Until you have the domain, you can keep `EMAIL_BACKEND=outbox` and read OTP codes from `naraacare-backend/var/outbox/` instead (see [email-otp-setup.md](email-otp-setup.md)). Then nothing personal is used at all.

---

## 2. Backend: values you create before launch 🟠

### Google sign-in

| Variable | What to put | How to get it |
|---|---|---|
| `GOOGLE_OAUTH_CLIENT_IDS` | The Web client ID and the iOS client ID, comma-separated, no spaces | Google Cloud Console → Google Auth Platform → Clients. Full steps in [sign-in-and-jwt-setup.pdf](sign-in-and-jwt-setup.pdf), Part 1. |

### Apple sign-in (needs the Apple Developer Program, US$99/year)

| Variable | What to put | How to get it |
|---|---|---|
| `APPLE_TEAM_ID` | 10 characters, like `A1B2C3D4E5` | developer.apple.com → Account → Membership details |
| `APPLE_BUNDLE_ID` | `com.naraacare.app.dev` (dev), `com.naraacare.app` (prod) | The app's ID. Register it under Identifiers. |
| `APPLE_SERVICE_ID` 🟢 | Leave the dummy value | Only needed for Apple sign-in on Android or web, which the app doesn't offer |
| `APPLE_SIWA_KEY_ID` | 10 characters | Certificates, Identifiers & Profiles → Keys → new key with "Sign in with Apple" |
| `APPLE_SIWA_PRIVATE_KEY_P8` | The whole text of the downloaded `.p8` file, inside double quotes | Same key. **Secret. You can download it only once.** |

Full steps: [sign-in-and-jwt-setup.pdf](sign-in-and-jwt-setup.pdf), Part 2.

### JWT (the "wristband" that keeps users signed in)

| Variable | What to put | How to get it |
|---|---|---|
| `JWT_ISSUER` | `http://localhost:8000` in dev; your real API address in prod, like `https://api.naraacare.app` | You choose it. Pick the prod value once and don't change it. |
| `JWT_AUDIENCE` 🟢 | `naraacare-mobile` | Leave it |
| `JWT_PRIVATE_KEY_PEM` | Line 1 printed by the key tool | Run `uv run python tools/new_jwt_key.py --kid k1` in `naraacare-backend`. **Secret.** Empty in dev means you're signed out after every restart. |
| `JWT_PUBLIC_KEYS_JSON` | Line 2 printed by the same command, inside single quotes | Same command |
| `JWT_ACTIVE_KID` | `k1` | The name you gave with `--kid` |

Full steps: [sign-in-and-jwt-setup.pdf](sign-in-and-jwt-setup.pdf), Part 3. Use a **different** key for dev, staging and prod.

### Store purchases: Google Play

| Variable | What to put | How to get it |
|---|---|---|
| `GOOGLE_PLAY_PACKAGE_NAME` | `com.naraacare.app.dev` (dev), `com.naraacare.app` (prod) | The Android app ID |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | The whole downloaded JSON file, on one line, inside single quotes | 1) Google Cloud Console → IAM & Admin → Service accounts → Create (name it "play-billing"). 2) Open it → Keys → Add key → JSON. A file downloads. 3) Play Console → Users and permissions → Invite new user → paste the service account's email → give it "View financial data" and "Manage orders and subscriptions". **Secret.** |
| `GOOGLE_RTDN_PUSH_AUDIENCE` | `https://api.naraacare.app/api/v1/billing/webhooks/google` | Your real API address plus that path. It must match what you type in the Pub/Sub push subscription (next row). |
| `GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL` | The email of the service account Pub/Sub uses to call you | 1) Google Cloud → Pub/Sub → create a topic. 2) Play Console → Monetize → Monetization setup → paste the topic name. 3) In Pub/Sub, create a **push** subscription to the URL above, tick **Enable authentication**, and pick a service account. That account's email goes here. |

*Why:* when someone buys, renews or cancels, Google tells our server through Pub/Sub ("real-time developer notifications"). The audience and email let the server check the message really came from Google.

### Store purchases: App Store

| Variable | What to put | How to get it |
|---|---|---|
| `APP_STORE_ISSUER_ID` | A long ID with dashes | App Store Connect → Users and Access → Integrations → In-App Purchase. The Issuer ID is shown at the top. |
| `APP_STORE_KEY_ID` | 10 characters | Same page → Generate in-app purchase key → copy its Key ID |
| `APP_STORE_PRIVATE_KEY_P8` | The whole text of the downloaded `.p8` file, inside double quotes | Same key → Download (**only once**). **Secret.** This is a different key from the Sign in with Apple one. |
| `APP_STORE_ENVIRONMENT` | `Sandbox` for dev and staging, `Production` for prod | You choose. Prod refuses `Sandbox`. |
| `APPLE_ROOT_CA_PATHS` | `certs/AppleRootCA-G3.cer` (already set) | Download "Apple Root CA - G3" from https://www.apple.com/certificateauthority/ and put it in `naraacare-backend/certs/`. It is public, not a secret. |

### Push notifications (Firebase Cloud Messaging)

| Variable | What to put | How to get it |
|---|---|---|
| `FCM_SERVICE_ACCOUNT_JSON` | The whole downloaded JSON file, on one line, inside single quotes | 1) https://console.firebase.google.com → Add project. Pick the same Google Cloud project as sign-in. 2) Add an Android app (`com.naraacare.app.dev`) and an iOS app. 3) Project settings (gear icon) → Service accounts → Generate new private key. A JSON file downloads. **Secret.** |

### Rin AI (OpenAI)

| Variable | What to put | How to get it |
|---|---|---|
| `OPENAI_API_KEY` | Starts with `sk-` | https://platform.openai.com → sign in with a NaraaCare account (not personal) → Settings → Billing (add a card and a monthly limit) → API keys → Create new secret key. **Secret.** It's shown only once. |
| `RIN_ENABLED` 🟢 | `true` | Set it to `false` to switch off the AI features |
| `RIN_MODEL`, `RIN_EFFORT`, `RIN_MAX_OUTPUT_TOKENS` 🟢 | as set | Which model and how much it may write |
| `RIN_MONTHLY_BUDGET_INR` 🟢 | `10` | The AI spending limit per user per month, in rupees |
| `AI_PRICE_*`, `AI_USD_TO_INR` 🟢 | as set | OpenAI's prices and the exchange rate, used to work out the cost of each call. Update them when OpenAI's prices change. |
| `RIN_FALLBACK_MODEL`, `AI_FALLBACK_PRICE_*` 🟢 | defaults (`gpt-5-nano`) | A cheaper model, and its prices, used when the main one can't be. They have defaults, so you don't need to add them to `.env`. |

### Production-only values

| Variable | What to put |
|---|---|
| `APP_ENV` | `dev` here, `staging` or `prod` on servers. Prod switches on all the safety checks. |
| `DATABASE_URL` | Your hosted database's address, user `app_rw`, and its password. **Secret.** |
| `DATABASE_SSL_MODE` | `disable` locally; `verify-full` on servers (prod refuses anything else) |
| `DATABASE_SSL_ROOT_CERT` | Path to the database provider's CA certificate file (they let you download it) |
| `REDIS_URL` | Address of a Redis server for the background worker. Leave it empty to run only the API. |
| `ALLOWED_HOSTS` | The API's domain on servers, for example `api.naraacare.app` |
| `STAFF_IP_ALLOWLIST` | The office or VPN IP addresses allowed to open `/admin` pages. Leave it empty to close them. |
| `API_DOCS_ENABLED` / `API_DOCS_BASIC_AUTH` | `true` and `user:password` on staging to protect the docs page; `false` in prod (prod refuses `true`) |
| `REFERRAL_LINK_DOMAIN` | The domain used in invite links: `naraacare.app` |

---

## 3. Backend: leave these as they are 🟢

They already have sensible values, or they are fixed addresses owned by Google, Apple or OpenAI.

| Variables | What they do |
|---|---|
| `APP_NAME`, `APP_VERSION`, `LOG_LEVEL` | The service's name and version in the logs, and how much it logs (`DEBUG` is refused in prod) |
| `CORS_ALLOWED_ORIGINS` | Websites allowed to call the API from a browser. Empty, because the app is not a website. |
| `DATABASE_REPLICA_URL`, `DATABASE_POOL_SIZE`, `DATABASE_MAX_OVERFLOW` | An optional read-only copy of the database, and how many database connections to keep open |
| `ACCESS_TOKEN_TTL_SECONDS`, `REFRESH_TOKEN_TTL_DAYS`, `LINK_TOKEN_TTL_SECONDS` | How long sign-in tokens last (15 minutes, 60 days, 10 minutes) |
| `ARGON2_MEMORY_KIB`, `ARGON2_TIME_COST`, `ARGON2_PARALLELISM` | How hard passwords are to crack. Don't lower them. |
| `STORAGE_ROOT_DIR`, `STORAGE_CONTAINER_REPORTS`, `STORAGE_CONTAINER_ATTACHMENTS` | Where report PDFs and chat attachments are saved |
| `EMAIL_OUTBOX_DIR` | The folder where emails are saved when `EMAIL_BACKEND=outbox` |
| `SUPPORT_EMAIL_RESPONSE`, `SUPPORT_PHONE`, `SUPPORT_PHONE_HOURS` | Text on the Help screen. Set `SUPPORT_PHONE` (like `+91 98xxxxxxxx`) only if you want STAR users to see a phone number. |
| `GOOGLE_JWKS_URL`, `APPLE_JWKS_URL`, `APPLE_TOKEN_URL`, `APPLE_REVOKE_URL`, `GOOGLE_OAUTH_TOKEN_URL`, `FCM_API_BASE_URL`, `GOOGLE_PLAY_API_BASE_URL`, `APP_STORE_*_URL`, `PLAY_MANAGE_SUBSCRIPTIONS_URL`, `OPEN_FOOD_FACTS_BASE_URL` | Fixed web addresses of Google, Apple, Firebase and Open Food Facts |
| `MAX_BODY_BYTES`, `MAX_UPLOAD_BYTES` | Largest request (1 MB) and largest upload (10 MB) |
| `WORKER_CONCURRENCY` | How many background jobs run at once |

---

## 4. Database file (`naraacare-database/.env`)

Locally these are just passwords for your own PC. On a real server, every password must be new and long. A password manager can generate them.

| Variable | Tag | What to put |
|---|---|---|
| `PGHOST`, `PGPORT`, `PGDATABASE` | 🟢 | Where PostgreSQL runs: `localhost`, `5432`, `naraacare` |
| `POSTGRES_USER`, `POSTGRES_PASSWORD` | 🟠 | The PostgreSQL superuser you chose when you installed PostgreSQL. Your current password is a simple one; use a strong one on any shared or real server. Only the setup scripts use it, never the app. |
| `FLYWAY_URL` | 🟢 | The same database written the way Flyway wants (`jdbc:postgresql://...`) |
| `FLYWAY_USER`, `FLYWAY_PASSWORD` | 🟠 | The `migration_owner` user that creates the tables. Pick the password yourself before the first setup; the setup script creates the user with it. |
| `FLYWAY_PLACEHOLDERS_APP_RW_PASSWORD` | 🟠 | Password for `app_rw`, the user the API logs in as. **It must match the password inside the backend's `DATABASE_URL`.** |
| `FLYWAY_PLACEHOLDERS_APP_WORKER_PASSWORD` | 🟠 | Password for the background worker's database user |
| `FLYWAY_PLACEHOLDERS_APP_READONLY_PASSWORD`, `FLYWAY_PLACEHOLDERS_REPORTING_PASSWORD` | 🟠 | Passwords for the read-only and reporting users (for future dashboards) |
| `FLYWAY_PLACEHOLDERS_SEED_SAMPLE_FOODS` | 🟢 | `true` loads sample foods for testing. **Must be `false` in prod.** |
| `FLYWAY_LOCATIONS`, `FLYWAY_VALIDATE_MIGRATION_NAMING`, `FLYWAY_CLEAN_DISABLED` | 🟢 | Which folders Flyway runs, and a safety switch that stops it from wiping the database |
| `PGTAP_DATABASE` | 🟢 | A separate database used only by the database tests |

The role passwords are only used the **first** time the database is built. To change one later, change it in PostgreSQL itself (`ALTER ROLE app_rw PASSWORD '...'`) and in the backend's `DATABASE_URL`.

---

## 5. Mobile file (`naraacare-mobile/env/dev.env`)

Nothing here is secret. Rebuild the app after changing it.

| Variable | Tag | What to put |
|---|---|---|
| `ENV_NAME` | 🟢 | `dev`, `staging` or `prod`. It must match the build you run. |
| `API_BASE_URL` | 🟢 / 🟠 | Dev: `http://10.0.2.2:8000/api/v1` (the emulator's name for this PC). Real phone or prod: your API address, which must start with `https://`. |
| `WS_BASE_URL` | 🟢 / 🟠 | The same address starting with `ws://` (dev) or `wss://` (prod), ending in `/ws` |
| `CERT_PINS` | 🟠 | Empty in dev. For staging and prod: fingerprints of your API's HTTPS certificate key (current and backup). Your hosting provider's certificate setup gives you the key; ask before launch. The app refuses to start in prod without them. |
| `GOOGLE_SERVER_CLIENT_ID` | 🟠 | The Google **Web** client ID (the same one in the backend's `GOOGLE_OAUTH_CLIENT_IDS`) |
| `TERMS_URL`, `PRIVACY_URL` | 🟠 | Links to your published Terms and Privacy Policy pages, starting with `https://` |

---

## What was removed on 2026-11-11, and why

These variables were set but **nothing in the code read them**. Changing them did nothing, which is confusing, so they were deleted from the `.env` files, the templates, the settings code and the READMEs.

| Removed from | Variables | Notes |
|---|---|---|
| Backend | `MIN_APP_VERSION_ANDROID`, `MIN_APP_VERSION_IOS` | No force-update check uses them yet |
| Backend | `OTP_TTL_SECONDS`, `OTP_MAX_ATTEMPTS`, `OTP_RESEND_COOLDOWN_SECONDS`, `OTP_MAX_SENDS_PER_HOUR` | The real OTP rules are fixed in the auth code |
| Backend | `LOCKOUT_THRESHOLD`, `LOCKOUT_WINDOW_SECONDS`, `DATABASE_STATEMENT_TIMEOUT_MS` | The real values live in the database |
| Backend | `STORAGE_BACKEND`, `STORAGE_CONTAINER_EXPORTS`, `STORAGE_SIGNED_URL_TTL_SECONDS` | Storage only has one kind, and these two were never read |
| Backend | `INVITE_LINK_TTL_DAYS`, `RATE_LIMIT_DEFAULT_PER_MIN_USER`, `RATE_LIMIT_DEFAULT_PER_MIN_IP` | Fixed in code |
| Backend | `SENTRY_DSN`, `SENTRY_TRACES_SAMPLE_RATE`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `FEATURE_FLAGS_SOURCE` | No error-tracking or tracing library is installed; feature flags always come from the database |
| Mobile | `SENTRY_DSN`, `APPLE_SERVICE_ID`, `APPLE_REDIRECT_URI`, `REFERRAL_LINK_DOMAIN`, `SUPPORT_EMAIL`, `FEATURE_FLAGS`, `STORE_PRODUCT_IDS`, `LOG_HTTP` | Read into the app's settings but never used by any screen |

If one of these features is built later, add the variable back at the same time as the code that uses it.
