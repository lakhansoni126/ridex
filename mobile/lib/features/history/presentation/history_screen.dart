import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../database/models.dart';
import '../../../main.dart';
import '../../../shared/ui/ui.dart';
import '../../ride/presentation/home_dashboard_screen.dart';

final historyProvider = FutureProvider.autoDispose<List<Ride>>(
  (ref) => dbService.getRidesNewestFirst(),
);

/// All locally recorded drives, grouped by month.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  Future<void> _delete(BuildContext context, WidgetRef ref, Ride ride) async {
    final ok = await confirmRx(
      context,
      title: 'Delete This Drive?',
      message: 'The route and stats will be removed from this phone.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    try {
      await dbService.deleteRide(ride.id);
      ref.invalidate(historyProvider);
      ref.invalidate(driveStatsProvider);
    } catch (e) {
      if (context.mounted) showRxError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rx = context.rx;
    final rides = ref.watch(historyProvider);

    return RxLargeTitlePage(
      title: 'All Drives',
      previousPageTitle: 'Drive',
      onRefresh: () async => ref.invalidate(historyProvider),
      slivers: [
        ...rides.when(
          loading: () => const [RxSliverLoading()],
          error: (e, _) => [
            RxSliverCenter(
              child: RxErrorState(
                  error: e, onRetry: () => ref.invalidate(historyProvider)),
            ),
          ],
          data: (list) {
            if (list.isEmpty) {
              return [
                RxSliverCenter(
                  child: RxEmptyState(
                    icon: CupertinoIcons.car_detailed,
                    title: 'No Drives Yet',
                    message: 'Recorded drives appear here.',
                    actionLabel: 'Start a Drive',
                    onAction: () => context.push('/record'),
                  ),
                ),
              ];
            }
            final groups = <String, List<Ride>>{};
            for (final r in list) {
              groups
                  .putIfAbsent(DateFormat('MMMM yyyy').format(r.startTime),
                      () => [])
                  .add(r);
            }
            return [
              const SliverToBoxAdapter(child: SizedBox(height: RxSpace.s)),
              for (final entry in groups.entries)
                SliverToBoxAdapter(
                  child: RxSection(
                    header:
                        '${entry.key} · ${entry.value.fold<double>(0, (a, r) => a + r.distance).toStringAsFixed(0)} km',
                    children: [
                      for (final r in entry.value)
                        Dismissible(
                          key: ValueKey(r.id),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) async {
                            await _delete(context, ref, r);
                            return false;
                          },
                          background: Container(
                            color: rx.destructive,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(CupertinoIcons.trash,
                                color: Color(0xFFFFFFFF)),
                          ),
                          child: RxTile(
                            title: DateFormat('EEE d · h:mm a')
                                .format(r.startTime),
                            subtitle:
                                '${formatDuration(r.durationSeconds.toInt())} · ${r.avgSpeed.toStringAsFixed(0)} km/h avg · top ${r.topSpeed.toStringAsFixed(0)}',
                            detail: '${r.distance.toStringAsFixed(1)} km',
                            icon: CupertinoIcons.car_detailed,
                            iconColor: rx.accent,
                            onTap: () => context.push('/drive/ride/${r.id}'),
                          ),
                        ),
                    ],
                  ),
                ),
              RxSliverPadding(
                child: Text('Swipe left on a drive to delete it.',
                    style: rx.footnote, textAlign: TextAlign.center),
              ),
            ];
          },
        ),
      ],
    );
  }
}
