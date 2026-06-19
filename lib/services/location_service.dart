import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  Future<bool> requestPermissions() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      final backgroundStatus = await Permission.locationAlways.request();
      return backgroundStatus.isGranted || status.isGranted;
    }
    return false;
  }

  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  Stream<Position> getPositionStream() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5, // Update every 5 meters
    );
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}
