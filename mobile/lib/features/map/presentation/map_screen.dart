import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../database/models.dart';
import '../../../services/location_service.dart';
import '../../../shared/ui/ui.dart';
import '../../ride/domain/ride_engine.dart';
import '../domain/polyline_engine.dart';

/// Full-screen map: your position, and the live route while recording.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _map = MapController();
  StreamSubscription<Position>? _sub;
  LatLng? _me;
  double? _heading;
  bool _ready = false;
  bool _follow = true;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final service = LocationService();
    if (!await service.requestPermissions()) {
      if (mounted) {
        setState(() => _problem = 'Location access is off. Allow it to see where you are.');
      }
      return;
    }
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) _update(last, initial: true);
    final fresh = await service.getCurrentPosition();
    if (fresh != null) _update(fresh, initial: last == null);
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_update, onError: (_) {});
  }

  void _update(Position p, {bool initial = false}) {
    if (!mounted) return;
    final loc = LatLng(p.latitude, p.longitude);
    setState(() {
      _me = loc;
      _heading = p.heading.isNaN || p.heading < 0 ? null : p.heading;
    });
    if (_ready && (_follow || initial)) {
      _map.move(loc, initial ? 16 : _map.camera.zoom);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final ride = ref.watch(rideEngineProvider);
    final route = [
      for (final p in ride.routePoints)
        RidePoint()
          ..latitude = p.latitude
          ..longitude = p.longitude
          ..speed = p.speed * 3.6,
    ];
    final polylines = PolylineEngine.generateHeatmap(route);
    final marker = ride.isRecording && ride.lastPosition != null
        ? LatLng(ride.lastPosition!.latitude, ride.lastPosition!.longitude)
        : _me;

    return CupertinoPageScaffold(
      backgroundColor: rx.background,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _me ?? const LatLng(20.5937, 78.9629),
                initialZoom: _me != null ? 16 : 4,
                onMapReady: () {
                  _ready = true;
                  if (_me != null) _map.move(_me!, 16);
                },
                onPositionChanged: (_, hasGesture) {
                  if (hasGesture && _follow) setState(() => _follow = false);
                },
              ),
              children: [
                const RxTileLayer(),
                if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
                if (marker != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: marker,
                      width: 26,
                      height: 26,
                      child: _UserDot(heading: _heading),
                    ),
                  ]),
                const RxMapAttribution(),
              ],
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(RxSpace.s + 4),
                child: Column(
                  children: [
                    Row(
                      children: [
                        RxMapButton(
                          icon: CupertinoIcons.xmark,
                          semanticLabel: 'Close map',
                          onPressed: () => context.pop(),
                        ),
                        const Spacer(),
                        if (ride.isRecording)
                          RxPill(
                            label:
                                '${ride.currentSpeed.toStringAsFixed(0)} km/h · ${ride.distance.toStringAsFixed(1)} km',
                            color: rx.destructive,
                            icon: CupertinoIcons.circle_fill,
                            filled: true,
                          ),
                        const Spacer(),
                        RxMapButton(
                          icon: _follow
                              ? CupertinoIcons.location_fill
                              : CupertinoIcons.location,
                          semanticLabel: 'Centre on my location',
                          active: _follow,
                          onPressed: () {
                            setState(() => _follow = true);
                            if (marker != null) _map.move(marker, 16);
                          },
                        ),
                      ],
                    ),
                    if (_problem != null) ...[
                      const SizedBox(height: RxSpace.m),
                      RxCard(
                        onTap: () => Geolocator.openAppSettings(),
                        child: Row(
                          children: [
                            Icon(CupertinoIcons.location_slash_fill,
                                color: rx.warning),
                            const SizedBox(width: RxSpace.s),
                            Expanded(
                                child: Text(_problem!, style: rx.subheadline)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserDot extends StatelessWidget {
  const _UserDot({this.heading});

  final double? heading;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Container(
      decoration: BoxDecoration(
        color: rx.info,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFFFFFFF), width: 3),
        boxShadow: [
          BoxShadow(color: rx.info.withOpacity(0.35), blurRadius: 12, spreadRadius: 4),
        ],
      ),
    );
  }
}
