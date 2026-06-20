import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../domain/polyline_engine.dart';
import '../../ride/domain/ride_engine.dart';
import '../../../database/models.dart';

class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rideState = ref.watch(rideEngineProvider);
    
    final ridePoints = rideState.routePoints.map((p) => RidePoint()
      ..latitude = p.latitude
      ..longitude = p.longitude
      ..speed = p.speed * 3.6
    ).toList();

    final polylines = PolylineEngine.generateHeatmap(ridePoints);
    
    final initialTarget = rideState.lastPosition != null 
      ? LatLng(rideState.lastPosition!.latitude, rideState.lastPosition!.longitude)
      : const LatLng(37.7749, -122.4194);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => context.pop(),
        ),
        title: const Text('RIDE MAP'),
        centerTitle: true,
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: initialTarget,
          initialZoom: 16.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.ridex',
            // Simple color filter for dark mode aesthetic
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
          PolylineLayer(
            polylines: polylines,
          ),
          if (rideState.lastPosition != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(rideState.lastPosition!.latitude, rideState.lastPosition!.longitude),
                  child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
