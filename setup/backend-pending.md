# Backend: pending items to run it locally

Checked on 2026-11-02 by starting the API (`uvicorn`) against the local database.

## Current status

| Item | Status |
|---|---|
| Python 3.13.17 + dependencies (`.venv`) | ✅ Installed |
| uv 0.13.6 | ✅ Installed and on PATH (checked 2026-11-02) |
| PostgreSQL `naraacare` database | ✅ Migrated, `/health/ready` reports `database: ok` |
| `naraacare-backend/.env` | ✅ Created from `.env.example` (dev values work as they are) |
| API starts | ✅ `/health/live` → `{"status":"ok"}`, `/reference/bootstrap` → 200 |
| Redis | ⏸️ **Deferred** until there are many users. The API runs without it (see step 2) |

## Pending

### 1. uv on PATH: just restart VS Code

uv is at `C:\Users\Sankalp Tiwari\.local\bin\uv.exe`, the standard location the uv installer uses. Don't move it. That folder is already in the Windows user PATH; the terminals open now started before it was added. Close and reopen VS Code, then check it with `uv --version`.

(An extra copy is in `AppData\Roaming\Python\Python311\Scripts\uv.exe`, from `pip install --user uv`. It is not on PATH and does no harm; delete it if you want, with `pip uninstall uv`.)

### 2. Redis (deferred)

For now the backend runs without Redis. `.env` uses a fail-fast URL, so each request gives up on Redis in 0.05 s instead of waiting about 8 s. Measured: a request takes about 0.4 s.

```
REDIS_URL=redis://127.0.0.1:6379/0?socket_connect_timeout=0.05&socket_timeout=0.05
```

What you lose without Redis (all of it fails open, so nothing errors):
- no rate limits (no per-IP brute-force or spam protection). Account lockout still works, because it lives in the database: after 4 wrong passwords, login returns 423 (locked);
- after logout, the access token keeps working for up to 15 minutes (refresh tokens are still revoked);
- no entitlement cache (every request reads the database);
- `/health/ready` returns 503, so don't use it as a deploy health check yet;
- the background worker (`taskiq`) cannot start, so scheduled jobs such as reminders, partitions and retention don't run.

**Before going live with real users, install Redis.** There is no WSL on this machine, so use one of these:
- **Memurai Developer** (Redis-compatible, native Windows service): install it, and it runs on `localhost:6379` automatically. **This is the easiest option.**
- Or install WSL (`wsl --install`, then restart), and run `sudo apt install redis-server` inside Ubuntu.

Then set `REDIS_URL=redis://localhost:6379/0` back in `.env`.

### 3. Run

```bash
cd "/d/Naara Care/naraacare-backend"
uv run python -m uvicorn app.main:create_app --factory --reload --no-access-log
```

Check: http://localhost:8000/api/v1/health/live should return `{"status":"ok"}`.
If it fails with `Failed to spawn: uvicorn ... An Application Control policy has blocked this file (os error 4551)`, you typed `uv run uvicorn`. Windows Smart App Control blocks the small `.exe` launchers in `.venv\Scripts` (`uvicorn.exe`, `pytest.exe`, `taskiq.exe`). Always use `uv run python -m <tool>` as shown above; Python itself is allowed. Don't switch Smart App Control off: once it is off, Windows can only turn it back on with a full reset.
If it fails with `[Errno 10048] ... only one usage of each socket address`, a backend is already running on port 8000. Stop that one first, or add `--port 8001`.
(After Redis is installed, also start the worker in a second terminal with `uv run python -m taskiq worker app.workers.broker:broker`, and `/health/ready` should report `database: ok` and `redis: ok`.)

## Optional: only for features that call outside services

**Done for now:** every key below already has a placeholder value in `.env` (for example `dummy-not-a-key`, `{"type":"dummy"}`), and the API starts with them. Replace them with real values later, when you need the feature:

| Feature | `.env` keys |
|---|---|
| Google sign-in | `GOOGLE_OAUTH_CLIENT_IDS`. See [sign-in-and-jwt-setup.pdf](sign-in-and-jwt-setup.pdf). |
| Apple sign-in | `APPLE_*`, `APPLE_SIWA_PRIVATE_KEY_P8`. See [sign-in-and-jwt-setup.pdf](sign-in-and-jwt-setup.pdf). |
| Rin AI chat | `ANTHROPIC_API_KEY` |
| Push notifications | `FCM_SERVICE_ACCOUNT_JSON` (Firebase project still to be created) |
| Store purchases | `GOOGLE_PLAY_*`, `APP_STORE_*` |
| iOS purchase verification | `APPLE_ROOT_CA_PATHS`: put `AppleRootCA-G3.cer` in `naraacare-backend/certs/` (see `certs/README.md`). Dev runs without it; **staging and prod refuse to start without it.** |
| Real email | `EMAIL_BACKEND=smtp` + `SMTP_*` (dev writes emails to `var/outbox/` as `.eml` files instead). See [email-otp-setup.md](email-otp-setup.md). |

Dev notes: no JWT keys are set, so a temporary key is generated each time the API starts and you have to sign in again after every restart. This is expected in dev.

Every variable in every `.env` file, what it does and how to get its value: [env-variables-guide.pdf](env-variables-guide.pdf) (source text: [env-variables-guide.md](env-variables-guide.md)).
