import 'api_client.dart';

class GeoPointDto {
  GeoPointDto({required this.lat, required this.lon});

  final double lat;
  final double lon;

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};
}

class WaypointDto {
  WaypointDto({required this.lat, required this.lon, this.name});

  final double lat;
  final double lon;
  final String? name;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        if (name != null) 'name': name,
      };
}

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
    this.displayName,
    this.username,
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
  final String? displayName;
  final String? username;
  final double? lat;
  final double? lon;

  factory ParticipantDto.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return ParticipantDto(
      id: json['id'] as String,
      rideId: json['ride_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
      status: json['status'] as String,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.tryParse(json['last_seen_at'] as String)
          : null,
      distanceToHostM: (json['distance_to_host_m'] as num?)?.toDouble(),
      distanceToDestinationM:
          (json['distance_to_destination_m'] as num?)?.toDouble(),
      displayName: user?['display_name'] as String?,
      username: user?['username'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lon: (json['lon'] as num?)?.toDouble(),
    );
  }

  ParticipantDto copyWith({
    String? status,
    double? lat,
    double? lon,
    DateTime? lastSeenAt,
    double? distanceToHostM,
    double? distanceToDestinationM,
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
        displayName: displayName,
        username: username,
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
    required this.joinCode,
    required this.inviteToken,
    this.scheduledAt,
    this.startedAt,
    this.endedAt,
    this.startLat,
    this.startLon,
    this.destLat,
    this.destLon,
    this.participants = const [],
  });

  final String id;
  final String hostId;
  final String title;
  final String? description;
  final String visibility;
  final String status;
  final String joinCode;
  final String inviteToken;
  final DateTime? scheduledAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final double? startLat;
  final double? startLon;
  final double? destLat;
  final double? destLon;
  final List<ParticipantDto> participants;

  factory RideDto.fromJson(Map<String, dynamic> json) => RideDto(
        id: json['id'] as String,
        hostId: json['host_id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        visibility: json['visibility'] as String,
        status: json['status'] as String,
        joinCode: json['join_code'] as String,
        inviteToken: json['invite_token'] as String,
        scheduledAt: json['scheduled_at'] != null
            ? DateTime.tryParse(json['scheduled_at'] as String)
            : null,
        startedAt: json['started_at'] != null
            ? DateTime.tryParse(json['started_at'] as String)
            : null,
        endedAt: json['ended_at'] != null
            ? DateTime.tryParse(json['ended_at'] as String)
            : null,
        startLat: (json['start_lat'] as num?)?.toDouble(),
        startLon: (json['start_lon'] as num?)?.toDouble(),
        destLat: (json['dest_lat'] as num?)?.toDouble(),
        destLon: (json['dest_lon'] as num?)?.toDouble(),
        participants: (json['participants'] as List<dynamic>? ?? [])
            .map((e) => ParticipantDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
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

  Future<List<RideDto>> listRides({
    String? status,
    String? near,
    int? radiusM,
  }) async {
    final query = <String, String>{
      if (status != null) 'status': status,
      if (near != null) 'near': near,
      if (radiusM != null) 'radius_m': '$radiusM',
    };
    final response = await _api.get('/rides', query: query.isEmpty ? null : query);
    final data = ApiClient.decodeMap(response);
    return (data['rides'] as List<dynamic>)
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
    List<WaypointDto>? waypoints,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      if (description != null) 'description': description,
      'visibility': visibility,
      if (scheduledAt != null)
        'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      if (start != null) 'start': start.toJson(),
      if (destination != null) 'destination': destination.toJson(),
      if (waypoints != null)
        'waypoints': waypoints.map((w) => w.toJson()).toList(),
    };
    final response = await _api.post('/rides', body: body);
    return RideDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<RideDto> getRide(String id) async {
    final response = await _api.get('/rides/$id');
    return RideDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<RideDto> joinRide({String? joinCode, String? inviteToken}) async {
    final response = await _api.post('/rides/join', body: {
      if (joinCode != null) 'join_code': joinCode,
      if (inviteToken != null) 'invite_token': inviteToken,
    });
    return RideDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<RideDto> startRide(String id) async {
    final response = await _api.post('/rides/$id/start');
    return RideDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<RideDto> endRide(String id) async {
    final response = await _api.post('/rides/$id/end');
    return RideDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<ParticipantDto> updateMyStatus(String rideId, String status) async {
    final response = await _api.patch(
      '/rides/$rideId/me/status',
      body: {'status': status},
    );
    return ParticipantDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<void> postLocations(String rideId, List<LocationPointDto> points) async {
    await _api.post('/rides/$rideId/locations', body: {
      'points': points.map((p) => p.toJson()).toList(),
    });
  }
}
