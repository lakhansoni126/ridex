import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:geolocator/geolocator.dart';

part 'ride_state.freezed.dart';

@freezed
class RideState with _$RideState {
  const factory RideState({
    @Default(false) bool isRecording,
    @Default(false) bool isPaused,
    @Default(false) bool hasCrashed,
    @Default(0.0) double currentSpeed, // km/h
    @Default(0.0) double topSpeed, // km/h
    @Default(0.0) double distance, // km
    @Default(0) int durationSeconds,
    @Default(0.0) double currentLeanAngle,
    @Default(0.0) double maxLeanAngle,
    String? weatherCondition,
    double? temperature,
    Position? lastPosition,
    @Default([]) List<Position> routePoints,
  }) = _RideState;
}
