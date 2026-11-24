# Hosting the backend on this Windows PC

The API runs on this PC and the internet reaches it at `https://api.naraacare.com` through Cloudflare Tunnel. This setup is for **testing only** (`APP_ENV=dev`, mobile `CERT_PINS` empty). Real users go on the Hostinger KVM 2 later (Ubuntu; same steps as [hosting-oracle-free.html](hosting-oracle-free.html)). Why: the mobile app pins the server's own certificate key, and Cloudflare's free certificate key can change at any time.

Scripts: [naraacare-backend/deploy/windows/](../naraacare-backend/deploy/windows/)

| Script | What it does |
|---|---|
| `install-tasks.ps1` | Run once as admin. Creates the scheduled tasks below, starts them, and turns off sleep and hibernate while plugged in. `-Remove` deletes the tasks again. |
| `run.ps1 -Service api` | Starts uvicorn on `127.0.0.1:8000` as one process and restarts it if it stops. |
| `run.ps1 -Service worker` | Starts `tools/dev_worker.py` as `app_worker`, using the password in `naraacare-database/.env`. |
| `backup-db.ps1` | `pg_dump` of the database plus a zip of `var/storage`, saved to `D:\NaraaCare-backups` and kept for 14 days. |

Tasks: `NaraaCare-API` and `NaraaCare-Worker` start at boot. `NaraaCare-Backup` runs nightly at 02:30. All of them run as your Windows user whether or not you are signed in. Logs are in `naraacare-backend\var\logs\`.

## 1. Start the backend on boot

PowerShell opened with **Run as administrator**:

```powershell
cd "D:\Naara Care\naraacare-backend\deploy\windows"
.\install-tasks.ps1
curl.exe http://localhost:8000/api/v1/health/ready     # {"status":"ok","checks":{"database":"ok"}}
```

PostgreSQL 18 is already a Windows service set to Automatic. If the API starts before the database is ready, `run.ps1` retries every 10 s.

Stop the tasks before you run your own `--reload` dev server on port 8000: `Stop-ScheduledTask NaraaCare-API`. Start them again afterwards with `Start-ScheduledTask NaraaCare-API`.

## 2. Move the domain's DNS to Cloudflare (free plan)

1. Sign in at dash.cloudflare.com → **Add a domain** → `naraacare.com` → Free plan.
2. Cloudflare copies your current DNS records. **Compare them with your registrar's list before you continue.** Keep every record for the website (`www`, `@`) and for email (`MX`, `TXT`/SPF, DKIM, DMARC), or the site and info@naraacare.com mail stop working.
3. At your registrar, replace the nameservers with the two Cloudflare gives you. It can take up to 24 h to switch.

## 3. Create the tunnel

1. Install cloudflared (Apache-2.0 licence):
   ```powershell
   winget install --id Cloudflare.cloudflared
   ```
2. In Cloudflare: **Zero Trust → Networks → Tunnels → Create a tunnel → Cloudflared**, name it `naraacare-pc`.
3. Choose Windows, copy the `cloudflared.exe service install <token>` command, and run it in an admin PowerShell. The tunnel now runs as a Windows service and starts at boot.
4. **Public hostname**: subdomain `api`, domain `naraacare.com`, service `HTTP` → `localhost:8000`. Save.
5. Check from any network: `curl.exe https://api.naraacare.com/api/v1/health/live` should return `{"status":"ok"}`.

WebSockets (circle chat) work through the tunnel without extra settings.

If the newer dashboard has no "Public hostname" tab, open the tunnel, go to **Routes → Add route → Published application**, and enter the same values.

**`DNS_PROBE_FINISHED_NXDOMAIN` right after setup:** the internet provider's DNS still remembers the old Hostinger nameservers, which can last up to 48 h. Fix it on this PC: set Windows DNS to `1.1.1.1` / `1.0.0.1` (Settings → Network → your connection → DNS server assignment → Manual) and run `ipconfig /flushdns`. Then in Chrome, open `chrome://net-internals/#dns` → **Clear host cache**.

## 4. Backend settings (`naraacare-backend/.env`)

- `ALLOWED_HOSTS` already includes `api.naraacare.com`.
- Keep `APP_ENV=dev`. Staging and prod need the store, FCM and Apple keys, and an SSL database connection; see [env-variables-guide.md](env-variables-guide.md).
- `/docs` is now public. Either set `API_DOCS_ENABLED=false`, or set `API_DOCS_BASIC_AUTH=user:password`.
- Restart the API after any change: `Stop-ScheduledTask NaraaCare-API; Start-ScheduledTask NaraaCare-API`.

## 5. Point a real phone at it

`naraacare-mobile/env/dev-tunnel.env` is a copy of `dev.env` with:

```
API_BASE_URL=https://api.naraacare.com/api/v1
WS_BASE_URL=wss://api.naraacare.com/api/v1/ws
CERT_PINS=
```

Build an installable Android APK from `naraacare-mobile`. Use the 8.3 short Flutter path; see that README's Windows note.

```powershell
flutter build apk --release --flavor dev -t lib/main_dev.dart --dart-define-from-file=env/dev-tunnel.env
# -> build\app\outputs\flutter-apk\app-dev-release.apk
```

The APK is signed with the debug key until release signing exists (Session 17). It is fine to install directly on test phones, but never upload it to Play. `dev.env` stays on `http://10.0.2.2:8000` for the emulator.

iPhone builds need a Mac with Xcode and an Apple Developer account; they cannot be built on Windows.

## 6. Keeping it running

- **Power cuts:** use a UPS. The tasks and the tunnel start again by themselves after a reboot.
- **Windows Update:** set Active hours (Settings → Windows Update → Advanced) so restarts happen at night.
- **Internet outages:** add a free uptime check (for example UptimeRobot) on `https://api.naraacare.com/api/v1/health/ready`. The worker cannot alert you when the PC itself is offline (see [owner-alerts.md](owner-alerts.md)).
- **Backups:** copy `D:\NaraaCare-backups` off this PC regularly.

## 7. Moving to the Hostinger KVM 2 later

1. Run the Ubuntu steps in [hosting-oracle-free.html](hosting-oracle-free.html) on the KVM 2.
2. Copy the newest `naraacare_*.dump` over and restore it: `pg_restore -U postgres -d naraacare --clean --if-exists <file>.dump`. Unzip `storage_*.zip` into the server's storage folder.
3. In Cloudflare DNS, delete the tunnel's `api` record and add an `A` record `api` → the KVM 2's IP with the proxy **off** (grey cloud), so the server's own Let's Encrypt certificate is what phones see. Get that certificate with certbot.
4. Set `APP_ENV=prod` and the production values, and put the server's key pins in the mobile release build's `CERT_PINS`.
5. Turn this PC off as a server: `.\install-tasks.ps1 -Remove`, and delete the tunnel in Cloudflare.
