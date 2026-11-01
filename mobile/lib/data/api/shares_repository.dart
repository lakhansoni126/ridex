import 'api_client.dart';
import 'friends_repository.dart';
import 'rides_repository.dart';

class LocationShareGrantDto {
  LocationShareGrantDto({
    required this.id,
    required this.shareId,
    required this.friendUserId,
    this.revokedAt,
    this.friend,
  });

  final String id;
  final String shareId;
  final String friendUserId;
  final DateTime? revokedAt;
  final PublicUserDto? friend;

  factory LocationShareGrantDto.fromJson(Map<String, dynamic> json) =>
      LocationShareGrantDto(
        id: json['id'] as String,
        shareId: json['share_id'] as String,
        friendUserId: json['friend_user_id'] as String,
        revokedAt: json['revoked_at'] != null
            ? DateTime.tryParse(json['revoked_at'] as String)
            : null,
        friend: json['friend'] != null
            ? PublicUserDto.fromJson(json['friend'] as Map<String, dynamic>)
            : null,
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
  final double? lat;
  final double? lon;
  final PublicUserDto? owner;
  final List<LocationShareGrantDto> grants;

  factory LocationShareDto.fromJson(Map<String, dynamic> json) =>
      LocationShareDto(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        duration: json['duration'] as String,
        isActive: json['is_active'] as bool? ?? false,
        expiresAt: json['expires_at'] != null
            ? DateTime.tryParse(json['expires_at'] as String)
            : null,
        lastSeenAt: json['last_seen_at'] != null
            ? DateTime.tryParse(json['last_seen_at'] as String)
            : null,
        lat: (json['lat'] as num?)?.toDouble(),
        lon: (json['lon'] as num?)?.toDouble(),
        owner: json['owner'] != null
            ? PublicUserDto.fromJson(json['owner'] as Map<String, dynamic>)
            : null,
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

  factory LocationSharesListDto.fromJson(Map<String, dynamic> json) =>
      LocationSharesListDto(
        mine: (json['mine'] as List<dynamic>)
            .map((e) => LocationShareDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        sharedWithMe: (json['shared_with_me'] as List<dynamic>)
            .map((e) => LocationShareDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class SharesRepository {
  SharesRepository(this._api);

  final ApiClient _api;

  /// Duration values: `1h`, `8h`, `indefinite`
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
    final response = await _api.get('/location-shares');
    return LocationSharesListDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<LocationShareDto> stopShare(String shareId) async {
    final response = await _api.post('/location-shares/$shareId/stop');
    return LocationShareDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<LocationShareDto> revokeGrant(String shareId, String friendId) async {
    final response =
        await _api.delete('/location-shares/$shareId/grants/$friendId');
    return LocationShareDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<void> postLocations(
    String shareId,
    List<LocationPointDto> points,
  ) async {
    await _api.post('/location-shares/$shareId/locations', body: {
      'points': points.map((p) => p.toJson()).toList(),
    });
  }
}
