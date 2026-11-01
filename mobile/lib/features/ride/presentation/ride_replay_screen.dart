import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../shared/widgets/glass_container.dart';

class RideReplayScreen extends StatefulWidget {
  const RideReplayScreen({super.key});

  @override
  State<RideReplayScreen> createState() => _RideReplayScreenState();
}

class _RideReplayScreenState extends State<RideReplayScreen> {
  double _currentProgress = 0;
  bool _isPlaying = false;

  @override
  Widget build(BuildContext context) {
    // Mock elevation data for demonstration
    final mockElevationPoints = [
      const FlSpot(0, 100),
      const FlSpot(1, 120),
      const FlSpot(2, 130),
      const FlSpot(3, 110),
      const FlSpot(4, 90),
      const FlSpot(5, 140),
    ];

    return Scaffold(
      body: Stack(
        children: [
          // Background Map Placeholder
          FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(37.7749, -122.4194),
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.ridex',
                tileBuilder: (context, tileWidget, tile) {
                  return ColorFiltered(
                    colorFilter: const ColorFilter.matrix([
                      -1,  0,  0, 0, 255,
                       0, -1,  0, 0, 255,
                       0,  0, -1, 0, 255,
                       0,  0,  0, 1,   0,
                    ]),
                    child: tileWidget,
                  );
                },
              ),
            ],
          ),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      GlassContainer(
                        padding: const EdgeInsets.all(8),
                        borderRadius: 12,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                          onPressed: () => context.pop(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const GlassContainer(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        borderRadius: 12,
                        child: Text(
                          'RIDE REPLAY',
                          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  GlassContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Elevation Profile Chart
                        SizedBox(
                          height: 80,
                          child: LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: false),
                              titlesData: const FlTitlesData(show: false),
                              borderData: FlBorderData(show: false),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: mockElevationPoints,
                                  isCurved: true,
                                  color: Colors.blueAccent,
                                  barWidth: 2,
                                  isStrokeCapRound: true,
                                  dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: Colors.blueAccent.withOpacity(0.2),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('00:00', style: TextStyle(color: Colors.white70)),
                            Text('${(_currentProgress * 42).toStringAsFixed(0)}:00', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Slider(
                          value: _currentProgress,
                          onChanged: (val) {
                            setState(() {
                              _currentProgress = val;
                            });
                          },
                          activeColor: Theme.of(context).colorScheme.primary,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                              iconSize: 64,
                              color: Theme.of(context).colorScheme.primary,
                              onPressed: () {
                                setState(() {
                                  _isPlaying = !_isPlaying;
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
