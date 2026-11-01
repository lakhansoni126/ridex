import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/glass_container.dart';
import '../../../main.dart';
import '../../../database/models.dart';
import '../../../services/export_service.dart';
import 'package:intl/intl.dart';

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
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => context.pop(),
        ),
        title: const Text('RIDE HISTORY'),
        centerTitle: true,
      ),
      body: ridesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (rides) {
          if (rides.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_car, size: 64, color: Colors.white.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  const Text('No rides recorded yet.',
                      style: TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text('Start a ride to see your history here.',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                ],
              ),
            );
          }
          // Sort newest first
          rides.sort((a, b) => b.startTime.compareTo(a.startTime));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rides.length,
            itemBuilder: (context, index) {
              final ride = rides[index];
              final pointCount = ride.points.length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: GestureDetector(
                  onTap: () {
                    // Navigate to the ride detail screen with the ride's ID
                    context.push('/ride-detail/${ride.id}');
                  },
                  child: GlassContainer(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Header row: date + menu ──
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateFormat('MMM dd, yyyy').format(ride.startTime),
                                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('hh:mm a').format(ride.startTime),
                                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white54),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                // GPS points badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: pointCount > 0
                                        ? Colors.greenAccent.withOpacity(0.15)
                                        : Colors.redAccent.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$pointCount pts',
                                    style: TextStyle(
                                      color: pointCount > 0 ? Colors.greenAccent : Colors.redAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
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
                        // ── Stats row ──
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _statChip(theme, Icons.straighten, '${ride.distance.toStringAsFixed(1)} km'),
                            _statChip(theme, Icons.timer, _formatDuration(ride.durationSeconds)),
                            _statChip(theme, Icons.speed, '${ride.avgSpeed.toStringAsFixed(0)} avg'),
                            _statChip(theme, Icons.flash_on, '${ride.topSpeed.toStringAsFixed(0)} top'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Tap hint
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('Tap to view route',
                                style: TextStyle(
                                    color: theme.colorScheme.primary.withOpacity(0.6),
                                    fontSize: 11,
                                    letterSpacing: 0.5)),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right,
                                color: theme.colorScheme.primary.withOpacity(0.6),
                                size: 16),
                          ],
                        ),
                      ],
                    ),
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
        Icon(icon, size: 14, color: theme.colorScheme.primary),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(
                color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
