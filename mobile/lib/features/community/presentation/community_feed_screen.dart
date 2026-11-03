import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../data/api/posts_repository.dart';
import '../../../shared/ui/ui.dart';
import '../../auth/application/auth_notifier.dart';

// ── Paginated feed state ──────────────────────────────────────────────────

class FeedState {
  const FeedState({
    this.posts = const [],
    this.nextCursor,
    this.loading = true,
    this.loadingMore = false,
    this.error,
    this.loadMoreError,
  });

  final List<PostDto> posts;
  final String? nextCursor;

  /// First page loading.
  final bool loading;
  final bool loadingMore;
  final Object? error;
  final Object? loadMoreError;

  bool get hasMore => nextCursor != null;

  FeedState copyWith({
    List<PostDto>? posts,
    String? nextCursor,
    bool clearCursor = false,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) =>
      FeedState(
        posts: posts ?? this.posts,
        nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
        loadMoreError:
            clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
      );
}

class FeedNotifier extends StateNotifier<FeedState> {
  FeedNotifier(this._repo) : super(const FeedState()) {
    refresh();
  }

  final PostsRepository _repo;
  static const _pageSize = 20;

  Future<void> refresh() async {
    if (state.posts.isEmpty) {
      state = state.copyWith(loading: true, clearError: true);
    }
    try {
      final page = await _repo.feed(limit: _pageSize);
      if (!mounted) return;
      state = FeedState(
        posts: page.posts,
        nextCursor: page.nextCursor,
        loading: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null || state.loadingMore || state.loading) return;
    state = state.copyWith(loadingMore: true, clearLoadMoreError: true);
    try {
      final page = await _repo.feed(cursor: cursor, limit: _pageSize);
      if (!mounted) return;
      final known = state.posts.map((p) => p.id).toSet();
      state = state.copyWith(
        posts: [
          ...state.posts,
          ...page.posts.where((p) => !known.contains(p.id)),
        ],
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        loadingMore: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loadingMore: false, loadMoreError: e);
    }
  }

  void prepend(PostDto post) {
    state = state.copyWith(
      posts: [post, ...state.posts.where((p) => p.id != post.id)],
      loading: false,
      clearError: true,
    );
  }

  void replace(PostDto post) {
    state = state.copyWith(
      posts: [for (final p in state.posts) p.id == post.id ? post : p],
    );
  }

  void remove(String postId) {
    state = state.copyWith(
      posts: state.posts.where((p) => p.id != postId).toList(),
    );
  }

  PostDto? find(String postId) {
    for (final p in state.posts) {
      if (p.id == postId) return p;
    }
    return null;
  }

  /// Adjusts the comment count of a cached post by [delta].
  void bumpComments(String postId, int delta) {
    final p = find(postId);
    if (p == null) return;
    replace(
        p.copyWith(commentCount: (p.commentCount + delta).clamp(0, 1 << 30)));
  }

  /// Optimistic like toggle; reconciles with the server, reverts on error.
  Future<void> toggleLike(String postId) async {
    final before = find(postId);
    if (before == null) return;
    final liked = !before.likedByMe;
    replace(before.copyWith(
      likedByMe: liked,
      likeCount: (before.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 30),
    ));
    try {
      final result = await _repo.toggleLike(postId);
      final current = find(postId);
      if (current != null && mounted) {
        replace(current.copyWith(
          likedByMe: result.liked,
          likeCount: result.likeCount,
        ));
      }
    } catch (e) {
      final current = find(postId);
      if (current != null && mounted) {
        replace(current.copyWith(
          likedByMe: before.likedByMe,
          likeCount: before.likeCount,
        ));
      }
      rethrow;
    }
  }
}

final communityFeedProvider =
    StateNotifierProvider<FeedNotifier, FeedState>((ref) {
  // Rebuild (dropping cached likes/posts) whenever the signed-in user changes.
  ref.watch(authNotifierProvider.select((s) => s.user?.id));
  return FeedNotifier(ref.watch(postsRepositoryProvider));
});

// ── Screen ────────────────────────────────────────────────────────────────

class CommunityFeedScreen extends ConsumerStatefulWidget {
  const CommunityFeedScreen({super.key});

  @override
  ConsumerState<CommunityFeedScreen> createState() =>
      _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends ConsumerState<CommunityFeedScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.maxScrollExtent - pos.pixels < 600) {
      ref.read(communityFeedProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(communityFeedProvider);
    final notifier = ref.read(communityFeedProvider.notifier);

    final List<Widget> slivers;
    if (feed.loading && feed.posts.isEmpty) {
      slivers = const [RxSliverLoading()];
    } else if (feed.error != null && feed.posts.isEmpty) {
      slivers = [
        RxSliverCenter(
          child: RxErrorState(error: feed.error!, onRetry: notifier.refresh),
        ),
      ];
    } else if (feed.posts.isEmpty) {
      slivers = [
        RxSliverCenter(
          child: RxEmptyState(
            icon: CupertinoIcons.photo_on_rectangle,
            title: 'No posts yet',
            message: 'Share a photo from your last drive with the community.',
            actionLabel: 'Share a Drive',
            onAction: () => context.push('/feed/compose'),
          ),
        ),
      ];
    } else {
      slivers = [
        SliverPadding(
          padding:
              const EdgeInsets.fromLTRB(RxSpace.m, RxSpace.s, RxSpace.m, 0),
          sliver: SliverList.separated(
            itemCount: feed.posts.length,
            separatorBuilder: (_, __) => const SizedBox(height: RxSpace.m),
            itemBuilder: (context, i) => PostCell(
              key: ValueKey(feed.posts[i].id),
              post: feed.posts[i],
            ),
          ),
        ),
        SliverToBoxAdapter(child: _footer(feed, notifier)),
      ];
    }

    return RxLargeTitlePage(
      title: 'Feed',
      controller: _scroll,
      trailing: RxNavIconButton(
        icon: CupertinoIcons.square_pencil,
        semanticLabel: 'New post',
        onPressed: () => context.push('/feed/compose'),
      ),
      onRefresh: notifier.refresh,
      slivers: slivers,
    );
  }

  Widget _footer(FeedState feed, FeedNotifier notifier) {
    final rx = context.rx;
    if (feed.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(RxSpace.l),
        child: CupertinoActivityIndicator(),
      );
    }
    if (feed.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.all(RxSpace.m),
        child: Center(
          child: RxButton.plain(
            label: "Couldn't load more · Retry",
            onPressed: notifier.loadMore,
          ),
        ),
      );
    }
    if (!feed.hasMore) {
      return Padding(
        padding: const EdgeInsets.all(RxSpace.l),
        child: Text("You're all caught up",
            style: rx.footnote, textAlign: TextAlign.center),
      );
    }
    return const SizedBox(height: RxSpace.l);
  }
}

// ── Post cell ─────────────────────────────────────────────────────────────

/// One post as a card. Also used by the post detail screen ([fullSize]).
class PostCell extends ConsumerWidget {
  const PostCell({
    super.key,
    required this.post,
    this.fullSize = false,
    this.onDeleted,
    this.onToggleLike,
  });

  final PostDto post;
  final bool fullSize;
  final VoidCallback? onDeleted;

  /// Overrides the default feed-backed like toggle (e.g. on detail pages
  /// for posts that aren't in the cached feed).
  final Future<void> Function()? onToggleLike;

  Future<void> _like(BuildContext context, WidgetRef ref) async {
    HapticFeedback.lightImpact();
    try {
      if (onToggleLike != null) {
        await onToggleLike!();
      } else {
        await ref.read(communityFeedProvider.notifier).toggleLike(post.id);
      }
    } catch (e) {
      if (context.mounted) showRxError(context, e);
    }
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, bool mine) async {
    final choice = await showRxActionSheet<String>(
      context,
      actions: [
        if (mine)
          const RxSheetAction(
              label: 'Delete Post', value: 'delete', destructive: true),
        if (!mine)
          const RxSheetAction(label: 'View Comments', value: 'comments'),
      ],
    );
    if (!context.mounted) return;
    if (choice == 'comments') {
      context.push('/feed/post/${post.id}', extra: post);
    } else if (choice == 'delete') {
      final ok = await confirmRx(
        context,
        title: 'Delete this post?',
        message: 'This removes the post and its comments for everyone.',
        confirmLabel: 'Delete',
      );
      if (!ok || !context.mounted) return;
      try {
        await ref.read(postsRepositoryProvider).deletePost(post.id);
        ref.read(communityFeedProvider.notifier).remove(post.id);
        if (context.mounted) showRxToast(context, 'Post deleted');
        onDeleted?.call();
      } catch (e) {
        if (context.mounted) showRxError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rx = context.rx;
    final me = ref.watch(authNotifierProvider).user;
    final mine = me != null && me.id == post.authorId;
    final name = post.author?.displayName ?? 'Driver';
    final openDetail = fullSize
        ? null
        : () => context.push('/feed/post/${post.id}', extra: post);

    return RxCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(RxSpace.m, 12, 4, 8),
            child: Row(
              children: [
                RxAvatar(
                    name: name, avatarPath: post.author?.avatarPath, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: rx.headline, overflow: TextOverflow.ellipsis),
                      Text(relativeTime(post.createdAt), style: rx.caption),
                    ],
                  ),
                ),
                if (mine || !fullSize)
                  Semantics(
                    button: true,
                    label: 'Post options',
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: RxSpace.minTouch,
                      onPressed: () => _menu(context, ref, mine),
                      child: Icon(CupertinoIcons.ellipsis,
                          color: rx.secondaryLabel, size: 20),
                    ),
                  ),
              ],
            ),
          ),

          // Images
          if (post.images.isNotEmpty)
            _PostImages(
              images: post.images,
              fullSize: fullSize,
              onDoubleTap: () {
                if (!post.likedByMe) _like(context, ref);
              },
              onTap: openDetail,
            ),

          // Caption
          if (post.caption != null && post.caption!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(RxSpace.m, 12, RxSpace.m, 0),
              child: Text(
                post.caption!,
                style: rx.body,
                maxLines: fullSize ? null : 6,
                overflow: fullSize ? null : TextOverflow.ellipsis,
              ),
            ),

          // Drive stats
          if (post.distanceKm != null || post.durationS != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(RxSpace.m, 10, RxSpace.m, 0),
              child: Wrap(
                spacing: RxSpace.s,
                children: [
                  if (post.distanceKm != null)
                    RxPill(
                      label: '${post.distanceKm!.toStringAsFixed(1)} km',
                      color: rx.info,
                      icon: CupertinoIcons.map,
                    ),
                  if (post.durationS != null)
                    RxPill(
                      label: formatDuration(post.durationS!),
                      color: rx.indigo,
                      icon: CupertinoIcons.timer,
                    ),
                ],
              ),
            ),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, RxSpace.m, 4),
            child: Row(
              children: [
                _LikeButton(
                  liked: post.likedByMe,
                  count: post.likeCount,
                  onPressed: () => _like(context, ref),
                ),
                Semantics(
                  button: true,
                  label: '${post.commentCount} comments',
                  excludeSemantics: true,
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minSize: RxSpace.minTouch,
                    onPressed: openDetail,
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.chat_bubble,
                            size: 22, color: rx.label),
                        const SizedBox(width: 6),
                        Text('${post.commentCount}',
                            style: rx.subheadline.copyWith(color: rx.label)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LikeButton extends StatefulWidget {
  const _LikeButton({
    required this.liked,
    required this.count,
    required this.onPressed,
  });

  final bool liked;
  final int count;
  final VoidCallback onPressed;

  @override
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.3), weight: 50),
    TweenSequenceItem(tween: Tween(begin: 1.3, end: 1), weight: 50),
  ]).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));

  @override
  void didUpdateWidget(covariant _LikeButton old) {
    super.didUpdateWidget(old);
    if (widget.liked && !old.liked) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Semantics(
      button: true,
      toggled: widget.liked,
      label: widget.liked
          ? 'Unlike, ${widget.count} likes'
          : 'Like, ${widget.count} likes',
      excludeSemantics: true,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minSize: RxSpace.minTouch,
        onPressed: widget.onPressed,
        child: Row(
          children: [
            ScaleTransition(
              scale: _scale,
              child: Icon(
                widget.liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                size: 24,
                color: widget.liked ? rx.destructive : rx.label,
              ),
            ),
            const SizedBox(width: 6),
            Text('${widget.count}',
                style: rx.subheadline.copyWith(color: rx.label)),
          ],
        ),
      ),
    );
  }
}

class _PostImages extends StatefulWidget {
  const _PostImages({
    required this.images,
    required this.fullSize,
    required this.onDoubleTap,
    this.onTap,
  });

  final List<PostImageDto> images;
  final bool fullSize;
  final VoidCallback onDoubleTap;
  final VoidCallback? onTap;

  @override
  State<_PostImages> createState() => _PostImagesState();
}

class _PostImagesState extends State<_PostImages> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final images = widget.images;
    String pathOf(PostImageDto i) => widget.fullSize ? i.filePath : i.thumbPath;

    Widget image(PostImageDto i) => GestureDetector(
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          child: RxMediaImage(path: pathOf(i)),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RxSpace.s),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RxSpace.radius),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: images.length == 1
              ? image(images.first)
              : Stack(
                  children: [
                    PageView.builder(
                      itemCount: images.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (_, i) => image(images[i]),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < images.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: i == _page ? 8 : 6,
                              height: i == _page ? 8 : 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFFFFFFF)
                                    .withOpacity(i == _page ? 1 : 0.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: RxPill(
                        label: '${_page + 1}/${images.length}',
                        color: rx.isDark
                            ? const Color(0xFF000000)
                            : const Color(0xFF3A3A3C),
                        filled: true,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
