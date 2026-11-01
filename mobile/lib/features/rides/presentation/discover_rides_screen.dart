import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/api/rides_repository.dart';
import '../../../shared/widgets/glass_container.dart';

final discoverRidesProvider = FutureProvider.autoDispose<List<RideDto>>((ref) {
  return ref.watch(ridesRepositoryProvider).listRides();
});

class DiscoverRidesScreen extends ConsumerWidget {
  const DiscoverRidesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ridesAsync = ref.watch(discoverRidesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Discover drives'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            tooltip: 'Join with code',
            onPressed: () => context.push('/rides/join'),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create drive',
            onPressed: () => context.push('/rides/create'),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.accent,
        onRefresh: () async => ref.invalidate(discoverRidesProvider),
        child: ridesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: Text('Could not load drives\n$e',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          data: (rides) {
            if (rides.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  Text(
                    'No public drives yet. Create one or join with a code.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => context.push('/rides/create'),
                    child: const Text('CREATE DRIVE'),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: rides.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, i) {
                final ride = rides[i];
                return InkWell(
                  onTap: () => context.push('/rides/live/${ride.id}'),
                  borderRadius: BorderRadius.circular(24),
                  child: GlassContainer(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                ride.title,
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontSize: 20),
                              ),
                            ),
                            _StatusChip(status: ride.status),
                          ],
                        ),
                        if (ride.description != null &&
                            ride.description!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(ride.description!,
                              style: theme.textTheme.bodyMedium),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          '${ride.participants.length} drivers · code ${ride.joinCode}',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'live' => AppTheme.accent,
      'scheduled' => Colors.amber,
      'ended' => Colors.grey,
      _ => Colors.blueGrey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
