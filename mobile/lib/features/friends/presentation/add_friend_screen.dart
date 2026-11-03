import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/api/friends_repository.dart';
import '../../../shared/ui/ui.dart';
import 'friends_screen.dart';

class AddFriendScreen extends ConsumerStatefulWidget {
  const AddFriendScreen({super.key});

  @override
  ConsumerState<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends ConsumerState<AddFriendScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<UserSearchResultDto>? _results;
  Object? _error;
  bool _loading = false;
  int _searchSeq = 0;

  /// Local overrides after an action (user id → new state).
  final Map<String, FriendshipState> _overrides = {};
  final Set<String> _busy = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() {
        _results = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    final seq = ++_searchSeq;
    try {
      final results = await ref.read(friendsRepositoryProvider).searchUsers(q);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = results;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _add(PublicUserDto user) async {
    HapticFeedback.lightImpact();
    setState(() => _busy.add(user.id));
    try {
      final f =
          await ref.read(friendsRepositoryProvider).sendRequest(user.username);
      if (!mounted) return;
      final accepted = f.status == 'accepted';
      setState(() => _overrides[user.id] =
          accepted ? FriendshipState.friends : FriendshipState.outgoing);
      showRxToast(
        context,
        accepted
            ? "You're now friends with ${user.displayName}"
            : 'Request sent to ${user.displayName}',
      );
      ref.invalidate(friendRequestsProvider);
      if (accepted) ref.invalidate(friendsListProvider);
    } catch (e) {
      if (mounted) showRxError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(user.id));
    }
  }

  Future<void> _acceptIncoming(PublicUserDto user) async {
    HapticFeedback.mediumImpact();
    setState(() => _busy.add(user.id));
    try {
      final requests = await ref.read(friendsRepositoryProvider).listRequests();
      final match = requests.incoming
          .where((f) => f.requesterId == user.id || f.user?.id == user.id);
      if (match.isEmpty) {
        // Fall back to sending a request, which the server auto-accepts.
        await ref.read(friendsRepositoryProvider).sendRequest(user.username);
      } else {
        await ref.read(friendsRepositoryProvider).acceptRequest(match.first.id);
      }
      if (!mounted) return;
      setState(() => _overrides[user.id] = FriendshipState.friends);
      showRxToast(context, "You're now friends with ${user.displayName}");
      ref.invalidate(friendRequestsProvider);
      ref.invalidate(friendsListProvider);
    } catch (e) {
      if (mounted) showRxError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(user.id));
    }
  }

  Widget _trailing(UserSearchResultDto r) {
    final rx = context.rx;
    final state = _overrides[r.user.id] ?? r.friendship;
    if (_busy.contains(r.user.id)) {
      return const CupertinoActivityIndicator();
    }
    switch (state) {
      case FriendshipState.friends:
        return Semantics(
          label: 'Already friends',
          child: Icon(CupertinoIcons.checkmark_alt_circle_fill,
              color: rx.success, size: 24),
        );
      case FriendshipState.outgoing:
        return Text('Requested', style: rx.subheadline);
      case FriendshipState.incoming:
        return _Capsule(
          label: 'Accept',
          filled: true,
          onPressed: () => _acceptIncoming(r.user),
        );
      case FriendshipState.none:
        return _Capsule(label: 'Add', onPressed: () => _add(r.user));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final q = _query.text.trim();

    Widget body;
    if (q.length < 2) {
      body = const RxEmptyState(
        icon: CupertinoIcons.search,
        title: 'Find drivers',
        message: 'Search by name or @username to send a friend request.',
      );
    } else if (_loading && _results == null) {
      body = const Padding(
        padding: EdgeInsets.all(RxSpace.xl),
        child: CupertinoActivityIndicator(),
      );
    } else if (_error != null) {
      body = RxErrorState(error: _error!, onRetry: () => _search(q));
    } else if (_results == null || _results!.isEmpty) {
      body = RxEmptyState(
        icon: CupertinoIcons.person_crop_circle_badge_xmark,
        title: 'No results',
        message: 'No drivers match "$q".',
      );
    } else {
      body = RxSection(
        children: [
          for (final r in _results!)
            RxTile(
              leading: RxAvatar(
                  name: r.user.displayName, avatarPath: r.user.avatarPath),
              title: r.user.displayName,
              subtitle: '@${r.user.username}',
              trailing: _trailing(r),
              chevron: false,
            ),
        ],
      );
    }

    return RxPage(
      title: 'Add Friends',
      previousPageTitle: 'Friends',
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(top: RxSpace.m, bottom: RxSpace.xl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  RxSpace.inset, 0, RxSpace.inset, RxSpace.m),
              child: CupertinoSearchTextField(
                controller: _query,
                autofocus: true,
                placeholder: 'Name or username',
                style: rx.body,
                backgroundColor: rx.fill,
                onChanged: _onChanged,
                onSubmitted: (v) {
                  _debounce?.cancel();
                  if (v.trim().length >= 2) _search(v.trim());
                },
              ),
            ),
            if (_loading && _results != null)
              const Padding(
                padding: EdgeInsets.only(bottom: RxSpace.s),
                child: CupertinoActivityIndicator(),
              ),
            body,
          ],
        ),
      ),
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule({
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
        padding: const EdgeInsets.symmetric(horizontal: 16),
        minSize: 32,
        color: filled ? rx.accent : rx.accentTint,
        borderRadius: BorderRadius.circular(100),
        onPressed: onPressed,
        child: Text(
          label,
          style: rx.subheadline.copyWith(
            color: filled ? rx.onAccent : rx.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
