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
            return const Center(child: Text('No rides recorded yet.', style: TextStyle(color: Colors.white70)));
          }
          // Sort newest first
          rides.sort((a, b) => b.startTime.compareTo(a.startTime));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rides.length,
            itemBuilder: (context, index) {
              final ride = rides[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: GlassContainer(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('MMM dd, yyyy').format(ride.startTime),
                            style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            DateFormat('hh:mm a').format(ride.startTime),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${ride.distance.toStringAsFixed(1)} km',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDuration(ride.durationSeconds),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        onSelected: (value) async {
                          if (value == 'replay') {
                            // Can pass ride ID to replay screen in future
                            context.push('/replay');
                          } else if (value == 'export') {
                            await ExportService.exportRideToJson(ride);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'replay',
                            child: Text('Play Replay'),
                          ),
                          const PopupMenuItem(
                            value: 'export',
                            child: Text('Export JSON'),
                          ),
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
}
