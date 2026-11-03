import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../data/api/friends_repository.dart';
import '../../../data/api/shares_repository.dart';
import '../../../data/ws/ws_client.dart';
import '../../../shared/ui/ui.dart';
import '../../friends/presentation/friends_screen.dart';

final locationSharesProvider =
    FutureProvider.autoDispose<LocationSharesListDto>((ref) {
  return ref.watch(sharesRepositoryProvider).listShares();
});

class LocationSharingScreen extends ConsumerStatefulWidget {
  const LocationSharingScreen({super.key});

  @override
  ConsumerState<LocationSharingScreen> createState() =>
      _LocationSharingScreenState();
}

class _LocationSharingScreenState extends ConsumerState<LocationSharingScreen> {
  String _duration = '1h';
  final Set<String> _selected = {};
  bool _busy = false;

  Future<void> _refresh() async {
    ref.invalidate(locationSharesProvider);
    ref.invalidate(friendsListProvider);
    try {
      await ref.read(locationSharesProvider.future);
    } catch (_) {}
  }

  Future<void> _start() async {
    if (_selected.isEmpty) {
      showRxToast(context, 'Choose at least one friend', isError: true);
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(sharesRepositoryProvider);
    final bg = ref.read(backgroundLocationServiceProvider);
    try {
      final share = await repo.createShare(
        duration: _duration,
        friendIds: _selected.toList(),
      );
      final ws = LocationShareWsSession(
        tokenProvider: ref.read(tokenStoreProvider).readAccessToken,
      );
      await ws.connect(onMessage: (_) {});
      final ok = await bg.startForShare(shareId: share.id, ws: ws);
      if (!ok) {
        await ws.disconnect();
        try {
          await repo.stopShare(share.id);
        } catch (_) {}
        if (mounted) {
          showRxToast(
            context,
            'Location permission is required to share. Allow it in Settings.',
            isError: true,
          );
        }
        ref.invalidate(locationSharesProvider);
        return;
      }
      HapticFeedback.mediumImpact();
      if (mounted) {
        setState(_selected.clear);
        showRxToast(context, 'Sharing your location',
            icon: CupertinoIcons.location_fill);
      }
      ref.invalidate(locationSharesProvider);
    } catch (e) {
      if (mounted) showRxError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop(LocationShareDto share) async {
    final ok = await confirmRx(
      context,
      title: 'Stop sharing?',
      message: 'Friends will no longer see your live location.',
      confirmLabel: 'Stop Sharing',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(sharesRepositoryProvider).stopShare(share.id);
      await ref.read(backgroundLocationServiceProvider).stopShare();
      if (mounted) showRxToast(context, 'Location sharing stopped');
      ref.invalidate(locationSharesProvider);
    } catch (e) {
      if (mounted) showRxError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(LocationShareDto share, LocationShareGrantDto g) async {
    final name = g.friend?.displayName ?? 'this friend';
    final choice = await showRxActionSheet<String>(
      context,
      title: name,
      actions: [
        RxSheetAction(
          label: 'Stop Sharing with $name',
          value: 'revoke',
          destructive: true,
        ),
      ],
    );
    if (choice != 'revoke' || !mounted) return;
    try {
      await ref
          .read(sharesRepositoryProvider)
          .revokeGrant(share.id, g.friendUserId);
      if (mounted) showRxToast(context, 'Stopped sharing with $name');
      ref.invalidate(locationSharesProvider);
    } catch (e) {
      if (mounted) showRxError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sharesAsync = ref.watch(locationSharesProvider);

    return RxPage(
      title: 'Location Sharing',
      previousPageTitle: 'Friends',
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          CupertinoSliverRefreshControl(onRefresh: _refresh),
          ...sharesAsync.when(
            loading: () => [const RxSliverLoading()],
            error: (e, _) => [
              RxSliverCenter(child: RxErrorState(error: e, onRetry: _refresh)),
            ],
            data: (list) {
              final active = list.activeMine;
              return [
                const SliverToBoxAdapter(child: SizedBox(height: RxSpace.m)),
                if (active != null)
                  ..._activeSlivers(active)
                else
                  ..._setupSlivers(),
                if (list.sharedWithMe.isNotEmpty)
                  SliverToBoxAdapter(child: _sharedWithMe(list.sharedWithMe)),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.paddingOf(context).bottom + RxSpace.l,
                  ),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }

  // ── Active share ──────────────────────────────────────────────────────────
  List<Widget> _activeSlivers(LocationShareDto share) {
    final rx = context.rx;
    final grants = share.grants.where((g) => g.isActive).toList();
    final names = grants.map((g) => g.friend?.displayName ?? 'Friend').toList();
    final expiry = share.expiresAt == null
        ? 'Until you stop'
        : 'Until ${DateFormat.jm().format(share.expiresAt!.toLocal())}';
    return [
      RxSliverPadding(
        bottom: RxSpace.l,
        child: RxCard(
          padding: const EdgeInsets.all(RxSpace.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _PulsingDot(color: rx.success),
                  const SizedBox(width: RxSpace.s),
                  Text('Sharing live',
                      style: rx.headline.copyWith(color: rx.success)),
                  const Spacer(),
                  RxPill(label: expiry, color: rx.info),
                ],
              ),
              const SizedBox(height: RxSpace.s),
              Text(
                names.isEmpty
                    ? 'No friends can see you right now.'
                    : 'Visible to ${_joinNames(names)}',
                style: rx.body,
              ),
              const SizedBox(height: RxSpace.xs),
              Text(
                'Last update ${relativeTime(share.lastSeenAt)}',
                style: rx.footnote,
              ),
            ],
          ),
        ),
      ),
      if (grants.isNotEmpty)
        SliverToBoxAdapter(
          child: RxSection(
            header: 'Shared with',
            footer: 'Tap a friend to stop sharing with just them.',
            children: [
              for (final g in grants)
                RxTile(
                  leading: RxAvatar(
                    name: g.friend?.displayName ?? 'Friend',
                    avatarPath: g.friend?.avatarPath,
                  ),
                  title: g.friend?.displayName ?? 'Friend',
                  subtitle: g.friend == null ? null : '@${g.friend!.username}',
                  trailing: Icon(CupertinoIcons.ellipsis,
                      color: rx.secondaryLabel, size: 20),
                  onTap: () => _revoke(share, g),
                ),
            ],
          ),
        ),
      RxSliverPadding(
        top: RxSpace.m,
        bottom: RxSpace.s,
        child: RxButton(
          label: 'Stop Sharing',
          kind: RxButtonKind.destructive,
          icon: CupertinoIcons.location_slash_fill,
          busy: _busy,
          onPressed: () => _stop(share),
        ),
      ),
      RxSliverPadding(
        bottom: RxSpace.l,
        child: Text(
          'Android shows a persistent notification while RideX is sharing your location.',
          style: rx.footnote,
          textAlign: TextAlign.center,
        ),
      ),
    ];
  }

  // ── Setup ─────────────────────────────────────────────────────────────────
  List<Widget> _setupSlivers() {
    final rx = context.rx;
    final friendsAsync = ref.watch(friendsListProvider);
    return [
      RxSliverPadding(
        bottom: RxSpace.s,
        child: Text('DURATION', style: rx.footnote),
      ),
      RxSliverPadding(
        bottom: RxSpace.l,
        child: SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<String>(
            groupValue: _duration,
            thumbColor: rx.cardElevated,
            backgroundColor: rx.fill,
            children: {
              '1h': _segment('1 Hour'),
              '8h': _segment('8 Hours'),
              'indefinite': _segment('Until I Stop'),
            },
            onValueChanged: (v) {
              if (v == null) return;
              HapticFeedback.selectionClick();
              setState(() => _duration = v);
            },
          ),
        ),
      ),
      ...friendsAsync.when(
        loading: () => [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(RxSpace.l),
              child: CupertinoActivityIndicator(),
            ),
          ),
        ],
        error: (e, _) => [
          SliverToBoxAdapter(
            child: RxErrorState(
              error: e,
              onRetry: () => ref.invalidate(friendsListProvider),
            ),
          ),
        ],
        data: (friends) {
          if (friends.isEmpty) {
            return [
              SliverToBoxAdapter(
                child: RxEmptyState(
                  icon: CupertinoIcons.person_2,
                  title: 'No friends yet',
                  message:
                      'Add friends first, then share your live location with them.',
                  actionLabel: 'Add Friends',
                  onAction: () => context.push('/friends/add'),
                ),
              ),
            ];
          }
          final allSelected = _selected.length == friends.length;
          return [
            SliverToBoxAdapter(
              child: RxSection(
                header: 'Share with',
                footer:
                    'Only the friends you pick can see your location, and only until the share ends. You can stop at any time.',
                children: [
                  RxTile(
                    title: allSelected ? 'Deselect All' : 'Select All',
                    chevron: false,
                    trailing: const SizedBox.shrink(),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        if (allSelected) {
                          _selected.clear();
                        } else {
                          _selected.addAll(friends.map((f) => f.id));
                        }
                      });
                    },
                  ),
                  for (final f in friends) _friendRow(f),
                ],
              ),
            ),
            RxSliverPadding(
              top: RxSpace.m,
              bottom: RxSpace.s,
              child: RxButton(
                label: _selected.isEmpty
                    ? 'Start Sharing'
                    : 'Start Sharing with ${_selected.length}',
                icon: CupertinoIcons.location_fill,
                busy: _busy,
                onPressed: _selected.isEmpty ? null : _start,
              ),
            ),
            RxSliverPadding(
              bottom: RxSpace.l,
              child: Text(
                'Android shows a persistent notification while RideX is sharing your location.',
                style: rx.footnote,
                textAlign: TextAlign.center,
              ),
            ),
          ];
        },
      ),
    ];
  }

  Widget _segment(String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(label,
            style: context.rx.subheadline.copyWith(
              color: context.rx.label,
              fontWeight: FontWeight.w500,
            )),
      );

  Widget _friendRow(PublicUserDto f) {
    final rx = context.rx;
    final selected = _selected.contains(f.id);
    return Semantics(
      selected: selected,
      child: RxTile(
        leading: RxAvatar(name: f.displayName, avatarPath: f.avatarPath),
        title: f.displayName,
        subtitle: '@${f.username}',
        chevron: false,
        trailing: Icon(
          selected
              ? CupertinoIcons.checkmark_circle_fill
              : CupertinoIcons.circle,
          color: selected ? rx.accent : rx.tertiaryLabel,
          size: 24,
        ),
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            if (selected) {
              _selected.remove(f.id);
            } else {
              _selected.add(f.id);
            }
          });
        },
      ),
    );
  }

  // ── Shared with me ────────────────────────────────────────────────────────
  Widget _sharedWithMe(List<LocationShareDto> shares) {
    return Padding(
      padding: const EdgeInsets.only(top: RxSpace.s),
      child: RxSection(
        header: 'Shared with you',
        children: [
          for (final s in shares)
            RxTile(
              leading: RxAvatar(
                name: s.owner?.displayName ?? 'Friend',
                avatarPath: s.owner?.avatarPath,
              ),
              title: s.owner?.displayName ?? 'Friend',
              subtitle: s.hasLocation
                  ? 'Updated ${relativeTime(s.lastSeenAt)}'
                  : 'Waiting for location…',
              onTap: () => context.push('/friends/map'),
            ),
        ],
      ),
    );
  }

  static String _joinNames(List<String> names) {
    if (names.length <= 2) return names.join(' and ');
    return '${names.take(2).join(', ')} and ${names.length - 2} more';
  }
}

/// Green "live" dot that gently pulses.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});

  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return SizedBox(
      width: 16,
      height: 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!reduceMotion)
            AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Container(
                width: 8 + 8 * _c.value,
                height: 8 + 8 * _c.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withOpacity(0.4 * (1 - _c.value)),
                ),
              ),
            ),
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: widget.color),
          ),
        ],
      ),
    );
  }
}
