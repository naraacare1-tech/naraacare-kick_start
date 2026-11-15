# Frontend setup: run the mobile app

The frontend is the Flutter app in `naraacare-mobile/`. It runs on **Android and iOS only**. It does not run on Chrome or as a Windows desktop app, because the project has no `web/` or `windows/` folder and depends on phone-only plugins such as SQLCipher, secure storage and biometrics.

## Status of this PC (checked 2026-11-02)

| Item | Status |
|---|---|
| Flutter 3.47.7 / Dart 3.13.5 | Installed at `C:\Users\Sankalp Tiwari\flutter`. This is the version the project needs. |
| Android SDK / Android Studio | **Missing.** Install it before you can run the app (step 1). |
| Android emulator (AVD) | **None.** Create one (step 2) or use a real phone. |
| `env/dev.env` | **Missing.** Create it (step 3). |
| Generated code (`*.g.dart`, l10n) | Already committed. You do not need to run codegen. |

## 1. Install Android Studio (one time)

1. Download and install Android Studio from https://developer.android.com/studio
2. Open it and accept the setup wizard. It installs the Android SDK, platform-tools and an emulator image.
3. In **Settings → Languages & Frameworks → Android SDK → SDK Tools**, tick **Android SDK Command-line Tools** and **NDK (Side by side)**, then click Apply. The NDK is required because the first build compiles SQLCipher.
4. Install the Flutter and Dart plugins from **Settings → Plugins** (optional, but useful).
5. In a new terminal, run:
   ```powershell
   flutter doctor --android-licenses   # answer y to all
   flutter doctor                      # "Android toolchain" should now show [√]
   ```
   If Flutter cannot find the SDK, run `flutter config --android-sdk "C:\Users\Sankalp Tiwari\AppData\Local\Android\Sdk"`.

You can ignore the "Visual Studio" warning in `flutter doctor`. It only matters for Windows desktop apps.

## 2. Get a device

**Emulator:** in Android Studio, open **Device Manager → Create Virtual Device**, pick a phone (for example Pixel 8) and a recent system image, then press ▶ to start it.

You can also do it from the terminal:
```powershell
flutter emulators                      # list emulators
flutter emulators --launch <emulator_id>
```

**Real Android phone:** turn on **Developer options → USB debugging**, connect the phone by USB and accept the prompt on the phone.

Check that the device is visible:
```powershell
flutter devices                        # an "android" device must appear in the list
```

## 3. Create the dev config file (one time)

```powershell
cd "D:\Naara Care\naraacare-mobile"
Copy-Item .env.example env\dev.env
```

The defaults point to a backend on your PC:

```
API_BASE_URL=http://10.0.2.2:8000/api/v1
WS_BASE_URL=ws://10.0.2.2:8000/api/v1/ws
```

`10.0.2.2` is how the **Android emulator** reaches `localhost` on your PC. On a **real phone**, use one of these instead:
- your PC's LAN IP address (for example `http://192.168.1.20:8000/api/v1`), with the phone on the same Wi-Fi network, or
- `adb reverse tcp:8000 tcp:8000` and then `http://localhost:8000/api/v1`.

The dev flavor allows plain `http://` only for `10.0.2.2` and `localhost`, so the `adb reverse` option is the simplest way to test on a phone.

This file goes into the app binary. Never put secrets in it. `env/*.env` is git-ignored.

## 4. Start the backend (needed for login and data)

The app opens without the backend, but API calls fail. Start the backend in another terminal by following `naraacare-backend/README.md` and `setup/database-setup.md`:

```powershell
cd "D:\Naara Care\naraacare-backend"
uv run python -m uvicorn app.main:create_app --factory --reload --no-access-log
# check: http://localhost:8000/api/v1/health/live  →  {"status":"ok"}
```

## 5. Run the app

```powershell
cd "D:\Naara Care\naraacare-mobile"
flutter pub get --enforce-lockfile
flutter run --flavor dev -t lib/main_dev.dart --dart-define-from-file=env/dev.env
```

If more than one device is connected, add `-d <device_id>` (the ID comes from `flutter devices`).

The first build takes several minutes because Gradle downloads its dependencies and SQLCipher is compiled. Later builds are faster.

While the app is running, use these keys in the terminal: `r` hot reload · `R` hot restart · `q` quit.

### On this PC: always use the short path

Your Flutter SDK path contains a space (`Sankalp Tiwari`). The native-asset build fails on it with `'C:\Users\Sankalp' is not recognized`. Flutter also rewrites `flutter.sdk` in `android/local.properties` with whatever path you call it from. So on this PC, always run Flutter through the 8.3 short path. This is the command that worked (2026-11-02):

```powershell
$short = (New-Object -ComObject Scripting.FileSystemObject).GetFolder("$env:USERPROFILE\flutter").ShortPath
& "$short\bin\flutter.bat" run --flavor dev -t lib/main_dev.dart --dart-define-from-file=env/dev.env
```

The other option is to move the SDK to a path without spaces, for example `C:\dev\flutter`, and update your `PATH`. After that, plain `flutter run` works.

### Build fixes already in the project

The first build on this PC needed these fixes. They are already in `naraacare-mobile/android/`, so you don't need to do anything:

| Error | Fix |
|---|---|
| `Namespace not specified` for `flutter_jailbreak_detection` | `build.gradle.kts` fills in the namespace from the plugin's manifest. |
| `Inconsistent JVM-target compatibility ... (11) and (25)` | `build.gradle.kts` pins Java and Kotlin to 17 for Kotlin plugins, the same as `:app`. |
| `Could not close incremental caches` / `different roots` | `gradle.properties`: `kotlin.incremental=false`. The project (D:) and the pub cache (C:) are on different drives. |
| `cannot find symbol ScreenProtectorPlugin` | `build.gradle.kts` applies the Kotlin plugin to plugins that have Kotlin sources but expect AGP 9 built-in Kotlin. |

## Other flavors

| Flavor | Command |
|---|---|
| dev | `flutter run --flavor dev -t lib/main_dev.dart --dart-define-from-file=env/dev.env` |
| staging | `flutter run --flavor staging -t lib/main_staging.dart --dart-define-from-file=env/staging.env` |
| prod | `flutter run --flavor prod -t lib/main_prod.dart --dart-define-from-file=env/prod.env` |

Staging and prod require `https://` URLs and a non-empty `CERT_PINS`. If either is wrong, the app refuses to start.

## iOS

iOS builds need a Mac with Xcode. They cannot be done on this Windows PC. On a Mac, do the one-time setup first: `gem install xcodeproj -v 1.27.0 && ruby tool/ios/setup_flavors.rb`, then `cd ios && pod install`. See `naraacare-mobile/README.md` for details.

## Tests and checks (optional)

```powershell
flutter analyze --fatal-infos
flutter test --dart-define-from-file=env/test.env
```

## Troubleshooting

| Problem | Fix |
|---|---|
| `No supported devices connected` / only Chrome and Windows are listed | Start an Android emulator or connect a phone (step 2). The app cannot run on Chrome or Windows. |
| Emulator screen stays black, but `adb devices` shows it | The display got stuck (Android itself is running). Cold-boot it: in Android Studio, **Device Manager → ⋮ → Cold Boot Now**, or run `"$LOCALAPPDATA/Android/Sdk/emulator/emulator.exe" -avd Pixel_10_Pro -no-snapshot-load`. If it stays black after a cold boot, add `-gpu swiftshader_indirect` (slower, but draws without the graphics card). |
| `Unable to locate Android SDK` | Do step 1, then `flutter config --android-sdk <path>`. |
| App starts with a config error | `env/dev.env` is missing, or `ENV_NAME` does not match the flavor. Redo step 3. |
| Network errors in the app | The backend is not running, or the URL is wrong for your device (see step 3). |
| "Something went wrong" on every API call | The backend answers `400 Invalid host header`. Add `10.0.2.2` (emulator) or your LAN IP (real phone) to `ALLOWED_HOSTS` in `naraacare-backend/.env`, then restart the backend. |
| NDK / CMake error on the first build | Install **NDK (Side by side)** and **CMake** in Android Studio's SDK Tools. |
| `sdkmanager did not install NDK 28.2.13676358` | Flutter needs that exact NDK version, and the new sdkmanager does not install it on its own. Run `& "$env:LOCALAPPDATA\Android\sdk\cmdline-tools\latest\bin\android.exe" sdk install "ndk/28.2.13676358"`. Or in Android Studio, go to SDK Tools → tick **Show Package Details** → NDK → **28.2.13676358**. |

---

## Note: the website (`D:\naraacare`)

`D:\naraacare` is a separate Next.js website, not the mobile app. To run it, install Node.js 20+ and then:
```powershell
cd D:\naraacare
npm install
npm run dev        # open http://localhost:3000
```
