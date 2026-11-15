# 02 — Screen Inventory and Design Tokens

Source: Figma file `v0GxcMuSuXWsHBj311G0Oe`, **App Design page only** (`node-id=20-2`), **visible frames only** (structure read 2026-10-29); images from the local export `D:\Figma images\` are used only for frames that are visible on that page. Frame names below are the Figma frame names.

**Figma scope (owner rule, 2026-10-29):** only the **App Design** page (`node-id=20-2`) is used, and **hidden frames/layers on it are ignored**. Other pages and hidden frames (old Home/Profile/Settings/Care circle versions, Subscription/Pay, payment-method screens, Referral and Mobile Verification at sign-up, Request new food, Analyse and Update, Info Tip, the old Rin chatbot) are not part of the product.

**Flow (owner rule, 2026-10-29):** screen order and navigation follow the MVP document (§1 App flow, §2 Authentication, §3 Onboarding, §6 Care Circle invite flow); Figma supplies the screens. Where the visible frames differ, the document wins and the difference is logged in doc 00.
Validator column = Flutter `InputValidators.*` (lib/core/security/input_validators.dart) → backend `Safe*` type. Full rules: doc 07 §4.

---

## 1. Design foundations

> ⚠️ Colours are **sampled from PNG pixels** (OQ-01). Replace with Figma Variables before Session 06 sign-off. Font names are inferred visually (OQ-57).

### 1.1 Layout grid (from Figma foundations page — exact)

| Platform | Frame | Columns | Margin | Gutter | Safe areas |
|---|---|---|---|---|---|
| iOS | 390 × 844 | 4 | 20 | 16 | top 59, bottom 34 |
| Android | 412 × 917 | 4 | 16 | 16 | status bar 24, bottom gesture 16 |

Scroll: vertical only, no horizontal scrolling; sticky top app bar; bottom navigation fixed.

### 1.2 Spacing tokens (exact)

| Token | Value | Use |
|---|---|---|
| `space.screenPadding` | 16 (Android) / 20 (iOS) | screen side padding |
| `space.sectionGap` | 32 | between sections |
| `space.cardGap` | 16 | between cards |
| `space.cardPadding` | 16 | inside cards |
| `space.buttonGap` | 12 | stacked buttons |
| `space.inputGap` | 8 | label ↔ input, input ↔ hint |
| `size.buttonHeight` | 56 | primary buttons, fill container |
| `size.onboardingTextMaxWidth` | 320 | onboarding copy |

Radius scale named on the foundations page: `XXS, XS, S, M, L, XL, Full` (values not exported — confirm; proposed 2/4/8/12/16/24/999).

### 1.3 Colour tokens (sampled)

| Token | Hex (sampled) | Seen on |
|---|---|---|
| `color.primary` | `#35AFF4` | primary buttons, links, active tab, titles on auth screens |
| `color.primaryDisabled` | `#C4D8E4` | disabled primary button |
| `color.primarySurface` | `#E6F5FE` | selected chips, OTP active box, info cards |
| `color.star` | `#684C9C` | STAR upsell cards ("Unlock STAR") |
| `color.success` | `#19B27A` | verified badge icon |
| `color.successSurface` | `#DDF5EC` | verified badge ring |
| `color.error` | `#F87171` | error text, error borders |
| `color.errorSurface` | `#FCF0F0` | error banner background |
| `color.textPrimary` | `#111827` | headings |
| `color.textBody` | `#344044` | body copy |
| `color.textSecondary` | `#6B7280` | hints, captions |
| `color.inputFill` | `#F2F2F7` | text field background |
| `color.surface` | `#FFFFFF` | backgrounds, cards |
| `color.hydration.well` / `drinkSoon` / `low` / `critical` | TBD | hydration bands (DOC: "avatar colour bands") — need from design |

Dark mode: not designed → MVP is light-only; tokens structured so dark theme can be added.

### 1.4 Typography

Styles named in Figma: `H1, H2, H3, H4, Body Large (Base/Strong), Body Regular (Base/Strong), Body Small (Base/Strong), Caption, Footnote`.
Family: **Manrope** (proposed, OQ-57); brand serif for the Welcome tagline only. Sizes to be read from Figma (OQ-01); proposed mapping 32/28/24/20 · 18/16/14 · 12/11.
Support dynamic type up to 130 % without clipping.

### 1.5 Components (from foundations page)

Bottom navigation (Home · Care Circle · Rin AI · Profile, 5 states) · Primary/secondary/ghost buttons (default, pressed, disabled, "Continue") · Text field states: Empty, Focused, Filled, Error, Disabled, with label/hint/helper · Password field with show/hide and strength message · Dialog (title, body, Action 1/2) · Chips (presets like "+250 ml") · OTP 6-box input · Wheel pickers (height ruler, temperature, time) · Bottom sheets (slide-in) · Avatar carousel with pager dots · Toast ("New code sent successfully on your email") · Error banner · STAR badge · List rows with chevron · Segmented tabs (Water / Other Drinks; Monthly / Yearly; ft-in / cm; kg / lb).

App icon exports: 1024, 512, 400, 180, 64, 48 px; logos: primary, secondary, vertical, web, white, black, favicon, social watermark.

Android: same layouts; back by system swipe or ✕ button; ripple effects on buttons/chips (FIG note).

---

## 2. Screen inventory

Legend for API column: endpoints from doc 04 (prefix `/api/v1` omitted).

### 2.0 Navigation flow (MVP document §1, with the visible App Design frames)

```
Splash ─┬─ first install ──▶ Intro 1 → Intro 2 → Intro 3 (Skip) ─▶ Welcome          (OQ-62)
        ├─ signed out ─────────────────────────────────────────────▶ Welcome
        └─ signed in ──▶ onboarding done? ── no ──▶ resume onboarding step
                                        └── yes ─▶ HOME
Welcome ─┬─ Get Started ─▶ Sign Up → Check Your Email (6-digit code) → Email Verified
         │                 → After sign in (Build my avatar) → Steps 1–6 → Your avatar is ready
         │                 (Edit Details ↺ | Save my avatar) → Generating… → Saved Details → HOME
         └─ Sign In ─────▶ Sign In ── success ─▶ HOME (or resume onboarding)
                           └─ Forgot Password → Check Your Email (code) → Set New Password
                              → Password Changed → Sign In                              (OQ-64)
HOME | CARE CIRCLE | RIN AI | PROFILE   (bottom navigation, 4 tabs)
Invite link (DOC §6): open link → install/open app → Sign Up or Sign In → onboarding (if new)
                      → username popup → choose avatars to share → circle home
```

### 2.1 Launch and authentication

| # | Frame | Purpose | Key components | Input fields → validator | API calls |
|---|---|---|---|---|---|
| A1 | `Splash` | Brand + token check, then route per §2.0 | logo | — | `POST /auth/token/refresh` (if refresh token stored), `GET /reference/bootstrap` |
| A1a | `Onboarding 1 - Meet your health avatars`, `Onboarding 2 - Goals made for your body`, `Onboarding 3 - Care for each other` (Login Process section) | Intro slides, first install only (OQ-62); Next / Skip; last slide "Get Started" → Welcome | illustration, page dots, Next, Skip | — | — |
| A2 | `Welcome` | Entry | illustration, tagline, Get Started, "Already have an account? Sign In" | — | — |
| A3 | `Sign Up` (+ `Filled/Password Hidden`, `Password Shown`, `Error State/Email already registered`, `Password Mismatch`) | Create account (no Full Name: hidden in FIG, asked at onboarding step 1, OQ-65) | logo, email, password, confirm, terms checkbox, Sign Up, Google, Apple | Email → `email()` / `SafeEmail` (max 254) · Password → `password()` / `SafePassword` (8–128) · Confirm → `confirmPassword()` (client-only match; server re-checks) · Terms checkbox (bool) | `POST /auth/signup`, `POST /auth/oauth/google`, `POST /auth/oauth/apple` |
| A4 | `Email Verification` (+ `-1`, `-2`, `Resent code`, `Wrong OTP`) | Verify OTP | 6 boxes, Verify Email, Resend Code + countdown, toast | OTP → `otp()` / `SafeOtp` (`^\d{6}$`, digits-only formatter) | `POST /auth/otp/verify`, `POST /auth/otp/resend` |
| A5 | `Email Verified` | Success | badge | — | — |
| A6 | `Sign In` (+ `Error State`) | Login | email, password, Forgot Password?, Sign In, Google, Apple, Create an Account | Email `email()`/`SafeEmail` · Password `passwordLogin()` (length + no-markup only) / `SafePassword` | `POST /auth/login`, OAuth endpoints |
| A7 | `Forgot Password` (+ `Email`, `Error State`) | Request reset | email, Reset Password, Back to Sign In | Email `email()`/`SafeEmail` | `POST /auth/password/forgot` |
| A8 | `Forgot Password/Reset Password/Verification` | Check Your Email: enter the reset code (FIG copy says "link"; changed to "code", OQ-64) | 6 code boxes, Resend Code | OTP `otp()`/`SafeOtp` | (code sent with A9 submit) |
| A9 | `Reset Password` (+ `-1` mismatch) | Set new password | new, confirm, rules list | New `password()`/`SafePassword` · Confirm `confirmPassword()` | `POST /auth/password/reset` |
| A10 | `Password Changed` | Success | Back to Sign In | — | — |
| A11 | Google/Apple error banners | "Unable to connect to Apple…" | banner + retry | — | — |

### 2.2 Onboarding (`Onboarding`, `Onboarding 1..6`, `After sign in`)

| # | Frame | Purpose | Input fields → validator | API calls |
|---|---|---|---|---|
| O0 | `After sign in/Onboarding` | Intro "Let's build your Healthy avatar" + Build my avatar | — | `GET /me/onboarding` (resume step) |
| O1 | `Onboarding 1` (Default, Typing, Filled/Active State) | 1/6 sex + avatar card select, full name | Sex (2 cards, enum) · Full name → `name()` / `SafeName` (1–100) | `PUT /me/onboarding/steps/1` |
| O2 | `Onboarding 2` (cm, ft) | 2/6 height ruler, ft/in ↔ cm toggle | Height → `decimal(min:120,max:230)` cm or ft/in pickers (digits only) / `confloat(120..230)` | `PUT /me/onboarding/steps/2` |
| O3 | `Onboarding 3` | 3/6 weight kg/lb + goal dropdown | Weight → `decimal(30..250 kg)` (2 decimals) · Goal (dropdown enum; options from `GET /me/goal-options`) | `GET /me/goal-options?weight=&height=`, `PUT /me/onboarding/steps/3` |
| O4 | `Onboarding 4` | 4/6 target weight + healthy BMI hint + medical conditions search | Target weight → `decimal(30..250)` · Condition search → `search()`/`SafeSearchQuery` (local filter of ref list; no free text stored) | `PUT /me/onboarding/steps/4` |
| O5 | `Onboarding 5` | 5/6 age + activity level (4 options) | Age → `integer(18..100)` digits only · Activity (enum) | `PUT /me/onboarding/steps/5` |
| O6 | `Onboarding 6`, `6-1` | 6/6 body type carousel (3); chosen name in info text; then "Your avatar is ready" summary, Save my avatar / Edit Details | Body type (enum) | `PUT /me/onboarding/steps/6`, `POST /calculations/preview`, `POST /me/onboarding/complete` |
| O7 | `Generating your health profile…`, `Final page` ("Saved Details · Redirecting") | Progress / success | — | — |

### 2.3 Home — Hydration (`Home/Water*`, `Section 2`, `Home Page` board)

| # | Frame | Purpose | Input fields → validator | API calls |
|---|---|---|---|---|
| H1 | `Home/Water` + state variants (0 %, 84 %, 80 %, Goal Completed, Above Goal, Day ending soon, disabled/nudge) | Water avatar card, Add Water/Drink, Share, Info, ⋮ | — (swipe gesture ±100 mL) | `GET /hydration/status`, `POST /hydration/intakes` |
| H2 | Profile Username sheet (over Home) | Prompt to set username ("Set up later") | Username → `username()`/`SafeUsername` + live availability | `GET /usernames/availability`, `PUT /me/username` |
| H3 | `Water Update 2/Add water` | Add Intake — Water tab: amount + presets + Recent Updates | Amount ml → `integer(1..3000)` digits only | `POST /hydration/intakes`, `GET /hydration/intakes?date=` |
| H4 | `Water Update 2/Add other drinks` (+ search, custom, "Banana Shake") | Other Drinks: chips, search, custom drink name, quantity | Drink search → `search()`/`SafeSearchQuery` · Custom drink name → `shortText(max:60)`/`SafeShortText` · Quantity → `integer(1..3000)` | `GET /hydration/drinks`, `POST /hydration/custom-drinks/estimate` (STAR), `POST /hydration/custom-drinks` (STAR), `POST /hydration/intakes` |
| H5 | `Recent Updates / Edit your entry` (water) | Edit one of last 2 entries | Amount `integer(1..3000)` | `PUT /hydration/intakes/{id}`, `DELETE /hydration/intakes/{id}` |
| H6 | `Water/Temperature & Gym` (+ `Filled`) | Temperature wheel (°C/°F), activity chips, duration presets | Temperature → wheel (15–40 °C / 59–104 °F; no typing) · Duration → `integer(1..600)` | `PUT /hydration/temperature`, `POST /workouts` (STAR, OQ-04) |
| H7 | `Water/Info` | Static explainer + disclaimer | — | — |

### 2.4 Home — Nutrition (`Home/Nutrition*`, `Search`, `Save Meal`, `On press`)

| # | Frame | Purpose | Input fields → validator | API calls |
|---|---|---|---|---|
| N1 | `Home/Nutrition` | Meal avatar "1450 kcal of 2000 kcal", Add Food | — | `GET /nutrition/daily-summary?date=` |
| N2 | `On press` / `Premium plan features` | Today's Nutrition sheet: 6 nutrients + upsell, or all 17 (STAR) | — | `GET /nutrition/daily-summary` |
| N3 | `Nutrition Update-2` (Add Meal) | Search bar (mic, barcode icons), Recent chips, Add Items list with qty stepper + unit dropdown + delete, Save Meal, View Nutrition Summary | Search → `search()`/`SafeSearchQuery` (1–64) · Quantity → `decimal(0.25..20, step 0.25)` · Unit (enum from food units) | `GET /foods/search`, `GET /foods/{id}`, `GET /meals/recent` |
| N4 | `Home/Search` | Search results list (+ add) | as N3 | `GET /foods/search` |
| N5 | `Nutrition Update` (voice) | "Listening for ingredients…", transcript, Try saying… | Transcript (from STT, not typed) → `freeText(max:300)` / `SafeText(300)` | `POST /nutrition/voice/parse` (STAR) |
| N6 | `Nutrition Update-1` (barcode) | Camera frame, "Or add manually" product name/barcode, Item found, Estimated nutrients, Add to Meal, Scan Another | Manual entry → `barcodeOrSearch()` (digits 8–14 → `SafeBarcode`; else `SafeSearchQuery`) · Quantity `decimal` | `GET /foods/barcode/{code}` (STAR) |
| N7 | `Nutrition Update-3` | Nutrition Summary (6/17) + Unlock STAR + Update Meal | — | `POST /meals` or `PUT /meals/{id}` |
| N8 | `Save Meal` | Confirm items, Save Meal (+ meal-type chip, OQ-18) | Saved-meal name (optional) → `shortText(max:60)`/`SafeShortText` | `POST /meals`, `POST /saved-meals` |
| N9 | `Nutrition Update/Recent` | Recent Updates, Saved Meals, Last 2 Updates (edit) | — | `GET /meals/recent`, `GET /saved-meals` |
| N10 | `Nutrition/Edit` | Edit entry (last 2) | Quantity `decimal` | `PUT /meals/{id}`, `DELETE /meals/{id}` |
| ~~N11~~ | ~~`Nutrition Update/Request new food`~~ | **Removed** (hidden frame, not in DOC; OQ-63) | Food Name → `shortText(max:80)`/`SafeShortText` · Description → `freeText(max:500)`/`SafeText(500)` · Restaurant/Brand (optional) → `shortText(max:80)`/`SafeShortText` | `POST /food-requests` |
| N12 | `Nutrition/Info` | Static explainer + disclaimer | — | — |

### 2.5 Home — Sleep (STAR) (`Home Page` board, Sleep frames)

| # | Frame | Purpose | Input fields → validator | API calls |
|---|---|---|---|---|
| SL1 | Sleep avatar (STAR) / blurred "Unlock your Sleep Avatar" (STANDARD) | 8h 02m, score % | — | `GET /sleep/summary?date=` (403 → upsell) |
| SL2 | `Today's Sleep` | start, wake, goal, achieved, score label | — | `GET /sleep/summary` |
| SL3 | `Update Sleep` | Sleep time + wake time wheels (am/pm), night wakings (add) | Time wheels (no typing); server validates order and ≤ 16 h | `POST /sleep/entries`, `PUT /sleep/entries/{id}` |
| SL4 | Sleep `Information` | Static explainer | — | — |

### 2.6 Care Circle (`Care Circle 5`, `Care Circle 9`, circle frames in PDF)

| # | Frame | Purpose | Input fields → validator | API calls |
|---|---|---|---|---|
| C1 | `Your Circles` (empty: Create a Care Circle) | List circles + Invites section | — | `GET /circles`, `GET /circle-invites` |
| C2 | Username sheet (when creating without username) | as H2 | `username()` | as H2 |
| C3 | `Create a Circle` | Circle name, Add Members | Circle name → `shortText(max:50)`/`SafeShortText` | — |
| C4 | `Add Members` (People on NaraaCare / Invite Link) | Search by username, connected list, Share Invite Link | Search → `usernameSearch()`/`SafeSearchQuery` | `GET /people/search`, `GET /connections` |
| C5 | `Share with Gym Buddies` | Choose ≥ 1 avatar (Hydration, Nutrition, Sleep STAR) | checkboxes; Create disabled until ≥ 1 | `POST /circles` |
| C6 | `Care Circle 5/Home page` (Gym Buddies) | Members strip, Circle Chat card, Recent Updates | — | `GET /circles/{id}`, `GET /circles/{id}/feed` |
| C7 | Circle chat | Messages, @mentions, Type here.. | Message → `chatMessage(max:2000)`/`SafeChatMessage` | `GET /circles/{id}/messages`, `POST /circles/{id}/messages`, WebSocket |
| C8 | Invite detail ("You are invited to join Gym Buddies") | Join Circle / Decline / Maybe Later (link flow) | — | `POST /circle-invites/{id}/accept|decline|later`, `POST /invite-links/resolve` |
| C9 | `All Members` / `Manage Members` | Admins, Members, Invited; search | Search `usernameSearch()` | `GET /circles/{id}/members` |
| C10 | Member profile (`@sahil.123` View Profile) | Shared avatars; "not shared"; Sleep STAR-only | — | `GET /circles/{id}/members/{userId}/avatars` |
| C11 | Circle `Notifications` | Mentions, joins, goal completions | — | `GET /notifications?circle_id=` |
| C12 | Circle `Settings` (+ leave dialog) | Manage/Add members, Your shared avatars, Notifications, Leave | — | `PUT /circles/{id}/shares`, `POST /circles/{id}/leave` |
| C13 | Circle `Profile` (wallpaper + name) | Select wallpaper, rename | Circle name `shortText(max:50)` · wallpaper (enum) | `PATCH /circles/{id}` |
| C14 | `Member` (admin) | View shared avatars, Remove from circle | — | `DELETE /circles/{id}/members/{userId}` |
| C15 | Circle `Notification Settings` | 5 toggles | toggles | `PUT /circles/{id}/notification-settings` |

### 2.7 Rin AI (`Rin AI`, `Rin AI-1`, `Rin AI/Start`)

| # | Frame | Purpose | Input fields → validator | API calls |
|---|---|---|---|---|
| R1 | `Rin AI-1` Unlock Rin AI (STANDARD) | Upsell | — | — |
| R2 | Rin start | Greeting + 4 suggested prompts | Prompt box → `chatMessage(max:2000)`/`SafeChatMessage` | `POST /rin/conversations`, `POST /rin/conversations/{id}/messages` (SSE) |
| R3 | Rin conversation (+ meal estimate card: Add to Avatar / Edit / Not Now) | Chat; action card | as R2 | `POST /rin/actions/{id}/accept`, `/dismiss` |
| R4 | Rin menu: Search History, Delete Chat, Help; delete dialog + toast | — | — | `DELETE /rin/conversations/{id}` |
| R5 | `Search in Rin AI` | Recent searches, conversations | Search → `search()`/`SafeSearchQuery` | `GET /rin/conversations?q=` |
| R6 | `Rin AI help` | About + disclaimer | — | — |

### 2.8 Profile (`Profile`, `Profile.pdf`, PDF frames)

| # | Frame | Purpose | Input fields → validator | API calls |
|---|---|---|---|---|
| P1 | `Profile` | Avatar, @username, STAR badge, counts (Connected, Streak, Care circles) | — | `GET /me`, `GET /me/streak` |
| P2 | `Connections` (My Connections / Find People, Invites, Suggested) | Connect / Decline | Search `usernameSearch()` | `GET /connections`, `GET /people/search`, `GET /people/suggestions`, `POST /connections/requests`, accept/decline |
| P3 | Personal `Notifications` | List | — | `GET /notifications`, `POST /notifications/{id}/read` |
| P4 | `Active Streak` (+ calendar, Streak Broken) | Current/longest, month calendar | Month picker | `GET /me/streak?month=` |
| P5 | `Download Report` (STANDARD / STAR) | Monthly vs Custom | Month picker | `POST /reports`, `GET /reports/{id}` |
| P6 | `Customize Report` | Range presets, From/To dates, sections | Dates → date picker (no typing) | `POST /reports` |
| P7 | `Report Preview`, `Report Downloaded` | Summary, Download, Share | — | `GET /reports/{id}` |

### 2.9 Settings (`Settings`, PDF frames)

| # | Frame | Purpose | Input fields → validator | API calls |
|---|---|---|---|---|
| ST1 | `Settings` | Menu | — | — |
| ST2 | `Edit Profile` | Name, sex, age, height, weight, target, goal, conditions, activity, body type, BMI (read-only), goal pace | Name `name()` · Age `integer(18..100)` · Height/weight/target `decimal` · enums | `GET /me`, `PATCH /me/profile`, `GET /me/goal-options` |
| ST3 | `Username` | Change (once/90 days) | `username()`/`SafeUsername` | `PUT /me/username` |
| ST4 | `Account` | Email (read-only), change password, Delete Account | Current/new password `password()` | `POST /auth/password/change`, `POST /privacy/deletion-request` |
| ST5 | `Notification Settings` | Toggles (goal completions, streaks, insights STAR, hydration/nutrition/sleep reminders, daily check-in, connection requests/activity, reports ready, subscription) | toggles + reminder times | `GET/PUT /me/notification-preferences`, `GET/PUT /me/reminders` |
| ST6 | `My Subscriptions` (STANDARD view, Monthly/Yearly) | Plans | — | `GET /billing/plans`, `GET /billing/subscription` |
| ST7 | `Upgrade to STAR` → store sheet → "You're now on STAR plan" | Purchase | — | store SDK → `POST /billing/purchases/verify` |
| ST8 | `My Subscriptions` (STAR), `Billing History`, `Cancel Subscription`, `Subscription Cancelled` | Manage | — | `GET /billing/history`; cancel → deep link to store management |
| ST9 | `Refer 5 Friends` (STANDARD 30 days / STAR 50 days) | Code, link, progress | — | `GET /referrals/me` |
| ST10 | `Help & support`, `FAQs`, `Contact Support`, `Guide` | Static + search | FAQ search `search()` | `GET /support/faqs` |
| ST11 | `Report a Problem` | Category chips, description, screenshot upload (PNG/JPG ≤ 10 MB) | Description `freeText(max:2000)`/`SafeText(2000)` · file name → `SafeFileName` (server) | `POST /support/tickets` (multipart) |
| ST12 | `Request a Feature` | What + how it helps | What `shortText(max:120)`/`SafeShortText` · How `freeText(max:1000)`/`SafeText(1000)` | `POST /support/feature-requests` |
| ST13 | `Terms & Conditions`, `Privacy Policy`, `Licenses` | Versioned documents | — | `GET /reference/policies` |
| ST14 | Log Out confirm | — | — | `POST /auth/logout` |

### 2.10 Screens removed or pending (decisions in doc 00)

| Frame | Status |
|---|---|
| `Payments & Billing`, `Add Payment Method` (UPI, Card, Netbanking, Wallets), `Payment` card form, `Plan/Duration/Summary/Pay` (all hidden) | **Removed** — store billing only (OQ-07) |
| `Add Intake → Describe your meal → Analyse (0/4 credits)` (`Home/Nutrition Update/Analyse and Update`, hidden) | **Removed** (OQ-08 closed) |
| `Home/Nutrition Update/ Request new food` (hidden) | **Removed** (OQ-63) |
| Sign-up `Referral` and `Mobile Verification` frames, Sign Up `Full Name` / `Mobile` fields (hidden) | **Not built** — referral code arrives only through the invite/referral deep link (OQ-65, OQ-31) |
| Old top-level `Home/*`, `Profile`, `Settings`, `Edit`, `Reminders`, `Subscription`, `Refer/*`, `Care circle`, `Open AI Chatbot *Rin*`, `Info Tip` frames (hidden) | **Ignored** — superseded by the visible section frames |
| Account `Mobile Number`, Edit Profile `Date of birth` | **Removed** (OQ-31) |
| Blocked people / Accessibility / Languages (sticky note) | Blocked people built in S12; others later (OQ-52) |

---

## 3. Global UI rules

- Every `TextFormField` uses an `InputValidators` function **and** `maxLength` **and** input formatters (numbers use `FilteringTextInputFormatter`). Rejected input shows "Please use letters, numbers and basic punctuation only." — never echoes the input.
- User text is rendered with `Text` only; no WebView, no HTML rendering, no `Linkify` of user content.
- Units: stored metric; display per user preference (cm or ft/in, kg or lb, °C or °F).
- Empty, loading, error and offline states exist for every list/screen (offline banner + queued indicator on logs).
- All tier-gated actions show the upsell sheet when the server returns `403 UPGRADE_REQUIRED`.
