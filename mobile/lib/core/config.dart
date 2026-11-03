/// RideX API configuration.
///
/// Default points at the production VPS (nginx → API).
/// Override: `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000` (emulator)
class ApiConfig {
  ApiConfig._();

  /// Production host (Oracle VPS).
  static const String lanHost = '130.210.24.87';

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://130.210.24.87',
  );

  static const String apiPrefix = '/api/v1';

  static String get restBaseUrl => '$apiBaseUrl$apiPrefix';

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
