import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:geolocator/geolocator.dart';

part 'ride_state.freezed.dart';

@freezed
class RideState with _$RideState {
  const factory RideState({
    @Default(false) bool isRecording,
    @Default(0.0) double currentSpeed, // km/h
    @Default(0.0) double topSpeed, // km/h
    @Default(0.0) double distance, // km
    @Default(0) int durationSeconds,
    Position? lastPosition,
    @Default([]) List<Position> routePoints,
  }) = _RideState;
}
