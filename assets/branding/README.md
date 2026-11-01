# RideX Branding

Canonical brand assets for **RideX** (automobile community / group rides).

## Source (edit these)

| File | Purpose |
|------|---------|
| `ridex-logo.svg` | App mark (R + road/car cue) on `#0F0F11` |
| `ridex-wordmark.svg` | Horizontal RideX wordmark |
| `ridex-icon-fg.svg` | Android adaptive foreground (safe zone) |
| `ridex-icon-bg.svg` | Android adaptive background (`#0F0F11`) |

## Exports

| Path | Purpose |
|------|---------|
| `exports/ridex-icon-1024.png` | Master app icon |
| `exports/ridex-wordmark.png` | Marketing / splash wordmark |
| `exports/android/mipmap-*` | Android launcher densities |
| `exports/android/ic_launcher_background.png` | Adaptive background |
| `exports/ios/AppIcon.appiconset/` | iOS App Icon set + `Contents.json` |
| `exports/splash/` | Portrait & landscape splash bases |

Colors: background `#0F0F11`, accent `#E53935`, text `#FFFFFF`.

Mobile copies used by Flutter live under `mobile/assets/branding/` (keep in sync when regenerating).

## Regenerate mobile icons / splash

```bash
cd mobile
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```
