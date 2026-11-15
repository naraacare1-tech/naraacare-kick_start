# Session 11 — Free vs Paid Tiers, Subscriptions, Receipt Verification, Referral

## Goal and scope
Make STAR purchasable and authoritative: store products, in-app purchase flow, backend receipt verification (Google Play + App Store), store server notifications, entitlement computation and caching, cancel/expiry/grace/refund handling, billing history, upsell surfaces, and the referral programme (codes, links, attribution, tally, rewards).

**In:** `billing.*` functions/procedures, `/billing/*`, `/referrals/*`, webhooks, reconcile job, referral tally job, mobile `features/subscriptions`, `features/referral`, deep-link domain files.
**Out:** custom checkout (removed, OQ-07).

## Prerequisites
S05 (entitlements read), S08–S10 (features to gate). Decisions/defaults: OQ-06 (prices in stores), OQ-07, OQ-39. Store accounts with products `star_monthly`, `star_yearly` created in Play Console and App Store Connect (same IDs), Pub/Sub topic for RTDN, App Store Server Notifications v2 URL configured (sandbox + production), license testers / sandbox testers.

## Files to create / modify

### naraacare-database
```
functions/R__22_billing.fn_current_entitlement.sql   # (refine) subscription statuses + grants
functions/R__20_billing.fn_subscription_for_user.sql fn_billing_history.sql fn_find_subscription_by_token.sql fn_referral_progress.sql
procedures/R__30_billing.pr_upsert_subscription.sql  # binds token/original_transaction_id to one user (UQ); status transitions
procedures/R__30_billing.pr_record_transaction.sql
procedures/R__30_billing.pr_record_store_notification.sql  # idempotent on notification_uid; returns already_processed
procedures/R__30_billing.pr_ensure_referral_code.sql pr_attribute_referral.sql pr_tally_referrals.sql pr_grant_referral_reward.sql
tests/500_billing.sql tests/510_referral.sql
```

### naraacare-backend
```
app/integrations/google_play.py   # subscriptionsv2.get, acknowledge; service account from the secret manager
app/integrations/app_store.py     # SignedDataVerifier (app-store-server-library) + Get Transaction Info / Get All Subscription Statuses
app/integrations/pubsub_auth.py   # verify Pub/Sub push OIDC token (aud, email, iss)
app/api/v1/routers/billing.py billing_webhooks.py referrals.py
app/schemas/billing.py referrals.py
app/domain/entitlements/service.py  # cache (Redis 60 s) + invalidation on billing events
app/domain/referral/service.py      # attribution rules, anti-fraud (installation hash, self-referral, account age ≤ 7 days)
app/workers/jobs/subscription_reconcile.py referral_tally.py
tests/integration/test_billing_google.py test_billing_apple.py test_webhooks.py test_entitlements.py test_referral.py
tests/security/test_billing_security.py
```

### naraacare-mobile
```
lib/features/subscriptions/data/iap_service.dart     # in_app_purchase 3.3.1; purchase stream; pending purchases; restore
lib/features/subscriptions/presentation/screens/{my_subscriptions_standard, upgrade_to_star, purchase_success, my_subscriptions_star, billing_history, cancel_subscription, subscription_cancelled}.dart
lib/features/subscriptions/presentation/widgets/{plan_toggle_monthly_yearly, feature_compare_list}.dart
lib/shared/widgets/nc_upsell_sheet.dart (wire to upgrade flow everywhere)
lib/features/referral/presentation/screens/refer_friends_screen.dart  widgets/progress_tracker.dart
lib/core/security/deep_link_validator.dart  (add /invite/{code})
web/.well-known/assetlinks.json  apple-app-site-association   # delivered to the landing site repo
test/features/subscriptions/** test/features/referral/**
```

## Step-by-step tasks
1. Products: `billing.store_product` rows + `/billing/plans` (display prices come from the store SDK at runtime; DB prices are fallback display only).
2. Purchase flow: app buys → receives `PurchaseDetails` → sends token/JWS to `/billing/purchases/verify` with an `Idempotency-Key` → backend verifies with the store → `pr_upsert_subscription` → acknowledge (Android) → returns entitlements → app calls `completePurchase` only after the backend succeeds.
3. Webhooks: Google RTDN (verify OIDC, decode the message, fetch the authoritative state via API, update); Apple ASSN v2 (verify the JWS chain to Apple Root CA G3, handle `SUBSCRIBED, DID_RENEW, DID_CHANGE_RENEWAL_STATUS, EXPIRED, GRACE_PERIOD_EXPIRED, DID_FAIL_TO_RENEW, REFUND, REVOKE`). Idempotent per notification id.
4. Entitlement service + cache invalidation; `require_entitlement(feature)` dependency already used by S08–S10 now reads real data.
5. Cancel: deep link to store subscription management (Play / App Store); the app shows "access until {period_end}" from the backend. Restore purchases button.
6. Billing history from `store_transaction` (receipts come from the stores; GST invoices are out of scope, to confirm with finance).
7. Downgrade behaviour: STAR-only data hidden, not deleted; sleep shares blurred (S12).
8. Referral: code on account creation (`pr_ensure_referral_code`), link `https://naraacare.app/invite/CODE` (App Links / Universal Links; landing page redirects to the stores with `referrer=` for Play Install Referrer). Attribution at sign-up (`referral_code` in the signup body or `/referrals/attribute` within 7 days). Nightly tally per doc 06 §6; reward = entitlement grant (start at paid period end if subscribed). Refer screen with code, link share, progress (n/5, friends' days).
9. Reconcile job (every 6 h) for subscriptions near expiry or in grace.
10. Upsell sheet everywhere (`UPGRADE_REQUIRED` handler) → Upgrade screen.

## DB objects
Functions/procedures above (tables from S02).

## API endpoints
`GET /billing/plans`, `POST /billing/purchases/verify`, `GET /billing/subscription`, `GET /billing/history`, `POST /billing/webhooks/google`, `POST /billing/webhooks/apple`, `GET /referrals/me`, `POST /referrals/attribute`.

## Screens (Figma frames)
`My Subscriptions` (STANDARD, Monthly/Yearly), `Upgrade to STAR`, "You're now on STAR plan", `My Subscriptions` (STAR), `Billing History`, `Cancel Subscription`, `Subscription Cancelled`, `Refer 5 Friends` (STANDARD 30 days / STAR 50 days), all STAR upsell cards (Today's Nutrition, Sleep locked, Rin unlock, Custom report). **Not built:** Payments & Billing, Add Payment Method, card/UPI/netbanking/wallet forms (OQ-07).

## Security checks
SEC-6.1–6.3; T11–T13; purchase token bound to a single user (reuse on another account rejected + security event); webhook signature/OIDC verification; idempotency; no trust in client purchase state; referral anti-fraud; entitlement cache cannot be poisoned by clients; service-account keys only in the secret manager.

## Input-validation checklist
| Field | Type | Notes |
|---|---|---|
| `purchase_token` | SafeOpaqueToken(2048) | Android |
| `signed_transaction` | SafeOpaqueToken(16384) | iOS JWS |
| `product_id` | Literal['star_monthly','star_yearly'] | |
| `signedPayload` (ASSN) | SafeOpaqueToken(65536) | then JWS verification |
| Pub/Sub `message.data` | base64 → JSON validated with Pydantic | |
| `code` (referral) | SafeReferralCode | deep-link param validated in app too |
| `Idempotency-Key` | UUID | |
- [ ] Payload sweep covers billing/referral fields; deep-link validator tests with payloads.

## Tests to write
Google/Apple verification with recorded sandbox fixtures (valid, expired, refunded, wrong package/bundle, tampered JWS); token reuse across accounts; idempotent verify; webhook replay; forged webhook (bad OIDC / bad chain) → 401 and no change; entitlement transitions (active → canceled (until end) → expired; grace; refund → immediate STANDARD); cache invalidation; referral attribution rules (self, duplicate device, > 7 days), tally (29/30/31 active days, 60-day window), reward once, grant start after paid period; E2E with sandbox purchase on both platforms.

## Acceptance criteria / Definition of done
- [ ] Sandbox purchase on Android and iOS unlocks STAR features within 5 s via backend verification.
- [ ] Cancel keeps STAR until period end; expiry/refund revokes; webhooks reflected within 1 minute.
- [ ] Forged/replayed webhooks have no effect.
- [ ] All STAR endpoints return 403 for STANDARD; entitlement visible in `/me/entitlements`.
- [ ] Referral progress and reward work end to end in staging (time-travel test harness).
- [ ] No custom payment UI present.

## Estimated effort
9–10 developer-days.

## Implementation status (2026-11-02)

Built locally; nothing is committed. Tests are deferred (owner decision, 2026-11-02); the list is in `docs/pending-tasks.md`.

| Acceptance criterion | Status |
|---|---|
| Sandbox purchase on Android and iOS unlocks STAR within 5 s via backend verification | ⏳ code complete (store SDK → `POST /billing/purchases/verify` → store check → entitlement cache dropped → app finishes the purchase only after 200). Needs the store accounts, products `star_monthly`/`star_yearly`, the Play service account, the App Store key and sandbox testers (owner action) |
| Cancel keeps STAR until period end; expiry/refund revokes; webhooks within 1 minute | ✅ in code: `canceled` with a future period end stays STAR (`fn_current_entitlement`); Play RTDN and App Store notifications apply the store's state and drop the cache; refunds/revocations end STAR at once. Live check needs the stores |
| Forged/replayed webhooks have no effect | ✅ in code: Pub/Sub OIDC (signature, issuer, audience, verified service-account email) and Apple JWS chain to the Apple root are checked before anything is read; each notification id is processed once (`pr_record_store_notification`) |
| All STAR endpoints 403 for STANDARD; entitlement in `/me/entitlements` | ✅ (S08–S10 gates now read real subscriptions and grants) |
| Referral progress and reward end to end | ✅ checked once by hand on the migrated database: code format, attribution, repeat ignored, 5 friends with 31 active days qualify, one 30-day STAR grant, entitlement becomes STAR. Staging time-travel test deferred |
| No custom payment UI | ✅ purchases only through Google Play / App Store; Cancel opens the store's page |

**Database:** `V020` (`billing.subscription.purchase_token_ct`, encrypted Play token for reconcile/refunds); `fn_current_entitlement` refined (cancel = access to period end); `billing.fn_plans`, `fn_subscription`, `fn_billing_history`, `pr_upsert_subscription` (token bound to one account; reuse → `token_in_use` + security event), `pr_apply_store_state`, `pr_record_transaction`, `pr_record_store_notification`, `pr_finish_store_notification`, `pr_ensure_referral_code`, `pr_attribute_referral`, `fn_referral_progress`; worker-only `ops.pr_tally_referrals`, `ops.fn_subscriptions_to_reconcile`. All 20 pgTAP files green, no drift, sqlfluff clean.

**Backend:** `GET /billing/plans`, `POST /billing/purchases/verify` (Idempotency-Key, 24 h replay cache), `GET /billing/subscription`, `GET /billing/history` (cursor), `POST /billing/webhooks/google`, `POST /billing/webhooks/apple`, `GET /referrals/me`, `POST /referrals/attribute`; `app/integrations/google_play.py`, `app_store.py`, `pubsub_auth.py`, shared `google_oauth.py` (FCM moved onto it); worker jobs `billing.tally_referrals` (nightly 03:00 IST) and `billing.reconcile_subscriptions` (every 6 h). New errors `PURCHASE_INVALID` (422), `PURCHASE_TOKEN_IN_USE` (409); new type `SafeOpaqueToken65536`. ruff and mypy strict clean.

**Mobile:** `in_app_purchase 3.3.1`; `features/subscriptions`: My Subscriptions (STANDARD plans monthly/yearly with store prices, STAR features, Upgrade, Restore; STAR plan with renewal or "access until", grace warning, Billing History, Cancel → store page), "You're now on STAR", Billing History, Refer 5 Friends (code, link copied to the clipboard, n/5 progress, friends' days, reward), Invite screen for `/invite/<code>` (kept in secure storage, sent from Home after sign-up; allowed before sign-in and on a fresh install). Every upsell's Upgrade now opens My Subscriptions. Android verified App Links per flavor; `deeplink/` templates for `assetlinks.json` and `apple-app-site-association`. `flutter analyze --fatal-infos` clean.

**Decisions and deviations** (docs 00, 03, 04, 08 updated):
- **Store APIs over HTTPS** with the existing HTTP client, PyJWT and cryptography instead of google-api-python-client / google-auth / app-store-server-library: the same checks (Play subscriptionsv2 + acknowledge; Apple x5c chain to Apple Root CA G3 with Apple's OIDs, ES256 signature, bundle id, environment; Pub/Sub OIDC) with a much smaller dependency surface, as in S05 (PyJWT) and S09 (FCM).
- **The Play purchase token is stored encrypted** (new column, V020) besides its blind index, because the reconcile job and refunds must call Google with it.
- **Billing history amounts for Play** use the product's list price (subscriptionsv2 carries no price); Apple amounts come from the signed transaction. Receipts/invoices come from the stores (OQ-72).
- **Webhooks are processed once** per notification id; a failed attempt is retried on the store's redelivery. Unknown subscriptions (notification before the app verified) are ignored; the app's verify binds them.
- **Referral attribution** answers 204 whatever happens; the reason is only logged as a code.
- **New settings:** `GOOGLE_PLAY_API_BASE_URL`, `APP_STORE_API_BASE_URL`, `APP_STORE_SANDBOX_API_BASE_URL`, `PLAY_MANAGE_SUBSCRIPTIONS_URL`, `APP_STORE_MANAGE_SUBSCRIPTIONS_URL` (https only). Outside dev, `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` must be a service-account key and `APPLE_ROOT_CA_PATHS` must exist (`naraacare-backend/certs/README.md`).

**Open:** store accounts, products, keys, Pub/Sub topic, ASSN URLs and testers (owner); iOS Associated Domains (Mac + team); referral domain confirmation (OQ-39); OQ-72 (billing amounts / GST invoices); deferred tests.

