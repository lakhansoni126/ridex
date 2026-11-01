import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../data/api/rides_repository.dart';
import '../data/api/shares_repository.dart';
import '../data/local/location_buffer.dart';
import '../data/local/token_store.dart';
import '../data/ws/ws_client.dart';
import 'location_service.dart';

/// Background / foreground GPS stream for live group rides and location shares.
///
/// Buffers points locally and batch-syncs to the API; also emits WS location
/// messages when a socket session is attached.
class BackgroundLocationService {
  BackgroundLocationService({
    required LocationBuffer buffer,
    required RidesRepository ridesRepository,
    required SharesRepository sharesRepository,
    required TokenStore tokenStore,
    LocationService? locationService,
  })  : _buffer = buffer,
        _rides = ridesRepository,
        _shares = sharesRepository,
        _tokens = tokenStore,
        _location = locationService ?? LocationService();

  final LocationBuffer _buffer;
  final RidesRepository _rides;
  final SharesRepository _shares;
  final TokenStore _tokens;
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

  bool get isTracking => _sub != null;
  String? get activeRideId => _activeRideId;
  String? get activeShareId => _activeShareId;

  Future<bool> ensurePermissions({bool requestAlways = false}) async {
    final ok = await _location.requestPermissions();
    if (!ok) return false;
    if (requestAlways) {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse) {
        // Prompt again — on Android 10+ this can escalate to "Allow all the time".
        await Geolocator.requestPermission();
      }
    }
    return true;
  }

  Future<void> startForRide({
    required String rideId,
    String status = 'riding',
    RideWsSession? ws,
  }) async {
    _activeRideId = rideId;
    _participantStatus = status;
    _rideWs = ws;
    await _ensureStream();
  }

  Future<void> startForShare({
    required String shareId,
    LocationShareWsSession? ws,
  }) async {
    _activeShareId = shareId;
    _shareWs = ws;
    await _ensureStream();
  }

  void attachRideWs(RideWsSession? ws) => _rideWs = ws;
  void attachShareWs(LocationShareWsSession? ws) => _shareWs = ws;

  void updateParticipantStatus(String status) {
    _participantStatus = status;
    _rideWs?.sendStatus(status);
  }

  Future<void> stopRide() async {
    _activeRideId = null;
    await _rideWs?.disconnect();
    _rideWs = null;
    await _maybeStopStream();
  }

  Future<void> stopShare() async {
    _activeShareId = null;
    await _shareWs?.disconnect();
    _shareWs = null;
    await _maybeStopStream();
  }

  Future<void> stopAll() async {
    _activeRideId = null;
    _activeShareId = null;
    await _rideWs?.disconnect();
    await _shareWs?.disconnect();
    _rideWs = null;
    _shareWs = null;
    await _stopStream();
  }

  Future<void> _ensureStream() async {
    if (_sub != null) return;
    final ok = await ensurePermissions(requestAlways: true);
    if (!ok) {
      debugPrint('BackgroundLocationService: permissions denied');
      return;
    }
    _sub = _location.getPositionStream().listen(
      _onPosition,
      onError: (Object e) => debugPrint('BackgroundLocationService GPS: $e'),
    );
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 8), (_) => flush());
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
    await flush();
  }

  Duration _adaptiveInterval(Position pos) {
    final speedKmh = (pos.speed.isNaN ? 0 : pos.speed) * 3.6;
    if (speedKmh < 3) return const Duration(seconds: 8);
    if (speedKmh < 40) return const Duration(seconds: 4);
    return const Duration(seconds: 2);
  }

  Future<void> _onPosition(Position pos) async {
    final now = DateTime.now().toUtc();
    final interval = _adaptiveInterval(pos);
    if (_lastEmitAt != null && now.difference(_lastEmitAt!) < interval) {
      // Still accept if moved meaningfully
      if (_lastLat != null && _lastLon != null) {
        final moved = Geolocator.distanceBetween(
          _lastLat!,
          _lastLon!,
          pos.latitude,
          pos.longitude,
        );
        if (moved < 8) return;
      } else {
        return;
      }
    }
    _lastEmitAt = now;
    _lastLat = pos.latitude;
    _lastLon = pos.longitude;

    final speedMps = pos.speed.isNaN ? null : pos.speed;
    final heading = pos.heading.isNaN ? null : pos.heading;
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

  Future<String?> currentAccessToken() => _tokens.readAccessToken();
}
