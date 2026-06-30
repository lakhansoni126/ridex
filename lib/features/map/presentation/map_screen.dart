import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../domain/polyline_engine.dart';
import '../../ride/domain/ride_engine.dart';
import '../../../database/models.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;
  LatLng? _currentLocation;
  bool _hasCentered = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  void _initLocation() async {
    bool hasPermission = await Geolocator.checkPermission() == LocationPermission.always || 
                         await Geolocator.checkPermission() == LocationPermission.whileInUse;
    
    if (!hasPermission) {
      await Geolocator.requestPermission();
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          if (!_hasCentered) {
            _mapController.move(_currentLocation!, 16.0);
            _hasCentered = true;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rideState = ref.watch(rideEngineProvider);
    
    final ridePoints = rideState.routePoints.map((p) => RidePoint()
      ..latitude = p.latitude
      ..longitude = p.longitude
      ..speed = p.speed * 3.6
    ).toList();

    final polylines = PolylineEngine.generateHeatmap(ridePoints);
    
    // Determine the blue dot position: prioritize the RideEngine if recording, else use the local Map location
    LatLng? markerPos;
    if (rideState.isRecording && rideState.lastPosition != null) {
      markerPos = LatLng(rideState.lastPosition!.latitude, rideState.lastPosition!.longitude);
    } else {
      markerPos = _currentLocation;
    }

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
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blueAccent,
        onPressed: () {
          if (markerPos != null) {
            _mapController.move(markerPos, 16.0);
          }
        },
        child: const Icon(Icons.my_location, color: Colors.white),
      ),
      body: FlutterMap(
        mapController: _mapController,
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
          PolylineLayer(
            polylines: polylines,
          ),
          if (markerPos != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: markerPos,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.circle, color: Colors.blueAccent, size: 20),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
