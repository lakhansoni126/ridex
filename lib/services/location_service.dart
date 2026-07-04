import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Unified GPS service using only Geolocator's permission system
/// to avoid conflicts with permission_handler.
class LocationService {
  /// Request location permissions using Geolocator's built-in system.
  /// Returns true if at least "while in use" permission is granted.
  Future<bool> requestPermissions() async {
    // 1. Check if location services are enabled on the device
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('LocationService: Location services are disabled on this device.');
      return false;
    }

    // 2. Check current permission status
    LocationPermission permission = await Geolocator.checkPermission();

    // 3. If denied, request it
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('LocationService: Location permission denied by user.');
        return false;
      }
    }

    // 4. If permanently denied, we can't do anything
    if (permission == LocationPermission.deniedForever) {
      debugPrint('LocationService: Location permission permanently denied. User must enable in Settings.');
      return false;
    }

    debugPrint('LocationService: Permission granted: $permission');
    return true;
  }

  /// Get a one-shot position fix. Returns null if it fails.
  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint('LocationService: getCurrentPosition failed: $e');
      return null;
    }
  }

  /// Get a continuous stream of position updates.
  /// distanceFilter: 0 means we get updates even when stationary (time-based).
  Stream<Position> getPositionStream() {
    LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0, // Get ALL updates, even when stationary
        forceLocationManager: false, // Use Fused Location Provider (reliable)
        intervalDuration: const Duration(seconds: 2), // Update every 2 seconds
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Ride Analytics is tracking your ride in the background.",
          notificationTitle: "Ride Tracking Active",
          enableWakeLock: true,
        ),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
    }

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}
