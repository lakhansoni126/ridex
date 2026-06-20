import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../services/location_service.dart';
import '../../../database/database_service.dart';
import '../../../database/models.dart';
import 'ride_state.dart';
import '../../../main.dart'; // To access dbService instance

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final rideEngineProvider = StateNotifierProvider<RideEngine, RideState>((ref) {
  return RideEngine(ref.watch(locationServiceProvider), dbService);
});

class RideEngine extends StateNotifier<RideState> {
  final LocationService _locationService;
  final DatabaseService _dbService;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _durationTimer;
  DateTime? _startTime;

  RideEngine(this._locationService, this._dbService) : super(const RideState());

  Future<void> startRide() async {
    final hasPermission = await _locationService.requestPermissions();
    if (!hasPermission) return;

    _startTime = DateTime.now();
    state = const RideState(isRecording: true);
    
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      state = state.copyWith(durationSeconds: state.durationSeconds + 1);
    });

    _positionSubscription = _locationService.getPositionStream().listen((Position position) {
      _processNewPosition(position);
    });
  }

  void _processNewPosition(Position position) {
    if (!state.isRecording) return;

    final speedKmh = position.speed * 3.6;
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

  Future<void> stopRide() async {
    if (!state.isRecording) return;
    
    _durationTimer?.cancel();
    _positionSubscription?.cancel();
    
    // Construct the Ride object
    final ride = Ride()
      ..startTime = _startTime ?? DateTime.now()
      ..endTime = DateTime.now()
      ..distance = state.distance
      ..durationSeconds = state.durationSeconds.toDouble()
      ..avgSpeed = (state.distance / (state.durationSeconds / 3600)).clamp(0, state.topSpeed)
      ..topSpeed = state.topSpeed;

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

    // Save to Database
    await _dbService.saveRide(ride);

    state = const RideState(); // Reset state
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }
}
