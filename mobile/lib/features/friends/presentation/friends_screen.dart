import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../data/api/friends_repository.dart';
import '../../../shared/ui/ui.dart';
import '../../sharing/presentation/location_sharing_screen.dart';

final friendsListProvider =
    FutureProvider.autoDispose<List<PublicUserDto>>((ref) {
  return ref.watch(friendsRepositoryProvider).listFriends();
});

final friendRequestsProvider =
    FutureProvider.autoDispose<FriendRequestsDto>((ref) {
  return ref.watch(friendsRepositoryProvider).listRequests();
});

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  /// Request ids handled optimistically (hidden until the list reloads).
  final Set<String> _hiddenRequests = {};

  /// Friend ids removed optimistically.
  final Set<String> _hiddenFriends = {};

  Future<void> _refresh() async {
    ref.invalidate(friendsListProvider);
    ref.invalidate(friendRequestsProvider);
    ref.invalidate(locationSharesProvider);
    try {
      await Future.wait([
        ref.read(friendsListProvider.future),
        ref.read(friendRequestsProvider.future),
      ]);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _hiddenRequests.clear();
        _hiddenFriends.clear();
      });
    }
  }

  Future<void> _accept(FriendshipDto f) async {
    HapticFeedback.mediumImpact();
    setState(() => _hiddenRequests.add(f.id));
    try {
      await ref.read(friendsRepositoryProvider).acceptRequest(f.id);
      if (!mounted) return;
      showRxToast(context,
          "You're now friends with ${f.user?.displayName ?? 'this driver'}");
      ref.invalidate(friendsListProvider);
      ref.invalidate(friendRequestsProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _hiddenRequests.remove(f.id));
      showRxError(context, e);
    }
  }

  Future<void> _decline(FriendshipDto f) async {
    HapticFeedback.selectionClick();
    setState(() => _hiddenRequests.add(f.id));
    try {
      await ref.read(friendsRepositoryProvider).declineRequest(f.id);
      ref.invalidate(friendRequestsProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _hiddenRequests.remove(f.id));
      showRxError(context, e);
    }
  }

  Future<void> _cancel(FriendshipDto f) async {
    HapticFeedback.selectionClick();
    setState(() => _hiddenRequests.add(f.id));
    try {
      await ref.read(friendsRepositoryProvider).cancelRequest(f.id);
      ref.invalidate(friendRequestsProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _hiddenRequests.remove(f.id));
      showRxError(context, e);
    }
  }

  Future<void> _friendMenu(PublicUserDto friend) async {
    HapticFeedback.selectionClick();
    final choice = await showRxActionSheet<String>(
      context,
      title: friend.displayName,
      message: '@${friend.username}',
      actions: const [
        RxSheetAction(
            label: 'Remove Friend', value: 'remove', destructive: true),
      ],
    );
    if (choice != 'remove' || !mounted) return;
    final ok = await confirmRx(
      context,
      title: 'Remove ${friend.displayName}?',
      message:
          'They will no longer see your shared location or appear in your friends list.',
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) return;
    setState(() => _hiddenFriends.add(friend.id));
    try {
      await ref.read(friendsRepositoryProvider).unfriend(friend.id);
      ref.invalidate(friendsListProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _hiddenFriends.remove(friend.id));
      showRxError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final friendsAsync = ref.watch(friendsListProvider);
    final requestsAsync = ref.watch(friendRequestsProvider);
    final sharesAsync = ref.watch(locationSharesProvider);

    final shares = sharesAsync.valueOrNull;
    final active = shares?.activeMine;
    final sharingDetail = active == null
        ? 'Off'
        : 'With ${active.grants.where((g) => g.isActive).length}';
    final sharingWithMe = shares?.sharedWithMe.length ?? 0;

    final slivers = <Widget>[];

    // ── Location ─────────────────────────────────────────────────────────
    slivers.add(SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: RxSpace.s),
        child: RxSection(
          children: [
            RxTile(
              title: 'Location Sharing',
              icon: CupertinoIcons.location_fill,
              iconColor: rx.success,
              detail: sharingDetail,
              onTap: () => context.push('/friends/sharing'),
            ),
            RxTile(
              title: "Friends' Map",
              icon: CupertinoIcons.map_fill,
              iconColor: rx.info,
              detail: sharingWithMe == 0 ? null : '$sharingWithMe live',
              onTap: () => context.push('/friends/map'),
            ),
          ],
        ),
      ),
    ));

    // ── Requests ─────────────────────────────────────────────────────────
    final requests = requestsAsync.valueOrNull;
    if (requests != null) {
      final incoming =
          requests.incoming.where((f) => !_hiddenRequests.contains(f.id));
      final outgoing =
          requests.outgoing.where((f) => !_hiddenRequests.contains(f.id));
      final rows = <Widget>[
        for (final f in incoming)
          _RequestRow(
            friendship: f,
            subtitle: 'Wants to be friends',
            actions: [
              _SmallButton(
                label: 'Accept',
                filled: true,
                onPressed: () => _accept(f),
              ),
              const SizedBox(width: RxSpace.s),
              _SmallButton(label: 'Decline', onPressed: () => _decline(f)),
            ],
          ),
        for (final f in outgoing)
          _RequestRow(
            friendship: f,
            subtitle: 'Request sent',
            actions: [
              _SmallButton(label: 'Cancel', onPressed: () => _cancel(f)),
            ],
          ),
      ];
      if (rows.isNotEmpty) {
        slivers.add(SliverToBoxAdapter(
          child: RxSection(header: 'Requests', children: rows),
        ));
      }
    }

    // ── Friends ──────────────────────────────────────────────────────────
    slivers.add(friendsAsync.when(
      loading: () => const RxSliverLoading(),
      error: (e, _) => RxSliverCenter(
        child: RxErrorState(error: e, onRetry: _refresh),
      ),
      data: (all) {
        final friends =
            all.where((f) => !_hiddenFriends.contains(f.id)).toList();
        if (friends.isEmpty) {
          return RxSliverCenter(
            child: RxEmptyState(
              icon: CupertinoIcons.person_2,
              title: 'No friends yet',
              message:
                  'Add drivers you know to share your location and drive together.',
              actionLabel: 'Add Friends',
              onAction: () => context.push('/friends/add'),
            ),
          );
        }
        return SliverToBoxAdapter(
          child: RxSection(
            header: 'Friends (${friends.length})',
            children: [
              for (final f in friends)
                GestureDetector(
                  onLongPress: () => _friendMenu(f),
                  child: RxTile(
                    leading:
                        RxAvatar(name: f.displayName, avatarPath: f.avatarPath),
                    title: f.displayName,
                    subtitle: '@${f.username}',
                    trailing: Semantics(
                      button: true,
                      label: 'More options for ${f.displayName}',
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minSize: RxSpace.minTouch,
                        onPressed: () => _friendMenu(f),
                        child: Icon(CupertinoIcons.ellipsis,
                            color: rx.secondaryLabel, size: 20),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ));

    return RxLargeTitlePage(
      title: 'Friends',
      trailing: RxNavIconButton(
        icon: CupertinoIcons.person_badge_plus,
        semanticLabel: 'Add friends',
        onPressed: () => context.push('/friends/add'),
      ),
      onRefresh: _refresh,
      slivers: slivers,
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.friendship,
    required this.subtitle,
    required this.actions,
  });

  final FriendshipDto friendship;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final user = friendship.user;
    final name = user?.displayName ?? 'Driver';
    return RxTile(
      leading: RxAvatar(name: name, avatarPath: user?.avatarPath),
      title: name,
      subtitle: user == null ? subtitle : '@${user.username} · $subtitle',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: actions),
      chevron: false,
    );
  }
}

/// Compact capsule button used inside list rows.
class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minSize: 32,
        color: filled ? rx.accent : rx.fill,
        borderRadius: BorderRadius.circular(100),
        onPressed: onPressed,
        child: Text(
          label,
          style: rx.subheadline.copyWith(
            color: filled ? rx.onAccent : rx.label,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
