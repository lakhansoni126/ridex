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
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  void _initLocation() async {
    try {
      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        debugPrint('MapScreen: Location permission denied');
        return;
      }

      // Get one-shot position first
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        debugPrint('MapScreen: Initial fix: ${pos.latitude}, ${pos.longitude}');
        if (mounted) {
          setState(() {
            _currentLocation = LatLng(pos.latitude, pos.longitude);
          });
          if (_mapReady) {
            _mapController.move(_currentLocation!, 16.0);
          }
        }
      } catch (e) {
        debugPrint('MapScreen: Initial fix failed: $e');
      }

      // Start continuous updates
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0, // Get ALL updates
        ),
      ).listen(
        (Position position) {
          if (mounted) {
            final newLoc = LatLng(position.latitude, position.longitude);
            final isFirstFix = _currentLocation == null;
            setState(() {
              _currentLocation = newLoc;
            });
            if (isFirstFix && _mapReady) {
              _mapController.move(newLoc, 16.0);
            }
          }
        },
        onError: (e) {
          debugPrint('MapScreen: GPS stream error: $e');
        },
      );
    } catch (e) {
      debugPrint('MapScreen: Failed to init location: $e');
    }
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

    // Build polylines from ride route
    final ridePoints = rideState.routePoints.map((p) => RidePoint()
      ..latitude = p.latitude
      ..longitude = p.longitude
      ..speed = p.speed * 3.6
    ).toList();
    final polylines = PolylineEngine.generateHeatmap(ridePoints);

    // Blue dot: use ride engine position when recording, else map's own GPS
    LatLng? markerPos;
    if (rideState.isRecording && rideState.lastPosition != null) {
      markerPos = LatLng(rideState.lastPosition!.latitude, rideState.lastPosition!.longitude);
    } else {
      markerPos = _currentLocation;
    }

    // Default center: India
    final initialCenter = _currentLocation ?? const LatLng(20.5937, 78.9629);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => context.pop(),
        ),
        title: Text(rideState.isRecording ? 'LIVE MAP' : 'MAP'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blueAccent,
        onPressed: () {
          final target = markerPos ?? _currentLocation;
          if (target != null && _mapReady) {
            _mapController.move(target, 16.0);
          }
        },
        child: const Icon(Icons.my_location, color: Colors.white),
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: initialCenter,
          initialZoom: _currentLocation != null ? 16.0 : 5.0,
          onMapReady: () {
            setState(() { _mapReady = true; });
            if (_currentLocation != null) {
              _mapController.move(_currentLocation!, 16.0);
            }
          },
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
          if (markerPos != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: markerPos,
                  width: 30,
                  height: 30,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.3),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blueAccent, width: 2),
                    ),
                    child: const Center(
                      child: Icon(Icons.circle, color: Colors.blueAccent, size: 14),
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
