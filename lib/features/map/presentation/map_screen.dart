import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../domain/polyline_engine.dart';
import '../../ride/domain/ride_engine.dart';
import '../../../database/models.dart';

class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rideState = ref.watch(rideEngineProvider);
    
    // Convert Position to RidePoint for the engine
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
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: initialTarget,
          zoom: 16.0,
        ),
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        compassEnabled: true,
        zoomControlsEnabled: false,
        polylines: polylines,
      ),
    );
  }
}
