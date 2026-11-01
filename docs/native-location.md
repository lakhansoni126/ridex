# RideX — Background location (native setup)

Platform folders are generated with `flutter create` (or by CI). Apply these settings after generating `mobile/android` and `mobile/ios`.

## Android

**Permissions** in `android/app/src/main/AndroidManifest.xml` (inside `<manifest>`, before `<application>`):

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.INTERNET" />
```

**Foreground service type** on the activity/service as required by your Geolocator version (Geolocator’s `ForegroundNotificationConfig` registers the FGS). Notification copy is set in code: **“RideX is sharing your location”**.

**Battery:** On first live drive / share, guide users to disable battery optimization for RideX (OEM settings). The permission education screen explains Always access before the system dialog.

**App label:** `android:label="RideX"`.

Helper: `scripts/patch_mobile_native.py` (run after `flutter create`).

## iOS

In `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>RideX needs your location for live group drives and optional friend sharing.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>RideX continues sharing your location in the background only while a drive is live or you choose to share with friends.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>RideX continues sharing your location in the background only while a drive is live or you choose to share with friends.</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
</array>
```

Request **When In Use** first (education screen), then escalate to **Always** when starting a live drive or location share (`BackgroundLocationService.ensurePermissions(requestAlways: true)`).

Significant-change monitoring can be added later as a low-power fallback; the current MVP uses the Geolocator stream with adaptive emit intervals while the FGS / background mode keeps the app alive.

## Adaptive updates & offline buffer

- Moving: ~2–4s emit interval; stationary: ~8s (see `BackgroundLocationService`).
- Points are queued in `LocationBuffer` and flushed every ~8s via REST batch endpoints; WebSocket sends the latest fix when connected.
