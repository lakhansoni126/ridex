import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/glass_container.dart';
import '../domain/ride_engine.dart';

class RideDashboardScreen extends ConsumerStatefulWidget {
  const RideDashboardScreen({super.key});

  @override
  ConsumerState<RideDashboardScreen> createState() => _RideDashboardScreenState();
}

class _RideDashboardScreenState extends ConsumerState<RideDashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Start the ride when the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rideEngineProvider.notifier).startRide();
    });
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rideState = ref.watch(rideEngineProvider);
    
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () {
                      ref.read(rideEngineProvider.notifier).stopRide();
                      context.pop();
                    },
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: rideState.isRecording ? Colors.red.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: rideState.isRecording ? Colors.red.withOpacity(0.5) : Colors.grey.withOpacity(0.5)
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.circle, color: rideState.isRecording ? Colors.red : Colors.grey, size: 12),
                        const SizedBox(width: 8),
                        Text(
                          rideState.isRecording ? 'REC' : 'STOPPED', 
                          style: TextStyle(
                            color: rideState.isRecording ? Colors.red : Colors.grey, 
                            fontWeight: FontWeight.bold
                          )
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 60),
              Center(
                child: Column(
                  children: [
                    Text(
                      rideState.currentSpeed.toStringAsFixed(1),
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontSize: 120,
                        height: 1.0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      'km/h',
                      style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              GlassContainer(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetric(context, 'DISTANCE', '${rideState.distance.toStringAsFixed(1)} km'),
                    Container(width: 1, height: 40, color: Colors.white24),
                    _buildMetric(context, 'DURATION', _formatDuration(rideState.durationSeconds)),
                    Container(width: 1, height: 40, color: Colors.white24),
                    _buildMetric(context, 'TOP', '${rideState.topSpeed.toStringAsFixed(0)} km/h'),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  ref.read(rideEngineProvider.notifier).stopRide();
                  context.pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                child: const Text('FINISH RIDE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetric(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 10, letterSpacing: 2),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
        ),
      ],
    );
  }
}
