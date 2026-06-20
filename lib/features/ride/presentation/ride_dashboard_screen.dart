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
              const Icon(Icons.warning_amber_rounded, size: 100, color: Colors.white),
              const SizedBox(height: 20),
              const Text('CRASH DETECTED', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('Sending SOS in 30 seconds...', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 40),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                ),
                onPressed: () {
                  ref.read(rideEngineProvider.notifier).cancelSOS();
                },
                child: const Text('I AM OKAY - CANCEL', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                   _triggerSosSms(context, rideState.lastPosition?.latitude ?? 0, rideState.lastPosition?.longitude ?? 0);
                   ref.read(rideEngineProvider.notifier).cancelSOS();
                },
                child: const Text('SEND SOS NOW', style: TextStyle(color: Colors.white70)),
              )
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (rideState.isPaused)
                    const Text('AUTO-PAUSED', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, letterSpacing: 2))
                  else if (rideState.weatherCondition != null)
                    Text('${rideState.temperature}°C • ${rideState.weatherCondition}', style: const TextStyle(color: Colors.white70))
                  else
                    const SizedBox.shrink(),
                  
                  IconButton(
                    icon: const Icon(Icons.map, color: Colors.white),
                    onPressed: () => context.push('/map'),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Speedometer
            Text(
              rideState.currentSpeed.toStringAsFixed(0),
              style: const TextStyle(
                fontSize: 140,
                fontWeight: FontWeight.bold,
                height: 1.0,
                letterSpacing: -5,
              ),
            ),
            Text(
              'KM/H',
              style: TextStyle(
                fontSize: 24,
                color: theme.colorScheme.primary,
                letterSpacing: 4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            // Analytics Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: GlassContainer(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMetric(context, 'TRIP', '${rideState.distance.toStringAsFixed(1)} km'),
                      _buildMetric(context, 'TIME', _formatDuration(rideState.durationSeconds)),
                      _buildMetric(context, 'LEAN', '${rideState.currentLeanAngle.toStringAsFixed(0)}°'),
                      _buildMetric(context, 'TOP', '${rideState.topSpeed.toStringAsFixed(0)} km/h'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            // Finish Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: GestureDetector(
                onTap: () async {
                  await ref.read(rideEngineProvider.notifier).stopRide();
                  if (context.mounted) {
                    context.pop();
                  }
                },
                child: GlassContainer(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  borderRadius: 30,
                  child: const Center(
                    child: Text(
                      'FINISH RIDE',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(BuildContext context, String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
