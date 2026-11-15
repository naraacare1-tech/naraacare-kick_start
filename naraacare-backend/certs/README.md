# Apple root certificate (Session 11)

`APPLE_ROOT_CA_PATHS` points here. Download **Apple Root CA - G3** (`AppleRootCA-G3.cer`) from
https://www.apple.com/certificateauthority/ and place it in this folder (or mount it in the
deployment), then compare its SHA-256 with the value Apple publishes on that page before use.

It is a public certificate (not a secret) used to verify App Store signed transactions and
App Store Server Notifications (`app/integrations/app_store.py`). Without it, dev runs with iOS
purchase verification disabled; staging and prod refuse to start (`Settings` check).
