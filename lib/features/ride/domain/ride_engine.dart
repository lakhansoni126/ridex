import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../services/location_service.dart';
import 'ride_state.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final rideEngineProvider = StateNotifierProvider<RideEngine, RideState>((ref) {
  return RideEngine(ref.watch(locationServiceProvider));
});

class RideEngine extends StateNotifier<RideState> {
  final LocationService _locationService;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _durationTimer;

  RideEngine(this._locationService) : super(const RideState());

  Future<void> startRide() async {
    final hasPermission = await _locationService.requestPermissions();
    if (!hasPermission) return;

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

    // Calculate speed in km/h (position.speed is m/s)
    final speedKmh = position.speed * 3.6;
    
    final newTopSpeed = speedKmh > state.topSpeed ? speedKmh : state.topSpeed;
    
    double addedDistance = 0.0;
    if (state.lastPosition != null) {
      addedDistance = Geolocator.distanceBetween(
        state.lastPosition!.latitude,
        state.lastPosition!.longitude,
        position.latitude,
        position.longitude,
      ) / 1000.0; // convert meters to km
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

  void stopRide() {
    _durationTimer?.cancel();
    _positionSubscription?.cancel();
    state = state.copyWith(isRecording: false, currentSpeed: 0.0);
    // TODO: Save ride to Isar database here
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }
}
