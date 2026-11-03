import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/glass.dart';
import '../../../main.dart';
import '../../../database/models.dart';
import '../../map/domain/polyline_engine.dart';

class RideDetailScreen extends ConsumerStatefulWidget {
  final int rideId;
  const RideDetailScreen({super.key, required this.rideId});

  @override
  ConsumerState<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends ConsumerState<RideDetailScreen> {
  Ride? _ride;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRide();
  }

  Future<void> _loadRide() async {
    try {
      final ride = await dbService.getRideById(widget.rideId);
      if (mounted) {
        setState(() {
          _ride = ride;
          _loading = false;
          if (ride == null) _error = 'Ride not found';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Error loading ride: $e';
        });
      }
    }
  }

  String _formatDuration(double seconds) {
    final s = seconds.toInt();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const GlassScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _ride == null) {
      return GlassScaffold(
        appBar: const GlassAppBar(title: 'Ride'),
        body: Center(
          child: Text(_error ?? 'Ride not found',
              style: const TextStyle(color: AppTheme.textSecondary)),
        ),
      );
    }

    final ride = _ride!;
    final ridePoints = ride.points.toList();
    final polylines = PolylineEngine.generateHeatmap(ridePoints);

    // Calculate map bounds from ride points
    LatLng center = const LatLng(20.5937, 78.9629); // Default India
    double zoom = 5.0;

    if (ridePoints.isNotEmpty) {
      double minLat = ridePoints.first.latitude;
      double maxLat = ridePoints.first.latitude;
      double minLon = ridePoints.first.longitude;
      double maxLon = ridePoints.first.longitude;

      for (final p in ridePoints) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLon) minLon = p.longitude;
        if (p.longitude > maxLon) maxLon = p.longitude;
      }

      center = LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
      // Rough zoom estimation based on coordinate span
      final latSpan = maxLat - minLat;
      final lonSpan = maxLon - minLon;
      final span = latSpan > lonSpan ? latSpan : lonSpan;
      if (span < 0.005) {
        zoom = 17.0;
      } else if (span < 0.01) {
        zoom = 16.0;
      } else if (span < 0.05) {
        zoom = 14.0;
      } else if (span < 0.1) {
        zoom = 13.0;
      } else if (span < 0.5) {
        zoom = 11.0;
      } else {
        zoom = 9.0;
      }
    }

    // Start and end markers
    final markers = <Marker>[];
    if (ridePoints.isNotEmpty) {
      markers.add(Marker(
        point: LatLng(ridePoints.first.latitude, ridePoints.first.longitude),
        width: 36,
        height: 36,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.greenAccent.withOpacity(0.9),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.greenAccent.withOpacity(0.4),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.play_arrow, color: Colors.white, size: 18),
          ),
        ),
      ));
      markers.add(Marker(
        point: LatLng(ridePoints.last.latitude, ridePoints.last.longitude),
        width: 36,
        height: 36,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.9),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accent.withOpacity(0.4),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.stop, color: Colors.white, size: 18),
          ),
        ),
      ));
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // ── FULL SCREEN MAP ──
          FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: zoom,
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
              if (polylines.isNotEmpty)
                PolylineLayer(polylines: polylines),
              if (markers.isNotEmpty)
                MarkerLayer(markers: markers),
            ],
          ),

          // ── TOP BAR ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  GlassContainer(
                    variant: GlassVariant.mapOverlay,
                    padding: const EdgeInsets.all(4),
                    borderRadius: 12,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios,
                          color: AppTheme.textPrimary, size: 20),
                      onPressed: () => context.pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GlassContainer(
                    variant: GlassVariant.mapOverlay,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    borderRadius: 12,
                    child: Text(
                      DateFormat('MMM dd, yyyy • hh:mm a')
                          .format(ride.startTime),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── BOTTOM STATS PANEL ──
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              children: [
                // Speed Legend
                GlassContainer(
                  variant: GlassVariant.mapOverlay,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  borderRadius: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _legendDot(Colors.greenAccent, '< 40'),
                      _legendDot(Colors.yellowAccent, '40-80'),
                      _legendDot(Colors.orangeAccent, '80-120'),
                      _legendDot(AppTheme.accent, '> 120'),
                      const Text('km/h',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Stats Grid
                GlassContainer(
                  variant: GlassVariant.mapOverlay,
                  padding: const EdgeInsets.all(20),
                  borderRadius: 16,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _statTile(theme, Icons.straighten, 'DISTANCE',
                              '${ride.distance.toStringAsFixed(2)} km'),
                          _statTile(theme, Icons.timer, 'DURATION',
                              _formatDuration(ride.durationSeconds)),
                          _statTile(theme, Icons.gps_fixed, 'POINTS',
                              '${ridePoints.length}'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _statTile(theme, Icons.speed, 'AVG SPEED',
                              '${ride.avgSpeed.toStringAsFixed(1)} km/h'),
                          _statTile(theme, Icons.flash_on, 'TOP SPEED',
                              '${ride.topSpeed.toStringAsFixed(0)} km/h'),
                          _statTile(theme, Icons.rotate_left, 'MAX TILT',
                              '${ride.maxLeanAngle.toStringAsFixed(0)}°'),
                        ],
                      ),
                      if (ride.weatherCondition != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          '${ride.temperatureCelsius?.toStringAsFixed(0) ?? '--'}°C • ${ride.weatherCondition}',
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 11)),
      ],
    );
  }

  Widget _statTile(ThemeData theme, IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.accent, size: 20),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 10, letterSpacing: 1)),
      ],
    );
  }
}
