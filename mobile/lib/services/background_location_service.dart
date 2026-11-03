import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../data/api/rides_repository.dart';
import '../data/api/shares_repository.dart';
import '../data/local/location_buffer.dart';
import '../data/ws/ws_client.dart';
import 'location_service.dart';

/// What the background tracker is currently doing (drives UI badges).
@immutable
class TrackingStatus {
  const TrackingStatus({
    this.rideId,
    this.shareId,
    this.permissionDenied = false,
    this.lastFixAt,
  });

  final String? rideId;
  final String? shareId;
  final bool permissionDenied;
  final DateTime? lastFixAt;

  bool get isTracking => rideId != null || shareId != null;
}

/// Foreground-service GPS stream for live group drives and location shares.
///
/// Every fix is persisted to [LocationBuffer] first (offline-safe), pushed
/// over the WebSocket when connected for low latency, and batch-synced over
/// REST every few seconds. The server de-duplicates by timestamp.
class BackgroundLocationService {
  BackgroundLocationService({
    required LocationBuffer buffer,
    required RidesRepository ridesRepository,
    required SharesRepository sharesRepository,
    LocationService? locationService,
  })  : _buffer = buffer,
        _rides = ridesRepository,
        _shares = sharesRepository,
        _location = locationService ?? LocationService();

  final LocationBuffer _buffer;
  final RidesRepository _rides;
  final SharesRepository _shares;
  final LocationService _location;

  StreamSubscription<Position>? _sub;
  Timer? _syncTimer;
  String? _activeRideId;
  String? _activeShareId;
  String _participantStatus = 'riding';
  RideWsSession? _rideWs;
  LocationShareWsSession? _shareWs;
  DateTime? _lastEmitAt;
  double? _lastLat;
  double? _lastLon;

  final status = ValueNotifier(const TrackingStatus());

  bool get isTracking => _sub != null;
  String? get activeRideId => _activeRideId;
  String? get activeShareId => _activeShareId;

  void _publish({bool permissionDenied = false, DateTime? fix}) {
    status.value = TrackingStatus(
      rideId: _activeRideId,
      shareId: _activeShareId,
      permissionDenied: permissionDenied,
      lastFixAt: fix ?? status.value.lastFixAt,
    );
  }

  /// Returns false when location permission is unavailable.
  Future<bool> startForRide({
    required String rideId,
    String status = 'riding',
    RideWsSession? ws,
  }) async {
    _activeRideId = rideId;
    _participantStatus = status;
    if (ws != null) _rideWs = ws;
    return _ensureStream();
  }

  Future<bool> startForShare({
    required String shareId,
    LocationShareWsSession? ws,
  }) async {
    _activeShareId = shareId;
    if (ws != null) _shareWs = ws;
    return _ensureStream();
  }

  /// Lets a screen hand its socket to the tracker (or detach with null).
  void attachRideWs(RideWsSession? ws) => _rideWs = ws;
  void attachShareWs(LocationShareWsSession? ws) => _shareWs = ws;

  void updateParticipantStatus(String status) {
    _participantStatus = status;
    _rideWs?.sendStatus(status);
  }

  Future<void> stopRide() async {
    _activeRideId = null;
    _rideWs = null;
    await _maybeStopStream();
    _publish();
  }

  Future<void> stopShare() async {
    final ws = _shareWs;
    _activeShareId = null;
    _shareWs = null;
    await ws?.disconnect();
    await _maybeStopStream();
    _publish();
  }

  Future<void> stopAll() async {
    final shareWs = _shareWs;
    _activeRideId = null;
    _activeShareId = null;
    _rideWs = null;
    _shareWs = null;
    await shareWs?.disconnect();
    await _stopStream();
    _publish();
  }

  Future<bool> _ensureStream() async {
    if (_sub != null) {
      _publish();
      return true;
    }
    final ok = await _location.requestPermissions();
    if (!ok) {
      debugPrint('BackgroundLocationService: permissions denied');
      _activeRideId = null;
      _activeShareId = null;
      _publish(permissionDenied: true);
      return false;
    }
    _sub = _location.getPositionStream().listen(
          _onPosition,
          onError: (Object e) =>
              debugPrint('BackgroundLocationService GPS: $e'),
        );
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 6), (_) => flush());
    _publish();
    return true;
  }

  Future<void> _maybeStopStream() async {
    if (_activeRideId == null && _activeShareId == null) {
      await _stopStream();
    }
  }

  Future<void> _stopStream() async {
    await _sub?.cancel();
    _sub = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _lastEmitAt = null;
    await flush();
  }

  Duration _adaptiveInterval(Position pos) {
    final speedKmh = (pos.speed.isNaN ? 0 : pos.speed) * 3.6;
    if (speedKmh < 3) return const Duration(seconds: 8);
    if (speedKmh < 40) return const Duration(seconds: 4);
    return const Duration(seconds: 2);
  }

  Future<void> _onPosition(Position pos) async {
    // Ignore wildly inaccurate fixes (tunnels, indoor).
    if (!pos.accuracy.isNaN && pos.accuracy > 100) return;

    final now = DateTime.now().toUtc();
    final interval = _adaptiveInterval(pos);
    if (_lastEmitAt != null && now.difference(_lastEmitAt!) < interval) {
      if (_lastLat == null || _lastLon == null) return;
      final moved = Geolocator.distanceBetween(
          _lastLat!, _lastLon!, pos.latitude, pos.longitude);
      if (moved < 15) return;
    }
    _lastEmitAt = now;
    _lastLat = pos.latitude;
    _lastLon = pos.longitude;
    _publish(fix: now);

    final speedMps = pos.speed.isNaN || pos.speed < 0 ? null : pos.speed;
    final heading = pos.heading.isNaN || pos.heading < 0 ? null : pos.heading;
    final accuracy = pos.accuracy.isNaN ? null : pos.accuracy;

    final rideId = _activeRideId;
    if (rideId != null) {
      await _buffer.enqueue(
        targetType: 'ride',
        targetId: rideId,
        lat: pos.latitude,
        lon: pos.longitude,
        speedMps: speedMps,
        heading: heading,
        accuracyM: accuracy,
        status: _participantStatus,
        recordedAt: now,
      );
      _rideWs?.sendLocation(
        lat: pos.latitude,
        lon: pos.longitude,
        speed: speedMps,
        heading: heading,
        accuracy: accuracy,
        recordedAt: now,
        status: _participantStatus,
      );
    }

    final shareId = _activeShareId;
    if (shareId != null) {
      await _buffer.enqueue(
        targetType: 'share',
        targetId: shareId,
        lat: pos.latitude,
        lon: pos.longitude,
        speedMps: speedMps,
        heading: heading,
        accuracyM: accuracy,
        recordedAt: now,
      );
      _shareWs?.sendLocation(
        shareId: shareId,
        lat: pos.latitude,
        lon: pos.longitude,
        recordedAt: now,
      );
    }
  }

  Future<void> flush() async {
    await _buffer.syncAll(flushBatch: (type, id, points) async {
      if (type == 'ride') {
        await _rides.postLocations(id, points);
      } else if (type == 'share') {
        await _shares.postLocations(id, points);
      }
    });
  }
}
