import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../data/api/rides_repository.dart';
import '../../../shared/ui/ui.dart';

final discoverRidesProvider =
    FutureProvider.autoDispose<List<RideDto>>((ref) {
  return ref.watch(ridesRepositoryProvider).listRides(scope: 'discover');
});

final myRidesProvider = FutureProvider.autoDispose<List<RideDto>>((ref) {
  return ref.watch(ridesRepositoryProvider).listRides(scope: 'mine');
});

/// Opens the "+" action sheet shared by the tab and empty states.
Future<void> showNewDriveSheet(BuildContext context) async {
  final choice = await showRxActionSheet<String>(
    context,
    actions: const [
      RxSheetAction(label: 'Create a Drive', value: 'create', isDefault: true),
      RxSheetAction(label: 'Join with Code', value: 'join'),
    ],
  );
  if (!context.mounted || choice == null) return;
  context.push(choice == 'create' ? '/rides/create' : '/rides/join');
}

/// "Today 6:30 PM", "Tomorrow 9:00 AM", "Sat, 12 Oct · 7:15 AM".
String formatRideTime(DateTime t) {
  final local = t.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final time = DateFormat.jm().format(local);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today $time';
  if (diff == 1) return 'Tomorrow $time';
  if (diff == -1) return 'Yesterday $time';
  return '${DateFormat('EEE, d MMM').format(local)} · $time';
}

class RidesScreen extends ConsumerStatefulWidget {
  const RidesScreen({super.key});

  @override
  ConsumerState<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends ConsumerState<RidesScreen> {
  int _segment = 0;

  Future<void> _refresh() async {
    if (_segment == 0) {
      ref.invalidate(discoverRidesProvider);
      await ref.read(discoverRidesProvider.future).catchError((_) => <RideDto>[]);
    } else {
      ref.invalidate(myRidesProvider);
      await ref.read(myRidesProvider.future).catchError((_) => <RideDto>[]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final async =
        ref.watch(_segment == 0 ? discoverRidesProvider : myRidesProvider);

    return RxLargeTitlePage(
      title: 'Drives',
      trailing: RxNavIconButton(
        icon: CupertinoIcons.plus,
        semanticLabel: 'New drive',
        onPressed: () => showNewDriveSheet(context),
      ),
      onRefresh: _refresh,
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _SegmentHeader(
            background: rx.background,
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: _segment,
              children: const {
                0: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Discover'),
                ),
                1: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('My Drives'),
                ),
              },
              onValueChanged: (v) => setState(() => _segment = v ?? 0),
            ),
          ),
        ),
        ...async.when(
          loading: () => const [RxSliverLoading()],
          error: (e, _) => [
            RxSliverCenter(
              child: RxErrorState(
                error: e,
                onRetry: () => ref.invalidate(
                    _segment == 0 ? discoverRidesProvider : myRidesProvider),
              ),
            ),
          ],
          data: (rides) => _segment == 0
              ? _discoverSlivers(rides)
              : _mineSlivers(rides),
        ),
      ],
    );
  }

  List<Widget> _discoverSlivers(List<RideDto> rides) {
    if (rides.isEmpty) {
      return [
        RxSliverCenter(
          child: RxEmptyState(
            icon: CupertinoIcons.car_detailed,
            title: 'No public drives yet',
            message:
                'Start one and invite your crew, or join a private drive with a code.',
            actionLabel: 'Create a Drive',
            onAction: () => context.push('/rides/create'),
          ),
        ),
      ];
    }
    return [_rideList(rides, top: RxSpace.s)];
  }

  List<Widget> _mineSlivers(List<RideDto> rides) {
    if (rides.isEmpty) {
      return [
        RxSliverCenter(
          child: RxEmptyState(
            icon: CupertinoIcons.flag,
            title: 'No drives yet',
            message: 'Drives you host or join will show up here.',
            actionLabel: 'New Drive',
            onAction: () => showNewDriveSheet(context),
          ),
        ),
      ];
    }
    final upcoming = rides.where((r) => !r.isOver).toList()
      ..sort((a, b) {
        if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
        final at = a.scheduledAt ?? a.createdAt ?? DateTime(2000);
        final bt = b.scheduledAt ?? b.createdAt ?? DateTime(2000);
        return at.compareTo(bt);
      });
    final past = rides.where((r) => r.isOver).toList();
    return [
      if (upcoming.isNotEmpty) ...[
        const _SectionHeader('Live & Upcoming'),
        _rideList(upcoming),
      ],
      if (past.isNotEmpty) ...[
        const _SectionHeader('Past'),
        _rideList(past),
      ],
    ];
  }

  Widget _rideList(List<RideDto> rides, {double top = 0}) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(RxSpace.inset, top, RxSpace.inset, 0),
      sliver: SliverList.separated(
        itemCount: rides.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => RideCard(ride: rides[i]),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
          RxSpace.inset + 16, RxSpace.m, RxSpace.inset, RxSpace.s),
      sliver: SliverToBoxAdapter(
        child: Text(text.toUpperCase(), style: rx.footnote),
      ),
    );
  }
}

class _SegmentHeader extends SliverPersistentHeaderDelegate {
  _SegmentHeader({required this.child, required this.background});

  final Widget child;
  final Color background;

  static const double _height = 52;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      color: background,
      padding: const EdgeInsets.fromLTRB(RxSpace.inset, 8, RxSpace.inset, 8),
      alignment: Alignment.center,
      child: SizedBox(width: double.infinity, child: child),
    );
  }

  @override
  bool shouldRebuild(_SegmentHeader old) =>
      old.child != child || old.background != background;
}

/// Summary card for one group drive.
class RideCard extends StatelessWidget {
  const RideCard({super.key, required this.ride});

  final RideDto ride;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final hostName = ride.host?.displayName ?? 'a driver';
    final String when;
    if (ride.isLive) {
      when = 'Live now';
    } else if (ride.isOver) {
      when = ride.endedAt != null
          ? 'Ended ${formatRideTime(ride.endedAt!)}'
          : (ride.status == 'cancelled' ? 'Cancelled' : 'Ended');
    } else if (ride.scheduledAt != null) {
      when = formatRideTime(ride.scheduledAt!);
    } else {
      when = 'Starts when the host is ready';
    }

    return Semantics(
      button: true,
      label: '${ride.title}, ${ride.status}, hosted by $hostName, $when',
      child: RxCard(
        onTap: () => context.push('/rides/live/${ride.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    ride.title,
                    style: rx.headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: RxSpace.s),
                RxRideStatusPill(status: ride.status),
              ],
            ),
            if (ride.description != null && ride.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                ride.description!,
                style: rx.subheadline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                RxAvatar(
                  name: hostName,
                  avatarPath: ride.host?.avatarPath,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hosted by $hostName',
                    style: rx.footnote,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (ride.isParticipant)
                  RxPill(
                    label: 'Joined',
                    color: rx.success,
                    icon: CupertinoIcons.checkmark_alt,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  ride.isLive
                      ? CupertinoIcons.dot_radiowaves_left_right
                      : CupertinoIcons.clock,
                  size: 14,
                  color: ride.isLive ? rx.destructive : rx.secondaryLabel,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    when,
                    style: rx.footnote.copyWith(
                      color: ride.isLive ? rx.destructive : rx.secondaryLabel,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(CupertinoIcons.person_2_fill,
                    size: 14, color: rx.secondaryLabel),
                const SizedBox(width: 4),
                Text('${ride.participantCount}', style: rx.footnote),
                if (ride.visibility == 'private') ...[
                  const SizedBox(width: 10),
                  Icon(CupertinoIcons.lock_fill,
                      size: 13, color: rx.secondaryLabel),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
