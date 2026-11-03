import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../main.dart';
import '../../../shared/widgets/glass.dart';
import '../../auth/application/auth_notifier.dart';

final homeStatsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final count = await dbService.getRideCount();
  final totalDist = await dbService.getTotalDistance();
  final topSpeed = await dbService.getOverallTopSpeed();
  return {
    'count': count,
    'totalDist': totalDist,
    'topSpeed': topSpeed,
  };
});

class HomeDashboardScreen extends ConsumerWidget {
  const HomeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statsAsync = ref.watch(homeStatsProvider);
    final user = ref.watch(authNotifierProvider).user;

    return GlassScaffold(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _GlassIconButton(
                icon: Icons.directions_car,
                tooltip: 'Garage',
                onPressed: () => context.push('/garage'),
              ),
              Row(
                children: [
                  _GlassIconButton(
                    icon: Icons.map_outlined,
                    onPressed: () => context.push('/map'),
                  ),
                  const SizedBox(width: 10),
                  _GlassIconButton(
                    icon: Icons.history,
                    onPressed: () => context.push('/history'),
                  ),
                  const SizedBox(width: 10),
                  _GlassIconButton(
                    icon: Icons.logout,
                    tooltip: 'Sign out',
                    onPressed: () =>
                        ref.read(authNotifierProvider.notifier).logout(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'RideX',
            style: theme.textTheme.displayMedium?.copyWith(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            user != null
                ? 'Hey ${user.displayName} — ready for the road?'
                : 'Ready for the road? Connect GPS and start your drive.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 22),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                GlassNavChip(
                  label: 'Discover',
                  icon: Icons.explore_outlined,
                  onTap: () => context.push('/rides'),
                ),
                GlassNavChip(
                  label: 'Friends',
                  icon: Icons.group_outlined,
                  onTap: () => context.push('/friends'),
                ),
                GlassNavChip(
                  label: 'Community',
                  icon: Icons.forum_outlined,
                  onTap: () => context.push('/community'),
                ),
                GlassNavChip(
                  label: 'Share',
                  icon: Icons.share_location,
                  onTap: () => context.push('/sharing'),
                ),
                GlassNavChip(
                  label: 'Garage',
                  icon: Icons.directions_car_filled_outlined,
                  onTap: () => context.push('/garage'),
                ),
              ],
            ),
          ),
          const Spacer(),
          Center(
            child: GlassContainer(
              variant: GlassVariant.intense,
              borderRadius: 120,
              padding: const EdgeInsets.all(18),
              child: InkWell(
                onTap: () => context.push('/ride'),
                borderRadius: BorderRadius.circular(100),
                child: Container(
                  width: 168,
                  height: 168,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF2D20), AppTheme.accent],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent.withOpacity(0.45),
                        blurRadius: 36,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'START',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.4,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          statsAsync.when(
            loading: () => const Row(
              children: [
                GlassStatCard(value: '--', label: 'Rides'),
                SizedBox(width: 10),
                GlassStatCard(value: '-- km', label: 'Total Dist'),
                SizedBox(width: 10),
                GlassStatCard(value: '--', label: 'Top Speed'),
              ],
            ),
            error: (_, __) => const Row(
              children: [
                GlassStatCard(value: '0', label: 'Rides'),
                SizedBox(width: 10),
                GlassStatCard(value: '0 km', label: 'Total Dist'),
                SizedBox(width: 10),
                GlassStatCard(value: '0', label: 'Top Speed'),
              ],
            ),
            data: (stats) => Row(
              children: [
                GlassStatCard(value: '${stats['count']}', label: 'Rides'),
                const SizedBox(width: 10),
                GlassStatCard(
                  value:
                      '${(stats['totalDist'] as double).toStringAsFixed(1)} km',
                  label: 'Total Dist',
                ),
                const SizedBox(width: 10),
                GlassStatCard(
                  value:
                      '${(stats['topSpeed'] as double).toStringAsFixed(0)} km/h',
                  label: 'Top Speed',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = GlassContainer(
      variant: GlassVariant.chip,
      borderRadius: 16,
      padding: const EdgeInsets.all(4),
      child: IconButton(
        icon: Icon(icon, color: AppTheme.textPrimary),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
    return button;
  }
}
