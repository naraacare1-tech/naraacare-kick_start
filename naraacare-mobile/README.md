# naraacare-mobile

Flutter app for NaraaCare (**Android + iOS only**). Flutter **3.47.7** / Dart **3.13.5**, Riverpod, go_router, dio.
Design docs: `docs/02-screen-inventory.md`, `docs/03-system-architecture.md` §3, `docs/07-security-architecture.md` §4.3 + §7, `docs/08-environment-and-config.md` §4.

## Layout

```
lib/
  main_dev.dart | main_staging.dart | main_prod.dart   flavor entry points → bootstrap(Flavor.x)
  bootstrap.dart        validates config (fails fast), starts ProviderScope
  app.dart              root widget (env ribbon on non-prod)
  core/config/          Flavor, AppConfig (from --dart-define-from-file), providers
  core/{theme,routing,network,errors,security,storage,sync,l10n,utils}/   (Session 06)
  features/<feature>/{data,domain,presentation}/                            (Session 07+)
  shared/widgets/       NcTextField and other shared widgets                (Session 06)
test/                   unit + widget tests; test/security/ = source rules + shared payload list
integration_test/       E2E (patrol, Session 07+)
tool/ios/setup_flavors.rb   one-time iOS flavor setup (run on a Mac)
env/test.env            committed dummy config for tests/CI;  env/<flavor>.env are git-ignored
```

## Flavors

| Flavor | Android applicationId | iOS bundle ID | App name | Entry point |
|---|---|---|---|---|
| dev | `com.naraacare.app.dev` | `com.naraacare.app.dev` | NaraaCare Dev | `lib/main_dev.dart` |
| staging | `com.naraacare.app.staging` | `com.naraacare.app.staging` | NaraaCare Staging | `lib/main_staging.dart` |
| prod | `com.naraacare.app` | `com.naraacare.app` | NaraaCare | `lib/main_prod.dart` |

## Setup and run

```bash
cp .env.example env/dev.env          # non-secret values; edit API_BASE_URL if needed
flutter pub get --enforce-lockfile
flutter run --flavor dev -t lib/main_dev.dart --dart-define-from-file=env/dev.env
```
The app refuses to start if the config is unsafe (e.g. `http://` API outside dev, missing `CERT_PINS` outside dev, env file built for another flavor).

**iOS (one time, on a Mac):** `gem install xcodeproj -v 1.27.0 && ruby tool/ios/setup_flavors.rb`, add the configuration mapping printed in the script header to `ios/Podfile`, then `cd ios && pod install`. Commit the result.

## Test and quality gates (same as CI)

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test --dart-define-from-file=env/test.env
```
`test/security/source_rules_test.dart` fails the build on raw `TextField`/`TextFormField` (use `NcTextField`), `print()`/`debugPrint()` outside `AppLogger`, colour literals outside `tokens.dart`, invisible/bidi characters, WebView/HTML packages, or secret-looking values in env files.

**Generated code** is committed; regenerate after editing ARB files or drift tables (CI fails if it is stale):
```bash
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
```
The local database is SQLCipher, compiled by the `sqlite3` build hook (`hooks: user_defines: sqlite3: source: sqlcipher` in `pubspec.yaml`); the first build needs a C toolchain (Xcode / Android NDK / MSVC on Windows for tests). Fonts are bundled Manrope (OFL, `assets/fonts/manrope/`).

### Windows note: space in the Flutter SDK path

If Flutter is installed under a path with a space (e.g. `C:\Users\First Last\flutter`), `flutter test`/`build` fails while building native assets (`'C:\Users\First' is not recognized…`). Call Flutter through the 8.3 short path, e.g. in PowerShell:
```powershell
$short = (New-Object -ComObject Scripting.FileSystemObject).GetFolder("$env:USERPROFILE\flutter").ShortPath
& "$short\bin\flutter.bat" test --dart-define-from-file=env/test.env
```
or move the SDK to a path without spaces (e.g. `C:\dev\flutter`).

## Environment variables (all non-secret — they ship inside the app)

| Key | Example | Description |
|---|---|---|
| `ENV_NAME` | `dev` | must match the flavor entry point |
| `API_BASE_URL` | `https://api.dev.naraacare.app/api/v1` | `https://` required (dev may use `http://10.0.2.2`/`localhost`) |
| `WS_BASE_URL` | `wss://api.dev.naraacare.app/api/v1/ws` | `wss://` required (same dev exception) |
| `CERT_PINS` | `sha256/AAAA…=,sha256/BBBB…=` | SPKI pins (current + backup); required outside dev |
| `GOOGLE_SERVER_CLIENT_ID` | `…apps.googleusercontent.com` | Google sign-in ID-token audience |
| `TERMS_URL`, `PRIVACY_URL` | `https://naraacare.app/terms` | fallback legal links |

Never put API keys or secrets in these files — everything compiled into the app can be extracted. Firebase config files and signing keys are injected by CI and are git-ignored.

## Security defaults already in place

- Android: `allowBackup=false`, data-extraction rules exclude everything, cleartext blocked (`network_security_config.xml`; dev flavor allows only `10.0.2.2`/`localhost`), user-installed CAs not trusted.
- iOS: App Transport Security left at its secure default (no exceptions).
- Release signing and obfuscation (`--obfuscate --split-debug-info`) are wired in Session 17; until then release builds use debug keys and must not be uploaded.
