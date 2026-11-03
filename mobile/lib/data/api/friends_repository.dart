import 'api_client.dart';
import 'auth_repository.dart';

class PublicUserDto {
  PublicUserDto({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarPath,
    this.bio,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarPath;
  final String? bio;

  factory PublicUserDto.fromJson(Map<String, dynamic> json) => PublicUserDto(
        id: json['id'] as String,
        username: json['username'] as String? ?? '',
        displayName: json['display_name'] as String? ?? 'Driver',
        avatarPath: json['avatar_path'] as String?,
        bio: json['bio'] as String?,
      );

  factory PublicUserDto.fromAuthUser(AuthUser user) => PublicUserDto(
        id: user.id,
        username: user.username,
        displayName: user.displayName,
        avatarPath: user.avatarPath,
        bio: user.bio,
      );

  static PublicUserDto? maybe(Object? json) =>
      json is Map<String, dynamic> ? PublicUserDto.fromJson(json) : null;
}

/// Relationship between the signed-in user and a search result.
enum FriendshipState { none, friends, incoming, outgoing }

class UserSearchResultDto {
  UserSearchResultDto({required this.user, required this.friendship});

  final PublicUserDto user;
  final FriendshipState friendship;

  factory UserSearchResultDto.fromJson(Map<String, dynamic> json) =>
      UserSearchResultDto(
        user: PublicUserDto.fromJson(json),
        friendship: switch (json['friendship']) {
          'friends' => FriendshipState.friends,
          'incoming' => FriendshipState.incoming,
          'outgoing' => FriendshipState.outgoing,
          _ => FriendshipState.none,
        },
      );
}

class FriendshipDto {
  FriendshipDto({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    required this.status,
    this.createdAt,
    this.user,
    this.requester,
    this.addressee,
  });

  final String id;
  final String requesterId;
  final String addresseeId;
  final String status;
  final DateTime? createdAt;

  /// The other party (not me).
  final PublicUserDto? user;
  final PublicUserDto? requester;
  final PublicUserDto? addressee;

  factory FriendshipDto.fromJson(Map<String, dynamic> json) => FriendshipDto(
        id: json['id'] as String,
        requesterId: json['requester_id'] as String,
        addresseeId: json['addressee_id'] as String,
        status: json['status'] as String,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        user: PublicUserDto.maybe(json['user']),
        requester: PublicUserDto.maybe(json['requester']),
        addressee: PublicUserDto.maybe(json['addressee']),
      );
}

class FriendRequestsDto {
  FriendRequestsDto({required this.incoming, required this.outgoing});

  final List<FriendshipDto> incoming;
  final List<FriendshipDto> outgoing;

  factory FriendRequestsDto.fromJson(Map<String, dynamic> json) =>
      FriendRequestsDto(
        incoming: (json['incoming'] as List<dynamic>? ?? [])
            .map((e) => FriendshipDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        outgoing: (json['outgoing'] as List<dynamic>? ?? [])
            .map((e) => FriendshipDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class UserStatsDto {
  UserStatsDto({
    this.friends = 0,
    this.ridesHosted = 0,
    this.ridesJoined = 0,
    this.posts = 0,
  });

  final int friends;
  final int ridesHosted;
  final int ridesJoined;
  final int posts;

  factory UserStatsDto.fromJson(Map<String, dynamic> json) => UserStatsDto(
        friends: (json['friends'] as num?)?.toInt() ?? 0,
        ridesHosted: (json['rides_hosted'] as num?)?.toInt() ?? 0,
        ridesJoined: (json['rides_joined'] as num?)?.toInt() ?? 0,
        posts: (json['posts'] as num?)?.toInt() ?? 0,
      );
}

class FriendsRepository {
  FriendsRepository(this._api);

  final ApiClient _api;

  Future<List<PublicUserDto>> listFriends() async {
    final data = ApiClient.decodeMap(await _api.get('/friends'));
    return (data['friends'] as List<dynamic>? ?? [])
        .map((e) => PublicUserDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<FriendRequestsDto> listRequests() async {
    return FriendRequestsDto.fromJson(
        ApiClient.decodeMap(await _api.get('/friends/requests')));
  }

  Future<List<UserSearchResultDto>> searchUsers(String query) async {
    final data = ApiClient.decodeMap(
        await _api.get('/users/search', query: {'q': query}));
    return (data['users'] as List<dynamic>? ?? [])
        .map((e) => UserSearchResultDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<UserStatsDto> myStats() async {
    return UserStatsDto.fromJson(
        ApiClient.decodeMap(await _api.get('/users/me/stats')));
  }

  Future<FriendshipDto> sendRequest(String username) async {
    final response =
        await _api.post('/friends/requests', body: {'username': username});
    return FriendshipDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<FriendshipDto> acceptRequest(String requestId) async {
    final response = await _api.post('/friends/requests/$requestId/accept');
    return FriendshipDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<void> declineRequest(String requestId) async {
    ApiClient.decodeMap(
        await _api.post('/friends/requests/$requestId/decline'));
  }

  Future<void> cancelRequest(String requestId) async {
    ApiClient.decodeMap(await _api.delete('/friends/requests/$requestId'));
  }

  Future<void> unfriend(String userId) async {
    ApiClient.decodeMap(await _api.delete('/friends/$userId'));
  }
}
