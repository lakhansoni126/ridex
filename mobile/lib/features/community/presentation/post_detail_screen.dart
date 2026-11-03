import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../data/api/posts_repository.dart';
import '../../../shared/ui/ui.dart';
import '../../auth/application/auth_notifier.dart';
import 'community_feed_screen.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId, this.initialPost});

  final String postId;
  final PostDto? initialPost;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  static const _maxComment = 1000;

  final _comment = TextEditingController();
  final _scroll = ScrollController();
  PostDto? _post;
  Object? _postError;
  List<CommentDto>? _comments;
  Object? _commentsError;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _post = widget.initialPost;
    _comment.addListener(() => setState(() {}));
    if (_post == null) _loadPost();
    _loadComments();
  }

  @override
  void dispose() {
    _comment.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadPost() async {
    try {
      final p = await ref.read(postsRepositoryProvider).getPost(widget.postId);
      if (!mounted) return;
      setState(() {
        _post = p;
        _postError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _postError = e);
    }
  }

  Future<void> _loadComments() async {
    try {
      final list =
          await ref.read(postsRepositoryProvider).listComments(widget.postId);
      if (!mounted) return;
      setState(() {
        _comments = list;
        _commentsError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _commentsError = e);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadPost(), _loadComments()]);
  }

  /// Like toggle that works whether or not the post is in the cached feed.
  Future<void> _toggleLike() async {
    final before = _post;
    if (before == null) return;
    final liked = !before.likedByMe;
    setState(() => _post = before.copyWith(
          likedByMe: liked,
          likeCount: (before.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 30),
        ));
    try {
      final r = await ref.read(postsRepositoryProvider).toggleLike(before.id);
      if (!mounted) return;
      final updated =
          _post!.copyWith(likedByMe: r.liked, likeCount: r.likeCount);
      setState(() => _post = updated);
      ref.read(communityFeedProvider.notifier).replace(updated);
    } catch (e) {
      if (mounted) setState(() => _post = before);
      rethrow;
    }
  }

  Future<void> _send() async {
    final body = _comment.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final c = await ref
          .read(postsRepositoryProvider)
          .addComment(widget.postId, body);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      _comment.clear();
      setState(() {
        _comments = [...?_comments, c];
        if (_post != null) {
          _post = _post!.copyWith(commentCount: _post!.commentCount + 1);
        }
      });
      ref.read(communityFeedProvider.notifier).bumpComments(widget.postId, 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) showRxError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _commentMenu(CommentDto c) async {
    final me = ref.read(authNotifierProvider).user;
    final canDelete =
        me != null && (c.userId == me.id || _post?.authorId == me.id);
    if (!canDelete) return;
    HapticFeedback.selectionClick();
    final choice = await showRxActionSheet<String>(
      context,
      actions: const [
        RxSheetAction(
            label: 'Delete Comment', value: 'delete', destructive: true),
      ],
    );
    if (choice != 'delete' || !mounted) return;
    final previous = _comments;
    setState(() {
      _comments = _comments?.where((x) => x.id != c.id).toList();
      if (_post != null) {
        _post = _post!.copyWith(
            commentCount: (_post!.commentCount - 1).clamp(0, 1 << 30));
      }
    });
    try {
      await ref
          .read(postsRepositoryProvider)
          .deleteComment(widget.postId, c.id);
      ref.read(communityFeedProvider.notifier).bumpComments(widget.postId, -1);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _comments = previous;
        if (_post != null) {
          _post = _post!.copyWith(commentCount: _post!.commentCount + 1);
        }
      });
      showRxError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final post = _post;

    Widget content;
    if (post == null) {
      content = _postError != null
          ? Center(child: RxErrorState(error: _postError!, onRetry: _loadPost))
          : const Center(child: CupertinoActivityIndicator());
    } else {
      content = CustomScrollView(
        controller: _scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          CupertinoSliverRefreshControl(onRefresh: _refresh),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                RxSpace.m, RxSpace.m, RxSpace.m, RxSpace.m),
            sliver: SliverToBoxAdapter(
              child: PostCell(
                post: post,
                fullSize: true,
                onToggleLike: _toggleLike,
                onDeleted: () {
                  if (mounted) context.pop();
                },
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                RxSpace.inset, RxSpace.s, RxSpace.inset, RxSpace.s),
            sliver: SliverToBoxAdapter(
              child: Text(
                'COMMENTS',
                style: rx.footnote,
              ),
            ),
          ),
          ..._commentSlivers(),
          const SliverToBoxAdapter(child: SizedBox(height: RxSpace.l)),
        ],
      );
    }

    return RxPage(
      title: 'Post',
      previousPageTitle: 'Feed',
      child: Column(
        children: [
          Expanded(child: content),
          if (post != null) _composer(),
        ],
      ),
    );
  }

  List<Widget> _commentSlivers() {
    final rx = context.rx;
    if (_comments == null) {
      if (_commentsError != null) {
        return [
          SliverToBoxAdapter(
            child: RxErrorState(error: _commentsError!, onRetry: _loadComments),
          ),
        ];
      }
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(RxSpace.l),
            child: CupertinoActivityIndicator(),
          ),
        ),
      ];
    }
    if (_comments!.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(RxSpace.l),
            child: Text(
              'No comments yet. Start the conversation.',
              style: rx.subheadline,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: RxSpace.m),
        sliver: SliverToBoxAdapter(
          child: RxCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _comments!.length; i++) ...[
                  if (i > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 60),
                      height: 0.5,
                      color: rx.separator,
                    ),
                  _CommentRow(
                    comment: _comments![i],
                    onLongPress: () => _commentMenu(_comments![i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _composer() {
    final rx = context.rx;
    final canSend = _comment.text.trim().isNotEmpty && !_sending;
    return Container(
      decoration: BoxDecoration(
        color: rx.bar,
        border: Border(top: BorderSide(color: rx.separator, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(
        RxSpace.m,
        RxSpace.s,
        RxSpace.s,
        RxSpace.s + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: CupertinoTextField(
              controller: _comment,
              placeholder: 'Add a comment…',
              placeholderStyle: rx.body.copyWith(color: rx.tertiaryLabel),
              style: rx.body,
              cursorColor: rx.accent,
              minLines: 1,
              maxLines: 5,
              maxLength: _maxComment,
              textCapitalization: TextCapitalization.sentences,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: rx.fill,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Send comment',
            child: CupertinoButton(
              padding: const EdgeInsets.only(left: 6),
              minSize: RxSpace.minTouch,
              onPressed: canSend ? _send : null,
              child: _sending
                  ? const CupertinoActivityIndicator()
                  : Icon(
                      CupertinoIcons.arrow_up_circle_fill,
                      size: 32,
                      color: canSend ? rx.accent : rx.tertiaryLabel,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment, required this.onLongPress});

  final CommentDto comment;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final name = comment.user?.displayName ?? 'Driver';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RxAvatar(
                name: name, avatarPath: comment.user?.avatarPath, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name,
                            style: rx.subheadline.copyWith(
                                color: rx.label, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Text(relativeTime(comment.createdAt), style: rx.caption),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(comment.body, style: rx.body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
