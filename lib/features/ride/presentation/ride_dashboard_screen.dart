import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/glass_container.dart';

class RideDashboardScreen extends StatefulWidget {
  const RideDashboardScreen({super.key});

  @override
  State<RideDashboardScreen> createState() => _RideDashboardScreenState();
}

class _RideDashboardScreenState extends State<RideDashboardScreen> {
  // Mock data for UI layout
  double speed = 104.2;
  double distance = 12.4;
  String duration = '00:14:32';
  double topSpeed = 122.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
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
                    onPressed: () => context.pop(),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.red.withOpacity(0.5)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.circle, color: Colors.red, size: 12),
                        SizedBox(width: 8),
                        Text('REC', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
                      speed.toStringAsFixed(1),
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
                    _buildMetric(context, 'DISTANCE', '${distance.toStringAsFixed(1)} km'),
                    Container(width: 1, height: 40, color: Colors.white24),
                    _buildMetric(context, 'DURATION', duration),
                    Container(width: 1, height: 40, color: Colors.white24),
                    _buildMetric(context, 'TOP', '${topSpeed.toStringAsFixed(0)} km/h'),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  // Stop ride logic
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
