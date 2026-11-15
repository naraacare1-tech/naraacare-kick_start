# 12 — Lessons from the Old Code

Repository: `D:\naraacare` → `github.com/naraacare1-tech/naraacare` (14 commits, latest "Update Google Script URL").

## 1. What the old repo actually is

It is **not** an earlier version of the app. It is a **Next.js 16 / React 19 marketing landing page** with:
- `app/components/` — Hero, Features, FAQ, CTA, Navbar, Footer (Tailwind 4, framer-motion, lucide icons)
- `app/api/waitlist/route.ts` — a waitlist endpoint that forwards an email to a **Google Apps Script web app** (which presumably writes to a Google Sheet)
- `app/privacy/page.tsx`, `app/terms/page.tsx` — placeholder legal pages
- Git history: EmailJS welcome email added, then removed; "Block duplicate email signups"; the Apps Script URL changed several times

There is no mobile code, no backend domain logic, no database, and no calculations. Nothing is reusable as application code, which is consistent with the rule "reference only; never copy wholesale".

## 2. Keep (ideas, not code)

| Item | How we use it |
|---|---|
| Brand assets (logo, colours, tagline "Personalized health insights for you and the people who care about you") | Cross-check against Figma tokens; the landing site can host deep-link files (`assetlinks.json`, `apple-app-site-association`) and the invite/referral landing page |
| Duplicate-signup prevention intent | Implemented properly as a unique blind index on email (`auth.user_account.email_bidx`) |
| Privacy/Terms routes on the website | Host the versioned legal documents there (`ref.policy_document.url`) once legal drafts them (OQ-47) |
| Existing waitlist list | Import into the launch email campaign **only** if those users consented to be contacted; otherwise discard |

## 3. Avoid (problems found)

| # | Problem in old code | Why it matters | What we do instead |
|---|---|---|---|
| 1 | **Hard-coded Google Apps Script URL** in `route.ts`; earlier URLs remain in git history | Anyone can call that Apps Script directly: an unauthenticated write endpoint into a sheet of personal emails. History cannot be "un-published" | No URLs or credentials in source (doc 08); gitleaks in CI. **Action now:** redeploy the Apps Script under a new deployment, disable the old deployments, and restrict the script to verify a shared secret header (or retire it) |
| 2 | **No input validation**: `const { email } = await req.json(); email.toLowerCase()` | A missing or non-string email crashes with a 500; any string (including markup) is forwarded and stored in the sheet; a sheet opened in a browser/Sheets UI can become an XSS / formula-injection vector (`=HYPERLINK(...)`) | Safe* types on every input (doc 07 §4); CSV/Sheets export guard against formula injection |
| 3 | **Errors reported as success**: unparseable upstream response → `{ success: true }`; on failure it returns HTTP 200 with `success:false` | Silent data loss; the client cannot distinguish failure | Uniform error envelope with correct HTTP status codes (doc 04 §1.1) |
| 4 | **Logging raw upstream responses** (`console.log("Raw response:", text)`) | Can leak PII into hosting logs | structlog with a redaction processor; never log bodies (SEC-7.4) |
| 5 | **No rate limiting / bot protection** on a public form | Spam, list pollution, cost | Per-IP/per-identity rate limits + web application firewall (SEC-3.2) |
| 6 | **No consent record** for waitlist emails; placeholder privacy page | DPDP requires notice + consent tied to a purpose | Versioned consent records (SEC-7.1) |
| 7 | Client-side EmailJS (removed later) | Exposes service keys in the browser bundle; anyone can send mail as you | All email sent server-side over SMTP; no third-party keys in clients |
| 8 | Business logic in a UI framework route, third-party sheet as a database | No transactions, no schema, no audit, no backups | PostgreSQL with schemas, constraints, audit, backups |
| 9 | Floating dependency ranges (`^4`, `^19`, `^12.40.0`) | Non-reproducible builds, supply-chain drift | Exact pins (doc 03 §2) + lockfiles + Dependabot |
| 10 | Commit messages repeated ("logo" ×3, "Block duplicate email signups" ×3) and no PR flow | Hard to audit changes | Conventional commits, PR template, branch protection (doc 09) |
| 11 | Agent instruction file says "This is NOT the Next.js you know" | Unclear source of truth for future contributors | Docs folder + session files are the single source of truth |

## 4. Carry-over checklist

- [ ] Rotate/retire the Apps Script deployments referenced in git history (owner: product, before any public launch announcement).
- [ ] Decide whether the landing page stays on Vercel; if yes, add the deep-link association files and the referral/invite landing route (S11/S12).
- [ ] Export the waitlist sheet, check consent, and delete it afterwards if it is not needed (data minimisation).
- [ ] Align landing page colours/fonts with the Figma tokens confirmed in S06.
