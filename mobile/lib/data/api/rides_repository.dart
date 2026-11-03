import 'api_client.dart';
import 'friends_repository.dart';

class GeoPointDto {
  GeoPointDto({required this.lat, required this.lon});

  final double lat;
  final double lon;

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};
}

/// Valid self-reported participant statuses.
const participantStatuses = [
  'on_the_way',
  'riding',
  'paused',
  'reached',
];

String participantStatusLabel(String status) => switch (status) {
      'joined' => 'Joined',
      'on_the_way' => 'On the way',
      'riding' => 'Driving',
      'paused' => 'Stopped',
      'reached' => 'Arrived',
      _ => status,
    };

class ParticipantDto {
  ParticipantDto({
    required this.id,
    required this.rideId,
    required this.userId,
    required this.role,
    required this.status,
    this.lastSeenAt,
    this.distanceToHostM,
    this.distanceToDestinationM,
    this.user,
    this.lat,
    this.lon,
  });

  final String id;
  final String rideId;
  final String userId;
  final String role;
  final String status;
  final DateTime? lastSeenAt;
  final double? distanceToHostM;
  final double? distanceToDestinationM;
  final PublicUserDto? user;
  final double? lat;
  final double? lon;

  bool get isHost => role == 'host';
  String get name => user?.displayName ?? user?.username ?? 'Driver';
  bool get hasLocation => lat != null && lon != null;

  factory ParticipantDto.fromJson(Map<String, dynamic> json) => ParticipantDto(
        id: json['id'] as String? ?? json['user_id'] as String,
        rideId: json['ride_id'] as String? ?? '',
        userId: json['user_id'] as String,
        role: json['role'] as String? ?? 'participant',
        status: json['status'] as String? ?? 'joined',
        lastSeenAt: DateTime.tryParse(json['last_seen_at'] as String? ?? ''),
        distanceToHostM: (json['distance_to_host_m'] as num?)?.toDouble(),
        distanceToDestinationM:
            (json['distance_to_destination_m'] as num?)?.toDouble(),
        user: PublicUserDto.maybe(json['user']),
        lat: (json['lat'] as num?)?.toDouble(),
        lon: (json['lon'] as num?)?.toDouble(),
      );

  ParticipantDto copyWith({
    String? status,
    double? lat,
    double? lon,
    DateTime? lastSeenAt,
    double? distanceToHostM,
    double? distanceToDestinationM,
    PublicUserDto? user,
  }) =>
      ParticipantDto(
        id: id,
        rideId: rideId,
        userId: userId,
        role: role,
        status: status ?? this.status,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        distanceToHostM: distanceToHostM ?? this.distanceToHostM,
        distanceToDestinationM:
            distanceToDestinationM ?? this.distanceToDestinationM,
        user: user ?? this.user,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
      );
}

class RideDto {
  RideDto({
    required this.id,
    required this.hostId,
    required this.title,
    this.description,
    required this.visibility,
    required this.status,
    this.joinCode,
    this.inviteToken,
    this.host,
    this.scheduledAt,
    this.startedAt,
    this.endedAt,
    this.createdAt,
    this.startLat,
    this.startLon,
    this.destLat,
    this.destLon,
    this.participantCount = 0,
    this.isParticipant = false,
    this.participants = const [],
  });

  final String id;
  final String hostId;
  final String title;
  final String? description;
  final String visibility;
  final String status;

  /// Only present for participants.
  final String? joinCode;
  final String? inviteToken;
  final PublicUserDto? host;
  final DateTime? scheduledAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? createdAt;
  final double? startLat;
  final double? startLon;
  final double? destLat;
  final double? destLon;
  final int participantCount;
  final bool isParticipant;
  final List<ParticipantDto> participants;

  bool get isLive => status == 'live';
  bool get isScheduled => status == 'scheduled';
  bool get isOver => status == 'ended' || status == 'cancelled';
  bool get hasDestination => destLat != null && destLon != null;

  RideDto copyWith({String? status, List<ParticipantDto>? participants}) =>
      RideDto(
        id: id,
        hostId: hostId,
        title: title,
        description: description,
        visibility: visibility,
        status: status ?? this.status,
        joinCode: joinCode,
        inviteToken: inviteToken,
        host: host,
        scheduledAt: scheduledAt,
        startedAt: startedAt,
        endedAt: endedAt,
        createdAt: createdAt,
        startLat: startLat,
        startLon: startLon,
        destLat: destLat,
        destLon: destLon,
        participantCount: participants?.length ?? participantCount,
        isParticipant: isParticipant,
        participants: participants ?? this.participants,
      );

  factory RideDto.fromJson(Map<String, dynamic> json) {
    final participants = (json['participants'] as List<dynamic>? ?? [])
        .map((e) => ParticipantDto.fromJson(e as Map<String, dynamic>))
        .toList();
    return RideDto(
      id: json['id'] as String,
      hostId: json['host_id'] as String,
      title: json['title'] as String? ?? 'Drive',
      description: json['description'] as String?,
      visibility: json['visibility'] as String? ?? 'public',
      status: json['status'] as String? ?? 'scheduled',
      joinCode: json['join_code'] as String?,
      inviteToken: json['invite_token'] as String?,
      host: PublicUserDto.maybe(json['host']),
      scheduledAt: DateTime.tryParse(json['scheduled_at'] as String? ?? ''),
      startedAt: DateTime.tryParse(json['started_at'] as String? ?? ''),
      endedAt: DateTime.tryParse(json['ended_at'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      startLat: (json['start_lat'] as num?)?.toDouble(),
      startLon: (json['start_lon'] as num?)?.toDouble(),
      destLat: (json['dest_lat'] as num?)?.toDouble(),
      destLon: (json['dest_lon'] as num?)?.toDouble(),
      participantCount:
          (json['participant_count'] as num?)?.toInt() ?? participants.length,
      isParticipant: json['is_participant'] as bool? ?? false,
      participants: participants,
    );
  }
}

class LocationPointDto {
  LocationPointDto({
    required this.lat,
    required this.lon,
    required this.recordedAt,
    this.speedMps,
    this.heading,
    this.accuracyM,
    this.status,
  });

  final double lat;
  final double lon;
  final DateTime recordedAt;
  final double? speedMps;
  final double? heading;
  final double? accuracyM;
  final String? status;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'recorded_at': recordedAt.toUtc().toIso8601String(),
        if (speedMps != null) 'speed_mps': speedMps,
        if (heading != null) 'heading': heading,
        if (accuracyM != null) 'accuracy_m': accuracyM,
        if (status != null) 'status': status,
      };
}

class RidesRepository {
  RidesRepository(this._api);

  final ApiClient _api;

  /// [scope]: `discover` (public, upcoming/live) or `mine`.
  Future<List<RideDto>> listRides({
    String scope = 'discover',
    String? status,
    String? near,
    int? radiusM,
  }) async {
    final query = <String, String>{
      'scope': scope,
      if (status != null) 'status': status,
      if (near != null) 'near': near,
      if (radiusM != null) 'radius_m': '$radiusM',
    };
    final data = ApiClient.decodeMap(await _api.get('/rides', query: query));
    return (data['rides'] as List<dynamic>? ?? [])
        .map((e) => RideDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RideDto> createRide({
    required String title,
    String? description,
    String visibility = 'public',
    DateTime? scheduledAt,
    GeoPointDto? start,
    GeoPointDto? destination,
  }) async {
    final response = await _api.post('/rides', body: {
      'title': title,
      if (description != null) 'description': description,
      'visibility': visibility,
      if (scheduledAt != null)
        'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      if (start != null) 'start': start.toJson(),
      if (destination != null) 'destination': destination.toJson(),
    });
    return RideDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<RideDto> getRide(String id) async =>
      RideDto.fromJson(ApiClient.decodeMap(await _api.get('/rides/$id')));

  Future<RideDto> joinRide({String? joinCode, String? inviteToken}) async {
    final response = await _api.post('/rides/join', body: {
      if (joinCode != null) 'join_code': joinCode.trim().toUpperCase(),
      if (inviteToken != null) 'invite_token': inviteToken,
    });
    return RideDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<RideDto> startRide(String id) async => RideDto.fromJson(
      ApiClient.decodeMap(await _api.post('/rides/$id/start')));

  Future<RideDto> endRide(String id) async =>
      RideDto.fromJson(ApiClient.decodeMap(await _api.post('/rides/$id/end')));

  Future<RideDto> cancelRide(String id) async => RideDto.fromJson(
      ApiClient.decodeMap(await _api.post('/rides/$id/cancel')));

  Future<void> leaveRide(String id) async {
    ApiClient.decodeMap(await _api.post('/rides/$id/leave'));
  }

  Future<void> removeParticipant(String rideId, String userId) async {
    ApiClient.decodeMap(
        await _api.post('/rides/$rideId/participants/$userId/remove'));
  }

  Future<void> updateMyStatus(String rideId, String status) async {
    ApiClient.decodeMap(await _api.patch(
      '/rides/$rideId/me/status',
      body: {'status': status},
    ));
  }

  Future<void> postLocations(
      String rideId, List<LocationPointDto> points) async {
    ApiClient.decodeMap(await _api.post('/rides/$rideId/locations', body: {
      'points': points.map((p) => p.toJson()).toList(),
    }));
  }
}
