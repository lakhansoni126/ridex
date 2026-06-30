import 'dart:async';
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
    final hasPermission = await _locationService.requestPermissions();
    if (!hasPermission) return;

    _startTime = DateTime.now();
    
    // Attempt to fetch weather safely without blocking the ride start
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low, 
        timeLimit: const Duration(seconds: 5)
      );
      final weather = await WeatherService.fetchWeather(pos.latitude, pos.longitude);

      state = const RideState(isRecording: true).copyWith(
        weatherCondition: weather?.condition,
        temperature: weather?.temperature,
      );
    } catch (e) {
      // If GPS fails to lock quickly or throws, start recording anyway
      state = const RideState(isRecording: true);
    }

    _imuService.onCrashDetected = (gForce) {
      if (!state.hasCrashed) {
        state = state.copyWith(hasCrashed: true);
      }
    };
    _imuService.startTracking();
    
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!state.isPaused) {
        state = state.copyWith(
          durationSeconds: state.durationSeconds + 1,
          currentLeanAngle: _imuService.currentLeanAngle,
          maxLeanAngle: _imuService.maxLeanAngle,
        );
      }
    });

    _positionSubscription = _locationService.getPositionStream().listen((Position position) {
      _processNewPosition(position);
    });
  }

  void _processNewPosition(Position position) {
    if (!state.isRecording) return;

    final speedKmh = position.speed * 3.6;

    // Auto-pause logic
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

    if (state.isPaused) return;

    final newTopSpeed = speedKmh > state.topSpeed ? speedKmh : state.topSpeed;
    
    double addedDistance = 0.0;
    if (state.lastPosition != null) {
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
      currentSpeed: speedKmh,
      topSpeed: newTopSpeed,
      distance: newDistance,
      lastPosition: position,
      routePoints: newPoints,
    );
  }

  void cancelSOS() {
    state = state.copyWith(hasCrashed: false);
  }

  Future<void> stopRide() async {
    if (!state.isRecording) return;
    
    _durationTimer?.cancel();
    _positionSubscription?.cancel();
    _imuService.stopTracking();
    
    final ride = Ride()
      ..startTime = _startTime ?? DateTime.now()
      ..endTime = DateTime.now()
      ..distance = state.distance
      ..durationSeconds = state.durationSeconds.toDouble()
      ..avgSpeed = (state.distance / (state.durationSeconds / 3600)).clamp(0, state.topSpeed)
      ..topSpeed = state.topSpeed
      ..maxLeanAngle = state.maxLeanAngle
      ..weatherCondition = state.weatherCondition
      ..temperatureCelsius = state.temperature;

    final points = state.routePoints.map((p) => RidePoint()
      ..latitude = p.latitude
      ..longitude = p.longitude
      ..speed = p.speed * 3.6
      ..heading = p.heading
      ..altitude = p.altitude
      ..accuracy = p.accuracy
      ..timestamp = p.timestamp ?? DateTime.now()
    ).toList();

    ride.points.addAll(points);
    await _dbService.saveRide(ride);

    state = const RideState(); 
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _positionSubscription?.cancel();
    _imuService.stopTracking();
    super.dispose();
  }
}
