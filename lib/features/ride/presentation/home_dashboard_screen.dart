import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/glass_container.dart';
import '../../ride/domain/ride_engine.dart';
import '../../../main.dart';

// Provider that loads aggregate stats from the database
final homeStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
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

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar Navigation
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GlassContainer(
                    padding: const EdgeInsets.all(12),
                    borderRadius: 16,
                    child: IconButton(
                      icon: const Icon(Icons.two_wheeler, color: Colors.white),
                      onPressed: () => context.push('/garage'),
                    ),
                  ),
                  Row(
                    children: [
                      GlassContainer(
                        padding: const EdgeInsets.all(12),
                        borderRadius: 16,
                        child: IconButton(
                          icon: const Icon(Icons.map_outlined, color: Colors.white),
                          onPressed: () => context.push('/map'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      GlassContainer(
                        padding: const EdgeInsets.all(12),
                        borderRadius: 16,
                        child: IconButton(
                          icon: const Icon(Icons.history, color: Colors.white),
                          onPressed: () => context.push('/history'),
                        ),
                      ),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Ready to ride?',
                style: theme.textTheme.displayMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Connect to GPS and start recording your journey.',
                style: theme.textTheme.bodyMedium,
              ),
              const Spacer(),
              Center(
                child: GlassContainer(
                  borderRadius: 100,
                  padding: const EdgeInsets.all(32),
                  child: InkWell(
                    onTap: () => context.push('/ride'),
                    borderRadius: BorderRadius.circular(100),
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.primary,
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.4),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'START',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // ── REAL STATS FROM DATABASE ──
              statsAsync.when(
                loading: () => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStat(context, '--', 'RIDES'),
                    _buildStat(context, '-- km', 'TOTAL DIST'),
                    _buildStat(context, '-- km/h', 'TOP SPEED'),
                  ],
                ),
                error: (_, __) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStat(context, '0', 'RIDES'),
                    _buildStat(context, '0 km', 'TOTAL DIST'),
                    _buildStat(context, '0 km/h', 'TOP SPEED'),
                  ],
                ),
                data: (stats) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStat(context, '${stats['count']}', 'RIDES'),
                    _buildStat(context, '${(stats['totalDist'] as double).toStringAsFixed(1)} km', 'TOTAL DIST'),
                    _buildStat(context, '${(stats['topSpeed'] as double).toStringAsFixed(0)} km/h', 'TOP SPEED'),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStat(BuildContext context, String value, String label) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 12,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}
