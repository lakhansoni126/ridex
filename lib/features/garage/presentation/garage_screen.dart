import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/glass_container.dart';
import '../../../database/models.dart';
import '../../../main.dart';

final garageProvider = FutureProvider.autoDispose<List<Bike>>((ref) async {
  return await dbService.isar.bikes.where().findAll();
});

class GarageScreen extends ConsumerStatefulWidget {
  const GarageScreen({super.key});

  @override
  ConsumerState<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends ConsumerState<GarageScreen> {
  void _showAddBikeDialog() {
    final nameController = TextEditingController();
    final brandController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Add Motorcycle', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Model (e.g. R1)', labelStyle: TextStyle(color: Colors.white54)),
            ),
            TextField(
              controller: brandController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Brand (e.g. Yamaha)', labelStyle: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => context.pop(), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              final bike = Bike()
                ..name = nameController.text
                ..brand = brandController.text;
              
              await dbService.isar.writeTxn(() async {
                await dbService.isar.bikes.put(bike);
              });
              
              context.pop();
              ref.refresh(garageProvider);
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bikesAsync = ref.watch(garageProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => context.pop(),
        ),
        title: const Text('GARAGE'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddBikeDialog,
          )
        ],
      ),
      body: bikesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (bikes) {
          if (bikes.isEmpty) {
            return const Center(child: Text('No bikes in garage. Add one!', style: TextStyle(color: Colors.white70)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: bikes.length,
            itemBuilder: (context, index) {
              final bike = bikes[index];
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
                            bike.name,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            bike.brand,
                            style: const TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                        ],
                      ),
                      const Icon(Icons.two_wheeler, size: 40, color: Colors.white38),
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
