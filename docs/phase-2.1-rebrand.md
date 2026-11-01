# Phase 2.1 — Rebrand & monorepo

## What changed

### Monorepo
- Flutter app moved from repo root → `mobile/`
- Created `backend/`, `assets/`, `storage/`, `infra/`, `docs/`, `scripts/`
- Legacy docs → `docs/legacy/`
- CI workflow runs from `mobile/` (`working-directory: mobile`)
- Removed `|| true` from APK build so failures surface

### Branding
- App name: **RideX** (`MaterialApp` title, FGS notification, pubspec)
- Package name: `ridex`
- Logo SVG + adaptive icon sources under `assets/branding/`
- PNG exports: Android mipmaps, iOS AppIcon set, splash
- Flutter copies under `mobile/assets/branding/` for asset bundling
- `flutter_launcher_icons` + `flutter_native_splash` configured in `mobile/pubspec.yaml`

### Domain (bike → car)
- `Bike` Isar model → `Vehicle`
- Garage UI: cars / `Icons.directions_car`
- Copy, SOS SMS, export text updated
- Dashboard brand hero: **RideX**
- Lean metric label → **TILT** (IMU retained for crash detection)

## How to verify locally

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter create --platforms android,ios .   # if platforms missing
dart run flutter_launcher_icons
dart run flutter_native_splash:create
flutter run
```

Check: home shows **RideX**, garage says cars, notification text says RideX when tracking.

## Manual notes
- Isar schema change (`Bike` → `Vehicle`): clear app data / reinstall if old DB conflicts.
- Platform folders are still generated in CI until committed.
