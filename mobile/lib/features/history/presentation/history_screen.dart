import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../database/models.dart';
import '../../../main.dart';
import '../../../services/export_service.dart';
import '../../../shared/widgets/glass.dart';

final historyProvider = FutureProvider.autoDispose<List<Ride>>((ref) async {
  return await dbService.getAllRides();
});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  String _formatDuration(double seconds) {
    final s = seconds.toInt();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ridesAsync = ref.watch(historyProvider);

    return GlassScaffold(
      appBar: const GlassAppBar(title: 'Ride History', centerTitle: true),
      body: ridesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (rides) {
          if (rides.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_car,
                      size: 64,
                      color: AppTheme.textPrimary.withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  const Text('No rides recorded yet.',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('Start a ride to see your history here.',
                      style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.7),
                          fontSize: 13)),
                ],
              ),
            );
          }
          rides.sort((a, b) => b.startTime.compareTo(a.startTime));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rides.length,
            itemBuilder: (context, index) {
              final ride = rides[index];
              final pointCount = ride.points.length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: GlassContainer(
                  variant: GlassVariant.card,
                  padding: const EdgeInsets.all(20),
                  onTap: () => context.push('/ride-detail/${ride.id}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('MMM dd, yyyy')
                                    .format(ride.startTime),
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontSize: 18),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('hh:mm a').format(ride.startTime),
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: pointCount > 0
                                      ? Colors.greenAccent
                                          .withValues(alpha: 0.15)
                                      : AppTheme.accentSoft,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$pointCount pts',
                                  style: TextStyle(
                                    color: pointCount > 0
                                        ? Colors.greenAccent
                                        : AppTheme.accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert,
                                    color: AppTheme.textSecondary, size: 20),
                                onSelected: (value) async {
                                  if (value == 'export') {
                                    await ExportService.exportRideToJson(ride);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'export',
                                    child: Text('Export JSON'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _statChip(theme, Icons.straighten,
                              '${ride.distance.toStringAsFixed(1)} km'),
                          _statChip(theme, Icons.timer,
                              _formatDuration(ride.durationSeconds)),
                          _statChip(theme, Icons.speed,
                              '${ride.avgSpeed.toStringAsFixed(0)} avg'),
                          _statChip(theme, Icons.flash_on,
                              '${ride.topSpeed.toStringAsFixed(0)} top'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('Tap to view route',
                              style: TextStyle(
                                  color: AppTheme.accent.withValues(alpha: 0.8),
                                  fontSize: 11,
                                  letterSpacing: 0.5)),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right,
                              color: AppTheme.accent.withValues(alpha: 0.8),
                              size: 16),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _statChip(ThemeData theme, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.accent),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}
