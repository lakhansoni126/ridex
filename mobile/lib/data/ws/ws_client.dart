import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/config.dart';

typedef WsMessageHandler = void Function(Map<String, dynamic> message);
typedef TokenProvider = Future<String?> Function();

enum WsConnectionState { connecting, connected, reconnecting, closed }

/// Self-healing WebSocket: reconnects with exponential backoff (1s → 30s),
/// fetches a fresh access token on every attempt, and keeps a heartbeat.
class RideXWsClient {
  RideXWsClient({required this.urlBuilder, required this.tokenProvider});

  /// Builds the socket URL for a given access token.
  final String Function(String token) urlBuilder;
  final TokenProvider tokenProvider;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _retryTimer;
  int _attempt = 0;
  bool _disposed = false;
  WsMessageHandler? _onMessage;

  final _state = ValueNotifier<WsConnectionState>(WsConnectionState.closed);
  ValueListenable<WsConnectionState> get state => _state;
  bool get isConnected => _state.value == WsConnectionState.connected;

  Future<void> connect({required WsMessageHandler onMessage}) async {
    _onMessage = onMessage;
    _disposed = false;
    _attempt = 0;
    await _open();
  }

  Future<void> _open() async {
    if (_disposed) return;
    _state.value = _attempt == 0
        ? WsConnectionState.connecting
        : WsConnectionState.reconnecting;
    await _teardownChannel();

    final token = await tokenProvider();
    if (_disposed) return;
    if (token == null || token.isEmpty) {
      _scheduleRetry();
      return;
    }

    try {
      final channel = WebSocketChannel.connect(Uri.parse(urlBuilder(token)));
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 15));
      if (_disposed) {
        await _teardownChannel();
        return;
      }
      _attempt = 0;
      _state.value = WsConnectionState.connected;
      _sub = channel.stream.listen(
        (raw) {
          try {
            final data = jsonDecode(raw as String);
            if (data is Map<String, dynamic>) _onMessage?.call(data);
          } catch (e) {
            debugPrint('RideXWsClient parse error: $e');
          }
        },
        onError: (Object e) {
          debugPrint('RideXWsClient error: $e');
          _scheduleRetry();
        },
        onDone: _scheduleRetry,
        cancelOnError: true,
      );
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(
        const Duration(seconds: 25),
        (_) => send({'type': 'ping'}),
      );
    } catch (e) {
      debugPrint('RideXWsClient connect failed: $e');
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_disposed) return;
    _pingTimer?.cancel();
    _retryTimer?.cancel();
    _state.value = WsConnectionState.reconnecting;
    final seconds = min(30, pow(2, _attempt).toInt());
    final jitterMs = Random().nextInt(500);
    _attempt = min(_attempt + 1, 6);
    _retryTimer = Timer(
      Duration(seconds: seconds, milliseconds: jitterMs),
      _open,
    );
  }

  void send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null || !isConnected) return;
    try {
      channel.sink.add(jsonEncode(message));
    } catch (e) {
      debugPrint('RideXWsClient send failed: $e');
    }
  }

  Future<void> _teardownChannel() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    await _sub?.cancel();
    _sub = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await ch.sink.close();
      } catch (_) {}
    }
  }

  Future<void> disconnect() async {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _teardownChannel();
    _state.value = WsConnectionState.closed;
  }
}

class RideWsSession {
  RideWsSession({required this.rideId, required TokenProvider tokenProvider})
      : client = RideXWsClient(
          urlBuilder: (t) => ApiConfig.rideWsUrl(rideId, t),
          tokenProvider: tokenProvider,
        );

  final String rideId;
  final RideXWsClient client;

  ValueListenable<WsConnectionState> get state => client.state;

  Future<void> connect({required WsMessageHandler onMessage}) =>
      client.connect(onMessage: onMessage);

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
      'recorded_at': (recordedAt ?? DateTime.now()).toUtc().toIso8601String(),
      if (status != null) 'status': status,
    });
  }

  void sendStatus(String status) =>
      client.send({'type': 'status', 'status': status});

  Future<void> disconnect() => client.disconnect();
}

class LocationShareWsSession {
  LocationShareWsSession({required TokenProvider tokenProvider})
      : client = RideXWsClient(
          urlBuilder: ApiConfig.locationShareWsUrl,
          tokenProvider: tokenProvider,
        );

  final RideXWsClient client;

  ValueListenable<WsConnectionState> get state => client.state;

  Future<void> connect({required WsMessageHandler onMessage}) =>
      client.connect(onMessage: onMessage);

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
      'recorded_at': (recordedAt ?? DateTime.now()).toUtc().toIso8601String(),
    });
  }

  Future<void> disconnect() => client.disconnect();
}
