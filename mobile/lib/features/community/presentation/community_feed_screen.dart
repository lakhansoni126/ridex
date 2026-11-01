import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/api/posts_repository.dart';
import '../../../shared/widgets/glass_container.dart';

final communityFeedProvider =
    FutureProvider.autoDispose<PostFeedDto>((ref) {
  return ref.watch(postsRepositoryProvider).feed();
});

class CommunityFeedScreen extends ConsumerWidget {
  const CommunityFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(communityFeedProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Community'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/community/compose'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.accent,
        onPressed: () => context.push('/community/compose'),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: RefreshIndicator(
        color: AppTheme.accent,
        onRefresh: () async => ref.invalidate(communityFeedProvider),
        child: feedAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(child: Text('$e', style: theme.textTheme.bodyMedium)),
            ],
          ),
          data: (feed) {
            if (feed.posts.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Text(
                      'No posts yet. Share a drive moment.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: feed.posts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, i) {
                final post = feed.posts[i];
                return _PostCard(post: post);
              },
            );
          },
        ),
      ),
    );
  }
}

class _PostCard extends ConsumerStatefulWidget {
  const _PostCard({required this.post});
  final PostDto post;

  @override
  ConsumerState<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<_PostCard> {
  late PostDto _post;
  final _comment = TextEditingController();
  List<CommentDto>? _comments;
  bool _showComments = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    final result =
        await ref.read(postsRepositoryProvider).toggleLike(_post.id);
    setState(() {
      _post = _post.copyWith(
        likedByMe: result.liked,
        likeCount: result.likeCount,
      );
    });
  }

  Future<void> _loadComments() async {
    setState(() => _showComments = true);
    final list =
        await ref.read(postsRepositoryProvider).listComments(_post.id);
    setState(() => _comments = list);
  }

  Future<void> _addComment() async {
    final body = _comment.text.trim();
    if (body.isEmpty) return;
    final c =
        await ref.read(postsRepositoryProvider).addComment(_post.id, body);
    _comment.clear();
    setState(() {
      _comments = [...?_comments, c];
      _post = _post.copyWith(commentCount: _post.commentCount + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = DateFormat.MMMd().add_jm().format(_post.createdAt.toLocal());

    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _post.author?.displayName ?? 'Driver',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600),
          ),
          Text(when, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12)),
          if (_post.caption != null && _post.caption!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_post.caption!, style: const TextStyle(color: Colors.white)),
          ],
          if (_post.images.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: FutureBuilder<String?>(
                  future: ref.read(tokenStoreProvider).readAccessToken(),
                  builder: (context, snap) {
                    final token = snap.data;
                    return Image.network(
                      '${ApiConfig.apiBaseUrl}/api/v1/media/${_post.images.first.thumbPath}',
                      fit: BoxFit.cover,
                      headers: token == null
                          ? null
                          : {'Authorization': 'Bearer $token'},
                      errorBuilder: (_, __, ___) => Container(
                        color: AppTheme.surface,
                        alignment: Alignment.center,
                        child: const Icon(Icons.image_outlined,
                            color: Colors.white38),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          if (_post.distanceKm != null) ...[
            const SizedBox(height: 8),
            Text(
              '${_post.distanceKm!.toStringAsFixed(1)} km'
              '${_post.durationS != null ? ' · ${(_post.durationS! / 60).round()} min' : ''}',
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                onPressed: _toggleLike,
                icon: Icon(
                  _post.likedByMe ? Icons.favorite : Icons.favorite_border,
                  color: _post.likedByMe ? AppTheme.accent : Colors.white70,
                ),
              ),
              Text('${_post.likeCount}',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(width: 16),
              IconButton(
                onPressed: _loadComments,
                icon: const Icon(Icons.chat_bubble_outline,
                    color: Colors.white70),
              ),
              Text('${_post.commentCount}',
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
          if (_showComments) ...[
            const Divider(color: Colors.white12),
            if (_comments == null)
              const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              )
            else
              ..._comments!.map(
                (c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${c.user?.displayName ?? 'Driver'}: ${c.body}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _comment,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Add a comment',
                      hintStyle: TextStyle(color: AppTheme.textSecondary),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _addComment,
                  icon: const Icon(Icons.send, color: AppTheme.accent),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
