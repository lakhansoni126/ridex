import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
    return Scaffold(
      body: Stack(
        children: [
          // Background Map Placeholder
          const GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(37.7749, -122.4194),
              zoom: 14.0,
            ),
            zoomControlsEnabled: false,
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
                      children: [
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
