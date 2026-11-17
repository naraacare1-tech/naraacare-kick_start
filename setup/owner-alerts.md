# Owner alerts (info@naraacare.com)

The backend emails `ERROR_ALERT_EMAIL` (set to `info@naraacare.com`) when one of the urgent alerts below triggers. Emails are plain text with counts and error types only, never user data. The same alert is sent at most once every 30 minutes (budget alerts once a day), with at most 30 emails an hour.

Settings: `ERROR_ALERT_EMAIL` and `AI_ACCOUNT_MONTHLY_BUDGET_INR` in `naraacare-backend/.env` (see [env-variables-guide.md](env-variables-guide.md)). Email sending uses the SMTP settings in [email-otp-setup.md](email-otp-setup.md).

| Doc section | Alert | When the email is sent |
|---|---|---|
| 2. Authentication | Sign-up OTP emails not arriving | Any failure sending a code email; or, in the last hour, at least 10 code checks with under 50% correct |
| 2. Authentication | Google/Apple sign-in failing | Over 10% of sign-ins failed in 15 minutes (at least 10 attempts) |
| 6. Rin AI | AI credits or quota low or exhausted | Our monthly AI spend reaches 80% and 95% of `AI_ACCOUNT_MONTHLY_BUDGET_INR`; any 429, 402, insufficient-quota or rejected-key error from OpenAI |
| 6. Rin AI | Rin AI down or very slow | Over 25% of replies failed, or the median reply took over 30 seconds, in 15 minutes (at least 5 replies) |
| 8. Subscriptions | User paid but didn't get STAR | A verified purchase leaves the user without STAR; or the 5-minute check finds an active subscription on a standard user |
| 8. Subscriptions | Payment or receipt validation failing | Play / App Store verification errors, webhook failures, the subscription reconcile job failing |
| 7. Profile | Report PDF generation failing or timing out | A report job failed, AI insights failed, or reports are stuck in the queue (over 15 minutes) |
| 7. Profile | Streak or day-rollover job failed | The reminder or day-ending-soon job failed or missed its schedule; a timezone error |

Where the checks run:

- **API** (counted in memory per process): OTP, sign-in, Rin, AI quota, purchases and webhooks, timezone errors.
- **Worker** (`ops.health_check` every 5 minutes, reads `ops.fn_ops_health`): stuck or failed reports, failed store notifications, paid-without-STAR, the monthly AI budget, missed day jobs.

Not covered yet:

- **Bounce spikes.** These need the bounce webhook of the production email provider; plain SMTP cannot see bounces.
- **Worker down.** The worker cannot alert when it is itself down. Add an outside uptime check when hosting is set up.

Other crashes (unhandled API errors, other failed jobs) are also emailed to the same address.
