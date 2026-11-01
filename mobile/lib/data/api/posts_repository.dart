import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'friends_repository.dart';

class PostImageDto {
  PostImageDto({
    required this.id,
    required this.filePath,
    required this.thumbPath,
    required this.sortOrder,
  });

  final String id;
  final String filePath;
  final String thumbPath;
  final int sortOrder;

  factory PostImageDto.fromJson(Map<String, dynamic> json) => PostImageDto(
        id: json['id'] as String,
        filePath: json['file_path'] as String,
        thumbPath: json['thumb_path'] as String,
        sortOrder: json['sort_order'] as int? ?? 0,
      );
}

class CommentDto {
  CommentDto({
    required this.id,
    required this.postId,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.user,
  });

  final String id;
  final String postId;
  final String userId;
  final String body;
  final DateTime createdAt;
  final PublicUserDto? user;

  factory CommentDto.fromJson(Map<String, dynamic> json) => CommentDto(
        id: json['id'] as String,
        postId: json['post_id'] as String,
        userId: json['user_id'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        user: json['user'] != null
            ? PublicUserDto.fromJson(json['user'] as Map<String, dynamic>)
            : null,
      );
}

class PostDto {
  PostDto({
    required this.id,
    required this.authorId,
    this.caption,
    this.rideId,
    this.distanceKm,
    this.durationS,
    required this.likeCount,
    required this.commentCount,
    required this.createdAt,
    this.author,
    this.images = const [],
    this.likedByMe = false,
  });

  final String id;
  final String authorId;
  final String? caption;
  final String? rideId;
  final double? distanceKm;
  final int? durationS;
  final int likeCount;
  final int commentCount;
  final DateTime createdAt;
  final PublicUserDto? author;
  final List<PostImageDto> images;
  final bool likedByMe;

  factory PostDto.fromJson(Map<String, dynamic> json) => PostDto(
        id: json['id'] as String,
        authorId: json['author_id'] as String,
        caption: json['caption'] as String?,
        rideId: json['ride_id'] as String?,
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        durationS: json['duration_s'] as int?,
        likeCount: json['like_count'] as int? ?? 0,
        commentCount: json['comment_count'] as int? ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
        author: json['author'] != null
            ? PublicUserDto.fromJson(json['author'] as Map<String, dynamic>)
            : null,
        images: (json['images'] as List<dynamic>? ?? [])
            .map((e) => PostImageDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        likedByMe: json['liked_by_me'] as bool? ?? false,
      );

  PostDto copyWith({int? likeCount, bool? likedByMe, int? commentCount}) =>
      PostDto(
        id: id,
        authorId: authorId,
        caption: caption,
        rideId: rideId,
        distanceKm: distanceKm,
        durationS: durationS,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
        createdAt: createdAt,
        author: author,
        images: images,
        likedByMe: likedByMe ?? this.likedByMe,
      );
}

class PostFeedDto {
  PostFeedDto({required this.posts, this.nextCursor});

  final List<PostDto> posts;
  final String? nextCursor;

  factory PostFeedDto.fromJson(Map<String, dynamic> json) => PostFeedDto(
        posts: (json['posts'] as List<dynamic>)
            .map((e) => PostDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextCursor: json['next_cursor'] as String?,
      );
}

class LikeResultDto {
  LikeResultDto({required this.liked, required this.likeCount});

  final bool liked;
  final int likeCount;

  factory LikeResultDto.fromJson(Map<String, dynamic> json) => LikeResultDto(
        liked: json['liked'] as bool,
        likeCount: json['like_count'] as int,
      );
}

class PostsRepository {
  PostsRepository(this._api);

  final ApiClient _api;

  Future<PostFeedDto> feed({String? cursor, int limit = 20}) async {
    final query = <String, String>{
      'limit': '$limit',
      if (cursor != null) 'cursor': cursor,
    };
    final response = await _api.get('/posts', query: query);
    return PostFeedDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<PostDto> createPost({
    String? caption,
    List<File> images = const [],
    double? distanceKm,
    int? durationS,
  }) async {
    final fields = <String, String>{
      if (caption != null) 'caption': caption,
      if (distanceKm != null) 'distance_km': '$distanceKm',
      if (durationS != null) 'duration_s': '$durationS',
    };
    final files = <http.MultipartFile>[];
    for (var i = 0; i < images.length; i++) {
      files.add(await http.MultipartFile.fromPath(
        'images',
        images[i].path,
        filename: 'image_$i.jpg',
      ));
    }
    final response = await _api.postMultipart(
      '/posts',
      fields: fields,
      files: files,
    );
    return PostDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<LikeResultDto> toggleLike(String postId) async {
    final response = await _api.post('/posts/$postId/like');
    return LikeResultDto.fromJson(ApiClient.decodeMap(response));
  }

  Future<List<CommentDto>> listComments(String postId) async {
    final response = await _api.get('/posts/$postId/comments');
    return ApiClient.decodeList(response)
        .map((e) => CommentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CommentDto> addComment(String postId, String body) async {
    final response = await _api.post(
      '/posts/$postId/comments',
      body: {'body': body},
    );
    return CommentDto.fromJson(ApiClient.decodeMap(response));
  }
}
