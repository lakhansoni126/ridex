import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:isar/isar.dart';

import '../../../core/theme/app_theme.dart';
import '../../../database/models.dart';
import '../../../main.dart';
import '../../../shared/widgets/glass.dart';

final garageProvider = FutureProvider.autoDispose<List<Vehicle>>((ref) async {
  return await dbService.isar.vehicles.where().findAll();
});

class GarageScreen extends ConsumerStatefulWidget {
  const GarageScreen({super.key});

  @override
  ConsumerState<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends ConsumerState<GarageScreen> {
  void _showAddVehicleDialog() {
    final nameController = TextEditingController();
    final brandController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.glassBorder),
        ),
        title: const Text('Add Car',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: AppTheme.textPrimary),
              cursorColor: AppTheme.accent,
              decoration: const InputDecoration(
                labelText: 'Name (e.g. Daily Driver)',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            TextField(
              controller: brandController,
              style: const TextStyle(color: AppTheme.textPrimary),
              cursorColor: AppTheme.accent,
              decoration: const InputDecoration(
                labelText: 'Make (e.g. Toyota)',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => context.pop(), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              final vehicle = Vehicle()
                ..name = nameController.text
                ..brand = brandController.text;

              await dbService.isar.writeTxn(() async {
                await dbService.isar.vehicles.put(vehicle);
              });

              if (context.mounted) context.pop();
              ref.invalidate(garageProvider);
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(garageProvider);

    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Garage',
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddVehicleDialog,
          )
        ],
      ),
      body: vehiclesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (vehicles) {
          if (vehicles.isEmpty) {
            return const Center(
              child: Text(
                'No cars in garage. Add one!',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: vehicles.length,
            itemBuilder: (context, index) {
              final vehicle = vehicles[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: GlassContainer(
                  variant: GlassVariant.card,
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vehicle.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                    fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            vehicle.brand,
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 16),
                          ),
                        ],
                      ),
                      const Icon(Icons.directions_car,
                          size: 40, color: AppTheme.accent),
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
