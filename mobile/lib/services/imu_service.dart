import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

final imuServiceProvider = Provider((ref) => ImuService());

class ImuService {
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<UserAccelerometerEvent>? _userAccelSub;

  double _currentLeanAngle = 0.0;
  double _maxLeanAngle = 0.0;
  
  Function(double)? onCrashDetected;

  void startTracking() {
    _maxLeanAngle = 0.0;
    
    // Track gravity vector to estimate lean angle
    _accelSub = accelerometerEventStream().listen((AccelerometerEvent event) {
      // Assuming phone is mounted perfectly upright and forward.
      // x is lateral (left/right), y is vertical (up/down), z is forward/back
      // Lean angle = atan(x / y)
      // This is a simplified estimation for a rigidly mounted phone.
      if (event.y != 0) {
        double angleRad = atan(event.x / event.y);
        double angleDeg = angleRad * (180 / pi);
        
        _currentLeanAngle = angleDeg.abs();
        if (_currentLeanAngle > _maxLeanAngle && _currentLeanAngle < 70) {
           // Cap at 70 to avoid anomalies
          _maxLeanAngle = _currentLeanAngle;
        }
      }
    });

    // Track user accelerometer (without gravity) for crash detection
    _userAccelSub = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      // Calculate total magnitude of G-force (excluding gravity)
      // 1 G = 9.81 m/s^2.
      double magnitude = sqrt(pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2));
      double gForce = magnitude / 9.81;

      // Arbitrary threshold for a "crash" spike
      if (gForce > 5.0) {
        onCrashDetected?.call(gForce);
      }
    });
  }

  void stopTracking() {
    _accelSub?.cancel();
    _userAccelSub?.cancel();
  }

  double get currentLeanAngle => _currentLeanAngle;
  double get maxLeanAngle => _maxLeanAngle;
}
