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
  int _stationaryTicks = 0;

  RideEngine(this._locationService, this._imuService, this._dbService) : super(const RideState());

  Future<void> startRide() async {
    if (state.isRecording) return;

    debugPrint('RideEngine: Requesting permissions...');
    final hasPermission = await _locationService.requestPermissions();
    if (!hasPermission) {
      debugPrint('RideEngine: ❌ Permission denied, ride will NOT start.');
      return;
    }
    debugPrint('RideEngine: ✅ Permission granted.');

    _startTime = DateTime.now();
    _stationaryTicks = 0;

    // ── 1. Start recording IMMEDIATELY ──
    state = const RideState(isRecording: true);
    debugPrint('RideEngine: 🟢 Ride started, isRecording=true');

    // ── 2. Get an initial GPS fix so the map has a position right away ──
    final initialPos = await _locationService.getCurrentPosition();
    if (initialPos != null && mounted) {
      debugPrint('RideEngine: 📍 Initial GPS fix: ${initialPos.latitude}, ${initialPos.longitude}');
      state = state.copyWith(
        lastPosition: initialPos,
        routePoints: [initialPos],
      );
    } else {
      debugPrint('RideEngine: ⚠️ No initial GPS fix (will get from stream)');
    }

    // ── 3. Fetch weather in background (non-blocking) ──
    if (initialPos != null) {
      _fetchWeatherInBackground(initialPos.latitude, initialPos.longitude);
    }

    // ── 4. Start IMU tracking ──
    _imuService.onCrashDetected = (gForce) {
      if (mounted && !state.hasCrashed) {
        state = state.copyWith(hasCrashed: true);
      }
    };
    _imuService.startTracking();

    // ── 5. Start duration timer ──
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (!state.isPaused) {
        state = state.copyWith(
          durationSeconds: state.durationSeconds + 1,
          currentLeanAngle: _imuService.currentLeanAngle,
          maxLeanAngle: _imuService.maxLeanAngle,
        );
      }
    });

    // ── 6. Subscribe to GPS stream ──
    _positionSubscription = _locationService.getPositionStream().listen(
      (Position position) {
        debugPrint('RideEngine: 📡 GPS update: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}, speed=${(position.speed * 3.6).toStringAsFixed(1)} km/h');
        _processNewPosition(position);
      },
      onError: (error) {
        debugPrint('RideEngine: ❌ GPS stream error: $error');
      },
    );
  }

  Future<void> _fetchWeatherInBackground(double lat, double lon) async {
    try {
      final weather = await WeatherService.fetchWeather(lat, lon);
      if (mounted && weather != null) {
        state = state.copyWith(
          weatherCondition: weather.condition,
          temperature: weather.temperature,
        );
        debugPrint('RideEngine: 🌤️ Weather: ${weather.temperature}°C ${weather.condition}');
      }
    } catch (e) {
      debugPrint('RideEngine: Weather fetch failed (non-critical): $e');
    }
  }

  void _processNewPosition(Position position) {
    if (!mounted || !state.isRecording) return;

    final speedKmh = (position.speed * 3.6).clamp(0.0, 500.0);

    // Auto-pause logic: only kicks in after we already have a position
    if (state.lastPosition != null) {
      if (speedKmh < 3.0) {
        _stationaryTicks++;
        if (_stationaryTicks > 15 && !state.isPaused) {
          state = state.copyWith(isPaused: true, currentSpeed: 0.0);
          debugPrint('RideEngine: ⏸️ Auto-paused (stationary for ${_stationaryTicks}s)');
        }
      } else {
        _stationaryTicks = 0;
        if (state.isPaused) {
          state = state.copyWith(isPaused: false);
          debugPrint('RideEngine: ▶️ Auto-resumed');
        }
      }
    }

    // Calculate distance (only when not paused and we have a previous position)
    double addedDistance = 0.0;
    if (state.lastPosition != null && !state.isPaused) {
      addedDistance = Geolocator.distanceBetween(
        state.lastPosition!.latitude,
        state.lastPosition!.longitude,
        position.latitude,
        position.longitude,
      ) / 1000.0;
      
      // Filter out GPS noise: ignore jumps > 1km in a single tick
      if (addedDistance > 1.0) {
        addedDistance = 0.0;
      }
    }

    final newTopSpeed = speedKmh > state.topSpeed ? speedKmh : state.topSpeed;
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

    debugPrint('RideEngine: 🛑 Stopping ride...');
    _durationTimer?.cancel();
    _positionSubscription?.cancel();
    _imuService.stopTracking();

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

        ride.points.addAll(points);
        await _dbService.saveRide(ride);
        debugPrint('RideEngine: ✅ Ride saved! ${points.length} GPS points, ${state.distance.toStringAsFixed(2)} km');
      } catch (e) {
        debugPrint('RideEngine: ❌ Error saving ride: $e');
      }
    } else {
      debugPrint('RideEngine: ⚠️ No data to save (0 points, 0 duration)');
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
