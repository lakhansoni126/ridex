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
        username: json['username'] as String,
        displayName: json['display_name'] as String,
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
}

class FriendshipDto {
  FriendshipDto({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    required this.status,
    this.requester,
    this.addressee,
  });

  final String id;
  final String requesterId;
  final String addresseeId;
  final String status;
  final PublicUserDto? requester;
  final PublicUserDto? addressee;

  factory FriendshipDto.fromJson(Map<String, dynamic> json) => FriendshipDto(
        id: json['id'] as String,
        requesterId: json['requester_id'] as String,
        addresseeId: json['addressee_id'] as String,
        status: json['status'] as String,
        requester: json['requester'] != null
            ? PublicUserDto.fromJson(json['requester'] as Map<String, dynamic>)
            : null,
        addressee: json['addressee'] != null
            ? PublicUserDto.fromJson(json['addressee'] as Map<String, dynamic>)
            : null,
      );
}

class FriendRequestsDto {
  FriendRequestsDto({required this.incoming, required this.outgoing});

  final List<FriendshipDto> incoming;
  final List<FriendshipDto> outgoing;

  factory FriendRequestsDto.fromJson(Map<String, dynamic> json) =>
      FriendRequestsDto(
        incoming: (json['incoming'] as List<dynamic>)
            .map((e) => FriendshipDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        outgoing: (json['outgoing'] as List<dynamic>)
            .map((e) => FriendshipDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class FriendsRepository {
  FriendsRepository(this._api);

  final ApiClient _api;

  Future<List<PublicUserDto>> listFriends() async {
    final response = await _api.get('/friends');
    final data = ApiClient.decodeMap(response);
    return (data['friends'] as List<dynamic>)
        .map((e) => PublicUserDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<FriendRequestsDto> listRequests() async {
    final response = await _api.get('/friends/requests');
    return FriendRequestsDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<FriendshipDto> sendRequest(String username) async {
    final response = await _api.post(
      '/friends/requests',
      body: {'username': username},
    );
    return FriendshipDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<FriendshipDto> acceptRequest(String requestId) async {
    final response = await _api.post('/friends/requests/$requestId/accept');
    return FriendshipDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<FriendshipDto> declineRequest(String requestId) async {
    final response = await _api.post('/friends/requests/$requestId/decline');
    return FriendshipDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<void> unfriend(String userId) async {
    await _api.delete('/friends/$userId');
  }
}
