import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../services/location_service.dart';
import '../../../services/imu_service.dart';
import '../../../services/weather_service.dart';
import '../../../database/database_service.dart';
import '../../../database/models.dart';
import 'ride_state.dart';
import '../../../main.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final rideEngineProvider = StateNotifierProvider<RideEngine, RideState>((ref) {
  return RideEngine(ref.watch(locationServiceProvider), ref.watch(imuServiceProvider), dbService);
});

class RideEngine extends StateNotifier<RideState> {
  final LocationService _locationService;
  final ImuService _imuService;
  final DatabaseService _dbService;

  StreamSubscription<Position>? _positionSubscription;
  Timer? _durationTimer;
  DateTime? _startTime;
  int _stationarySeconds = 0;

  RideEngine(this._locationService, this._imuService, this._dbService) : super(const RideState());

  Future<void> startRide() async {
    // Prevent double-starting
    if (state.isRecording) return;

    final hasPermission = await _locationService.requestPermissions();
    if (!hasPermission) {
      debugPrint('RideEngine: Location permission denied');
      return;
    }

    _startTime = DateTime.now();
    _stationarySeconds = 0;

    // Start recording immediately — weather is optional
    state = const RideState(isRecording: true);

    // Attempt to fetch weather in the background (non-blocking)
    _fetchWeatherInBackground();

    // Set up crash detection
    _imuService.onCrashDetected = (gForce) {
      if (mounted && !state.hasCrashed) {
        state = state.copyWith(hasCrashed: true);
      }
    };
    _imuService.startTracking();

    // Timer ticks every second
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!state.isPaused) {
        state = state.copyWith(
          durationSeconds: state.durationSeconds + 1,
          currentLeanAngle: _imuService.currentLeanAngle,
          maxLeanAngle: _imuService.maxLeanAngle,
        );
      }
    });

    // Subscribe to GPS stream
    _positionSubscription = _locationService.getPositionStream().listen(
      (Position position) {
        _processNewPosition(position);
      },
      onError: (error) {
        debugPrint('RideEngine: GPS stream error: $error');
      },
    );
  }

  Future<void> _fetchWeatherInBackground() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 5),
      );
      final weather = await WeatherService.fetchWeather(pos.latitude, pos.longitude);
      if (mounted && weather != null) {
        state = state.copyWith(
          weatherCondition: weather.condition,
          temperature: weather.temperature,
        );
      }
    } catch (e) {
      debugPrint('RideEngine: Weather fetch failed (non-critical): $e');
    }
  }

  void _processNewPosition(Position position) {
    if (!mounted || !state.isRecording) return;

    final speedKmh = (position.speed * 3.6).clamp(0.0, 500.0);

    // Auto-pause logic: only after we have at least one GPS fix
    if (state.lastPosition != null) {
      if (speedKmh < 3.0) {
        _stationarySeconds++;
        if (_stationarySeconds > 10 && !state.isPaused) {
          state = state.copyWith(isPaused: true, currentSpeed: 0.0);
        }
      } else {
        _stationarySeconds = 0;
        if (state.isPaused) {
          state = state.copyWith(isPaused: false);
        }
      }
    }

    // Always update lastPosition and routePoints even when paused
    // so the map always shows current location
    final newTopSpeed = speedKmh > state.topSpeed ? speedKmh : state.topSpeed;

    double addedDistance = 0.0;
    if (state.lastPosition != null && !state.isPaused) {
      addedDistance = Geolocator.distanceBetween(
        state.lastPosition!.latitude,
        state.lastPosition!.longitude,
        position.latitude,
        position.longitude,
      ) / 1000.0;
    }

    final newDistance = state.distance + addedDistance;
    final newPoints = List<Position>.from(state.routePoints)..add(position);

    state = state.copyWith(
      currentSpeed: state.isPaused ? 0.0 : speedKmh,
      topSpeed: newTopSpeed,
      distance: newDistance,
      lastPosition: position,
      routePoints: newPoints,
    );
  }

  void cancelSOS() {
    if (mounted) {
      state = state.copyWith(hasCrashed: false);
    }
  }

  Future<void> stopRide() async {
    if (!state.isRecording) return;

    _durationTimer?.cancel();
    _positionSubscription?.cancel();
    _imuService.stopTracking();

    // Only save if we have some data
    if (state.routePoints.isNotEmpty || state.durationSeconds > 0) {
      try {
        final duration = state.durationSeconds.toDouble();
        final avgSpeed = duration > 0
            ? (state.distance / (duration / 3600)).clamp(0.0, state.topSpeed)
            : 0.0;

        final ride = Ride()
          ..startTime = _startTime ?? DateTime.now()
          ..endTime = DateTime.now()
          ..distance = state.distance
          ..durationSeconds = duration
          ..avgSpeed = avgSpeed
          ..topSpeed = state.topSpeed
          ..maxLeanAngle = state.maxLeanAngle
          ..weatherCondition = state.weatherCondition
          ..temperatureCelsius = state.temperature;

        final points = state.routePoints.map((p) => RidePoint()
          ..latitude = p.latitude
          ..longitude = p.longitude
          ..speed = (p.speed * 3.6).clamp(0.0, 500.0)
          ..heading = p.heading
          ..altitude = p.altitude
          ..accuracy = p.accuracy
          ..timestamp = p.timestamp ?? DateTime.now()
        ).toList();

        // Add points to ride's IsarLinks collection
        ride.points.addAll(points);
        await _dbService.saveRide(ride);
        debugPrint('RideEngine: Ride saved successfully with ${points.length} points');
      } catch (e) {
        debugPrint('RideEngine: Error saving ride: $e');
      }
    }

    if (mounted) {
      state = const RideState();
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _positionSubscription?.cancel();
    _imuService.stopTracking();
    super.dispose();
  }
}
