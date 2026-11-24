# Launcher icon sources

Not bundled in the app (only `flutter_launcher_icons` reads them).

| File | What it is |
|---|---|
| `icon.png` | 1024 x 1024, logo at 70 % width on white. Used for legacy Android icons and iOS. |
| `icon_foreground.png` | 1024 x 1024, transparent, logo at 52 % width. The Android adaptive-icon foreground, which keeps the logo inside the safe zone that launchers crop to a circle or squircle. The background is white (`#FFFFFF`). |

Both are scaled up from `assets/brand/logo.png`, which is only 242 x 208 px. Replace them with
an export from a 1024 px or vector master when one exists, then run:

```
flutter pub run flutter_launcher_icons
```

Settings are in `flutter_launcher_icons.yaml`.
