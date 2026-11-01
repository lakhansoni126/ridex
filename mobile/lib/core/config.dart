/// RideX API configuration.
///
/// Android emulator → host machine: `10.0.2.2`
/// iOS simulator → host machine: `127.0.0.1` / `localhost`
/// Physical device → your LAN IP (e.g. `192.168.1.10`)
class ApiConfig {
  ApiConfig._();

  /// Override at build time:
  /// `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000`
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const String apiPrefix = '/api/v1';

  static String get restBaseUrl => '$apiBaseUrl$apiPrefix';

  /// WebSocket base derived from [apiBaseUrl] (http→ws, https→wss).
  static String get wsBaseUrl {
    final uri = Uri.parse(apiBaseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return uri.replace(scheme: scheme).toString().replaceAll(RegExp(r'/$'), '');
  }

  static String rideWsUrl(String rideId, String accessToken) =>
      '$wsBaseUrl/ws/rides/$rideId?token=${Uri.encodeQueryComponent(accessToken)}';

  static String locationShareWsUrl(String accessToken) =>
      '$wsBaseUrl/ws/location-shares?token=${Uri.encodeQueryComponent(accessToken)}';
}
