import 'api_client.dart';
import 'friends_repository.dart';
import 'rides_repository.dart';

class LocationShareGrantDto {
  LocationShareGrantDto({
    required this.friendUserId,
    this.revokedAt,
    this.friend,
  });

  final String friendUserId;
  final DateTime? revokedAt;
  final PublicUserDto? friend;

  bool get isActive => revokedAt == null;

  factory LocationShareGrantDto.fromJson(Map<String, dynamic> json) =>
      LocationShareGrantDto(
        friendUserId: json['friend_user_id'] as String,
        revokedAt: DateTime.tryParse(json['revoked_at'] as String? ?? ''),
        friend: PublicUserDto.maybe(json['friend']),
      );
}

class LocationShareDto {
  LocationShareDto({
    required this.id,
    required this.ownerId,
    required this.duration,
    required this.isActive,
    this.expiresAt,
    this.lastSeenAt,
    this.createdAt,
    this.lat,
    this.lon,
    this.owner,
    this.grants = const [],
  });

  final String id;
  final String ownerId;
  final String duration;
  final bool isActive;
  final DateTime? expiresAt;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;
  final double? lat;
  final double? lon;
  final PublicUserDto? owner;
  final List<LocationShareGrantDto> grants;

  bool get hasLocation => lat != null && lon != null;

  String get durationLabel => switch (duration) {
        '1h' => '1 hour',
        '8h' => '8 hours',
        'indefinite' => 'Until stopped',
        _ => duration,
      };

  LocationShareDto copyWith({
    double? lat,
    double? lon,
    DateTime? lastSeenAt,
    bool? isActive,
  }) =>
      LocationShareDto(
        id: id,
        ownerId: ownerId,
        duration: duration,
        isActive: isActive ?? this.isActive,
        expiresAt: expiresAt,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        createdAt: createdAt,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        owner: owner,
        grants: grants,
      );

  factory LocationShareDto.fromJson(Map<String, dynamic> json) =>
      LocationShareDto(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        duration: json['duration'] as String? ?? '',
        isActive: json['is_active'] as bool? ?? false,
        expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
        lastSeenAt: DateTime.tryParse(json['last_seen_at'] as String? ?? ''),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        lat: (json['lat'] as num?)?.toDouble(),
        lon: (json['lon'] as num?)?.toDouble(),
        owner: PublicUserDto.maybe(json['owner']),
        grants: (json['grants'] as List<dynamic>? ?? [])
            .map((e) =>
                LocationShareGrantDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class LocationSharesListDto {
  LocationSharesListDto({required this.mine, required this.sharedWithMe});

  final List<LocationShareDto> mine;
  final List<LocationShareDto> sharedWithMe;

  LocationShareDto? get activeMine {
    for (final s in mine) {
      if (s.isActive) return s;
    }
    return null;
  }

  factory LocationSharesListDto.fromJson(Map<String, dynamic> json) =>
      LocationSharesListDto(
        mine: (json['mine'] as List<dynamic>? ?? [])
            .map((e) => LocationShareDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        sharedWithMe: (json['shared_with_me'] as List<dynamic>? ?? [])
            .map((e) => LocationShareDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class SharesRepository {
  SharesRepository(this._api);

  final ApiClient _api;

  /// Duration values: `1h`, `8h`, `indefinite`.
  Future<LocationShareDto> createShare({
    required String duration,
    required List<String> friendIds,
  }) async {
    final response = await _api.post('/location-shares', body: {
      'duration': duration,
      'friend_ids': friendIds,
    });
    return LocationShareDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<LocationSharesListDto> listShares() async {
    return LocationSharesListDto.fromJson(
        ApiClient.decodeMap(await _api.get('/location-shares')));
  }

  Future<void> stopShare(String shareId) async {
    ApiClient.decodeMap(await _api.post('/location-shares/$shareId/stop'));
  }

  Future<void> revokeGrant(String shareId, String friendId) async {
    ApiClient.decodeMap(
        await _api.delete('/location-shares/$shareId/grants/$friendId'));
  }

  Future<void> postLocations(
    String shareId,
    List<LocationPointDto> points,
  ) async {
    ApiClient.decodeMap(
      await _api.post('/location-shares/$shareId/locations', body: {
        'points': points.map((p) => p.toJson()).toList(),
      }),
    );
  }
}
