import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  Future<bool> requestPermissions() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      final backgroundStatus = await Permission.locationAlways.request();
      if (Platform.isAndroid) {
        // Required for Android 14+ Foreground Service
        await Permission.notification.request();
      }
      return backgroundStatus.isGranted || status.isGranted;
    }
    return false;
  }

  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  Stream<Position> getPositionStream() {
    LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5, // Update every 5 meters
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Ride Analytics is tracking your ride in the background.",
          notificationTitle: "Ride Tracking Active",
          enableWakeLock: true,
        ),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      );
    }

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}
