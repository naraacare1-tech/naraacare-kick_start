# Email / OTP setup

The backend sends the signup and password-reset OTP codes by email. Where they go depends on `EMAIL_BACKEND` in `naraacare-backend/.env`.

## Status of this PC (checked 2026-11-03)

| Item | Status |
|---|---|
| `EMAIL_BACKEND` | `outbox`: no real email is sent. Each OTP is written to a file (option A). |
| SMTP (`SMTP_*`) | **Not set.** Needed only for real email (option B). |

## Option A: read the OTP from the outbox (dev default, no setup)

Each email is saved as an `.eml` file in `naraacare-backend/var/outbox/`, named `otp_verification-<id>.eml`. Nothing reaches a real inbox, so it does not matter which email address you sign up with.

After you sign up (or tap resend), print the newest code. Run this from `naraacare-backend/`:

```bash
grep -oE '\b[0-9]{6}\b' "$(ls -t var/outbox/*.eml | head -1)" | head -1
```

Or open the newest `.eml` file in VS Code and read the code from it. Codes expire after a few minutes; tap resend in the app to get a new one.

## Option B: send real email through Gmail

1. Turn on 2-Step Verification for the Gmail account, then create an **app password** at https://myaccount.google.com/apppasswords. Your normal Gmail password does not work.
2. Set these in `naraacare-backend/.env`. Type the app password in yourself, and never commit it:
   ```
   EMAIL_BACKEND=smtp
   SMTP_HOST=smtp.gmail.com
   SMTP_PORT=587
   SMTP_USERNAME=<your Gmail address>
   SMTP_PASSWORD=<16-character app password>
   EMAIL_FROM_ADDRESS=<same Gmail address>
   ```
   Where each value comes from:

   | Key | Value | Where it comes from |
   |---|---|---|
   | `SMTP_HOST` | `smtp.gmail.com` | Fixed. It is Gmail's mail server, the same for every Gmail account. |
   | `SMTP_PORT` | `587` | Fixed. Gmail's port for sending with TLS (already set in `.env`). |
   | `SMTP_USERNAME` | your full Gmail address | The account where you created the app password. |
   | `SMTP_PASSWORD` | the 16-character code | Shown **once** by Google when you create the app password (step 1). If you lost it, delete that app password and create a new one. |
   | `EMAIL_FROM_ADDRESS` | same Gmail address | Gmail only sends from the signed-in address, so use the same one. |

   The app password's name (for example "Naaracare") is only a label in your Google account. It does not go in `.env`.
3. Restart the backend. It reads `.env` only at startup, so `--reload` does not pick up `.env` changes.
4. Sign up with an address you can actually open. Addresses like `test@gmail.com` belong to real people, so their codes would go to a stranger.

Gmail limits how much you can send each day, so it is fine for testing only. Before going live, use a proper email provider and put its SMTP details in the same keys. Staging and prod refuse to start unless `EMAIL_BACKEND=smtp` and `SMTP_HOST` is set.

To switch back to the outbox, set `EMAIL_BACKEND=outbox` and restart.
