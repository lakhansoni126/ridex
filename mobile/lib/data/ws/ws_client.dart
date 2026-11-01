import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/config.dart';

typedef WsMessageHandler = void Function(Map<String, dynamic> message);

/// Thin WebSocket helper for RideX ride + location-share sockets.
class RideXWsClient {
  RideXWsClient();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  bool _closed = false;

  bool get isConnected => _channel != null && !_closed;

  Future<void> connect(
    String url, {
    required WsMessageHandler onMessage,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) async {
    await disconnect();
    _closed = false;
    debugPrint('RideXWsClient connecting: $url');
    final channel = WebSocketChannel.connect(Uri.parse(url));
    _channel = channel;
    _sub = channel.stream.listen(
      (raw) {
        try {
          final data = jsonDecode(raw as String) as Map<String, dynamic>;
          onMessage(data);
        } catch (e) {
          debugPrint('RideXWsClient parse error: $e');
        }
      },
      onError: (Object e) {
        debugPrint('RideXWsClient error: $e');
        onError?.call(e);
      },
      onDone: () {
        debugPrint('RideXWsClient done');
        _pingTimer?.cancel();
        onDone?.call();
      },
    );
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      send({'type': 'ping'});
    });
  }

  void send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null || _closed) return;
    try {
      channel.sink.add(jsonEncode(message));
    } catch (e) {
      debugPrint('RideXWsClient send failed: $e');
    }
  }

  Future<void> disconnect() async {
    _closed = true;
    _pingTimer?.cancel();
    _pingTimer = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }
}

class RideWsSession {
  RideWsSession({required this.rideId, required this.accessToken});

  final String rideId;
  final String accessToken;
  final RideXWsClient client = RideXWsClient();

  Future<void> connect({
    required WsMessageHandler onMessage,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) {
    return client.connect(
      ApiConfig.rideWsUrl(rideId, accessToken),
      onMessage: onMessage,
      onError: onError,
      onDone: onDone,
    );
  }

  void sendLocation({
    required double lat,
    required double lon,
    double? speed,
    double? heading,
    double? accuracy,
    DateTime? recordedAt,
    String? status,
  }) {
    client.send({
      'type': 'location',
      'lat': lat,
      'lon': lon,
      if (speed != null) 'speed': speed,
      if (heading != null) 'heading': heading,
      if (accuracy != null) 'accuracy': accuracy,
      'recorded_at': (recordedAt ?? DateTime.now().toUtc()).toIso8601String(),
      if (status != null) 'status': status,
    });
  }

  void sendStatus(String status) {
    client.send({'type': 'status', 'status': status});
  }

  Future<void> disconnect() => client.disconnect();
}

class LocationShareWsSession {
  LocationShareWsSession({required this.accessToken});

  final String accessToken;
  final RideXWsClient client = RideXWsClient();

  Future<void> connect({
    required WsMessageHandler onMessage,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) {
    return client.connect(
      ApiConfig.locationShareWsUrl(accessToken),
      onMessage: onMessage,
      onError: onError,
      onDone: onDone,
    );
  }

  void sendLocation({
    required String shareId,
    required double lat,
    required double lon,
    DateTime? recordedAt,
  }) {
    client.send({
      'type': 'location',
      'share_id': shareId,
      'lat': lat,
      'lon': lon,
      'recorded_at': (recordedAt ?? DateTime.now().toUtc()).toIso8601String(),
    });
  }

  Future<void> disconnect() => client.disconnect();
}
