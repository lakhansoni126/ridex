import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../database/models.dart';
import '../../../main.dart';
import '../../../shared/ui/ui.dart';
import '../../auth/application/auth_notifier.dart';
import '../../permissions/presentation/permission_education_screen.dart';
import '../domain/ride_engine.dart';

class DriveStats {
  const DriveStats({
    required this.count,
    required this.totalKm,
    required this.topSpeed,
    required this.recent,
  });

  final int count;
  final double totalKm;
  final double topSpeed;
  final List<Ride> recent;
}

final driveStatsProvider = FutureProvider.autoDispose<DriveStats>((ref) async {
  final results = await Future.wait([
    dbService.getRideCount(),
    dbService.getTotalDistance(),
    dbService.getOverallTopSpeed(),
    dbService.getRecentRides(limit: 3),
  ]);
  return DriveStats(
    count: results[0] as int,
    totalKm: results[1] as double,
    topSpeed: results[2] as double,
    recent: results[3] as List<Ride>,
  );
});

/// "Drive" tab: start a solo drive, glance at stats, open recent drives.
class HomeDashboardScreen extends ConsumerWidget {
  const HomeDashboardScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rx = context.rx;
    final user = ref.watch(authNotifierProvider).user;
    final stats = ref.watch(driveStatsProvider);
    final permission = ref.watch(locationPermissionProvider).valueOrNull;
    final recording = ref.watch(rideEngineProvider.select((s) => s.isRecording));
    final firstName = (user?.displayName ?? '').split(' ').first;

    return RxLargeTitlePage(
      title: 'Drive',
      trailing: RxNavIconButton(
        icon: CupertinoIcons.map,
        semanticLabel: 'Open map',
        onPressed: () => context.push('/map'),
      ),
      onRefresh: () async {
        ref.invalidate(driveStatsProvider);
        ref.invalidate(locationPermissionProvider);
        await ref.read(driveStatsProvider.future);
      },
      slivers: [
        RxSliverPadding(
          top: RxSpace.xs,
          child: Text(
            firstName.isEmpty
                ? '${_greeting()}.'
                : '${_greeting()}, $firstName.',
            style: rx.subheadline,
          ),
        ),
        if (permission != null && !permissionGranted(permission))
          RxSliverPadding(
            top: RxSpace.m,
            child: RxCard(
              onTap: () => context.push('/permissions'),
              child: Row(
                children: [
                  RxIconBadge(
                      icon: CupertinoIcons.location_slash_fill,
                      color: rx.warning),
                  const SizedBox(width: RxSpace.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Location is off', style: rx.headline),
                        Text('Turn it on to record drives.',
                            style: rx.footnote),
                      ],
                    ),
                  ),
                  Icon(CupertinoIcons.chevron_right,
                      size: 16, color: rx.tertiaryLabel),
                ],
              ),
            ),
          ),
        RxSliverPadding(
          top: RxSpace.l,
          child: _StartCard(
            recording: recording,
            onStart: () {
              HapticFeedback.mediumImpact();
              context.push('/record');
            },
          ),
        ),
        RxSliverPadding(
          top: RxSpace.l,
          bottom: RxSpace.s,
          child: stats.when(
            loading: () => const _StatsRow(count: '–', km: '–', top: '–'),
            error: (_, __) => const _StatsRow(count: '0', km: '0', top: '0'),
            data: (s) => _StatsRow(
              count: '${s.count}',
              km: s.totalKm.toStringAsFixed(s.totalKm < 100 ? 1 : 0),
              top: s.topSpeed.toStringAsFixed(0),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: RxSpace.m),
            child: stats.maybeWhen(
              data: (s) => s.recent.isEmpty
                  ? RxSection(
                      header: 'Recent Drives',
                      footer:
                          'Your drives are saved on this phone. Tap Start to record your first one.',
                      children: const [
                        RxTile(
                          title: 'No drives yet',
                          icon: CupertinoIcons.car_detailed,
                        ),
                      ],
                    )
                  : RxSection(
                      header: 'Recent Drives',
                      children: [
                        for (final r in s.recent) _RecentDriveTile(ride: r),
                        RxTile(
                          title: 'All Drives',
                          icon: CupertinoIcons.clock_fill,
                          iconColor: rx.indigo,
                          detail: '${s.count}',
                          onTap: () => context.push('/drive/history'),
                        ),
                      ],
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: RxSection(
            header: 'Together',
            children: [
              RxTile(
                title: 'Group Drives',
                subtitle: 'Drive with friends and see everyone live',
                icon: CupertinoIcons.flag_fill,
                iconColor: rx.success,
                onTap: () => context.go('/rides'),
              ),
              RxTile(
                title: 'Share My Location',
                subtitle: 'Let friends follow along',
                icon: CupertinoIcons.location_fill,
                iconColor: rx.info,
                onTap: () => context.go('/friends/sharing'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({required this.recording, required this.onStart});

  final bool recording;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Semantics(
      button: true,
      label: recording ? 'Return to current drive' : 'Start a drive',
      excludeSemantics: true,
      child: RxPressable(
        onTap: onStart,
        child: Container(
          height: 168,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RxSpace.radiusLarge + 4),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                rx.accent,
                Color.lerp(rx.accent, const Color(0xFF000000), 0.35)!,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: rx.accent.withOpacity(0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(RxSpace.l),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      recording ? 'Drive in progress' : 'Ready to drive?',
                      style: rx.title2.copyWith(color: rx.onAccent),
                    ),
                    const SizedBox(height: RxSpace.xs),
                    Text(
                      recording
                          ? 'Tap to return to your dashboard.'
                          : 'Track speed, distance and your route.',
                      style: rx.subheadline
                          .copyWith(color: rx.onAccent.withOpacity(0.85)),
                    ),
                  ],
                ),
              ),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: rx.onAccent,
                ),
                child: Icon(
                  recording ? CupertinoIcons.speedometer : CupertinoIcons.play_fill,
                  color: rx.accent,
                  size: 32,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.count, required this.km, required this.top});

  final String count;
  final String km;
  final String top;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    Widget cell(String v, String unit, String label, IconData icon, Color c) =>
        Expanded(
          child: RxCard(
            padding: const EdgeInsets.all(12),
            child: RxMetric(
              value: v,
              unit: unit,
              label: label,
              icon: icon,
              iconColor: c,
              valueSize: 20,
            ),
          ),
        );
    return Row(
      children: [
        cell(count, '', 'Drives', CupertinoIcons.car_detailed, rx.accent),
        const SizedBox(width: RxSpace.s),
        cell(km, 'km', 'Distance', CupertinoIcons.map_fill, rx.info),
        const SizedBox(width: RxSpace.s),
        cell(top, 'km/h', 'Top', CupertinoIcons.bolt_fill, rx.warning),
      ],
    );
  }
}

class _RecentDriveTile extends StatelessWidget {
  const _RecentDriveTile({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return RxTile(
      title: DateFormat('EEE, MMM d · h:mm a').format(ride.startTime),
      subtitle:
          '${ride.distance.toStringAsFixed(1)} km · ${formatDuration(ride.durationSeconds.toInt())} · ${ride.avgSpeed.toStringAsFixed(0)} km/h avg',
      icon: CupertinoIcons.car_detailed,
      iconColor: rx.accent,
      onTap: () => context.push('/drive/ride/${ride.id}'),
    );
  }
}
