# Deep-link domain files (Session 11)

Templates for the landing site (not this app): serve them at
`https://<REFERRAL_LINK_DOMAIN>/.well-known/assetlinks.json` and
`https://<REFERRAL_LINK_DOMAIN>/.well-known/apple-app-site-association` (no extension,
`Content-Type: application/json`, HTTPS, no redirects), one copy per flavor domain with that
flavor's package name / bundle id.

| Placeholder | Value | Where it comes from |
|---|---|---|
| `REPLACE_WITH_PLAY_APP_SIGNING_SHA256` | SHA-256 of the app signing key | Play Console → App integrity (S17) |
| `REPLACE_WITH_TEAM_ID` | Apple Developer team id | App Store Connect (S17) |

These values are public (they identify the app, they are not secrets). Android reads the link host
from `manifestPlaceholders["referralLinkHost"]` per flavor; iOS needs the Associated Domains
capability `applinks:<domain>` added on a Mac with the team set (pending, see docs/pending-tasks.md).
The app validates every code (`DeepLinkValidator.isInviteCode`) before storing it.
