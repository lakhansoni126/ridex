import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
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

  void _triggerSosSms(double lat, double lon) async {
    final url = Uri.parse(
      'sms:?body=SOS! I may have crashed on my motorcycle. Location: https://maps.google.com/?q=$lat,$lon'
    );
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    } catch (e) {
      debugPrint('Could not launch SMS: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rideState = ref.watch(rideEngineProvider);

    // ── SOS CRASH OVERLAY ──
    if (rideState.hasCrashed) {
      return Scaffold(
        backgroundColor: Colors.red[900],
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 100, color: Colors.white),
                const SizedBox(height: 20),
                const Text('CRASH DETECTED', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 10),
                const Text('Are you okay?', style: TextStyle(fontSize: 18, color: Colors.white70)),
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
                    _triggerSosSms(
                      rideState.lastPosition?.latitude ?? 0,
                      rideState.lastPosition?.longitude ?? 0,
                    );
                    ref.read(rideEngineProvider.notifier).cancelSOS();
                  },
                  child: const Text('SEND SOS NOW', style: TextStyle(color: Colors.white70, fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── NORMAL RIDE DASHBOARD ──
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: weather/pause status + map button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Recording indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: rideState.isPaused
                          ? Colors.orange.withOpacity(0.2)
                          : Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: rideState.isPaused
                            ? Colors.orange.withOpacity(0.5)
                            : Colors.red.withOpacity(0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          color: rideState.isPaused ? Colors.orange : Colors.red,
                          size: 10,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          rideState.isPaused ? 'PAUSED' : 'REC',
                          style: TextStyle(
                            color: rideState.isPaused ? Colors.orange : Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Weather info
                  if (rideState.weatherCondition != null)
                    Text(
                      '${rideState.temperature?.toStringAsFixed(0) ?? '--'}°C • ${rideState.weatherCondition}',
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  // Map button
                  GlassContainer(
                    padding: const EdgeInsets.all(8),
                    borderRadius: 14,
                    child: IconButton(
                      icon: const Icon(Icons.map, color: Colors.white, size: 22),
                      onPressed: () => context.push('/map'),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // ── SPEEDOMETER ──
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

            // ── ANALYTICS GRID ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: GlassContainer(
                padding: const EdgeInsets.all(20),
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

            const SizedBox(height: 30),

            // ── FINISH RIDE BUTTON ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: GestureDetector(
                onTap: () async {
                  await ref.read(rideEngineProvider.notifier).stopRide();
                  if (context.mounted) {
                    context.go('/');
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
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
