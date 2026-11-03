import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../database/models.dart';
import '../../../shared/ui/ui.dart';
import '../../history/presentation/ride_detail_screen.dart';
import '../../map/domain/polyline_engine.dart';

/// Animated playback of a recorded drive with a speed profile scrubber.
class RideReplayScreen extends ConsumerWidget {
  const RideReplayScreen({super.key, required this.rideId});

  final int rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(rideDetailProvider(rideId)).when(
          loading: () => const RxPage(
            title: 'Replay',
            child: Center(child: CupertinoActivityIndicator()),
          ),
          error: (e, _) => RxPage(
            title: 'Replay',
            child: Center(child: RxErrorState(error: e)),
          ),
          data: (ride) {
            final points = (ride?.points.toList() ?? <RidePoint>[])
              ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
            if (points.length < 2) {
              return const RxPage(
                title: 'Replay',
                child: Center(
                  child: RxEmptyState(
                    icon: CupertinoIcons.play_rectangle,
                    title: 'Nothing to Replay',
                    message: 'This drive has too few GPS points.',
                  ),
                ),
              );
            }
            return _ReplayView(points: points);
          },
        );
  }
}

class _ReplayView extends StatefulWidget {
  const _ReplayView({required this.points});

  final List<RidePoint> points;

  @override
  State<_ReplayView> createState() => _ReplayViewState();
}

class _ReplayViewState extends State<_ReplayView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final _map = MapController();
  bool _follow = true;
  int _speedIndex = 1;
  static const _speeds = [1, 2, 4, 8];

  late final List<LatLng> _latLngs = [
    for (final p in widget.points) LatLng(p.latitude, p.longitude)
  ];
  late final int _totalSeconds = math.max(
    1,
    widget.points.last.timestamp
        .difference(widget.points.first.timestamp)
        .inSeconds,
  );

  /// Base playback compresses the drive to at most ~60 s at 1×.
  Duration get _baseDuration =>
      Duration(seconds: math.min(60, math.max(10, _totalSeconds ~/ 10)));

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _baseDuration)
      ..addListener(_onTick)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) setState(() {});
      });
  }

  @override
  void dispose() {
    _c.dispose();
    _map.dispose();
    super.dispose();
  }

  int get _index =>
      (_c.value * (widget.points.length - 1)).round().clamp(0, widget.points.length - 1);

  void _onTick() {
    if (_follow) {
      try {
        _map.move(_latLngs[_index], _map.camera.zoom);
      } catch (_) {}
    }
    setState(() {});
  }

  void _togglePlay() {
    HapticFeedback.selectionClick();
    if (_c.isAnimating) {
      _c.stop();
    } else {
      if (_c.value >= 1) _c.value = 0;
      _c.duration = _baseDuration ~/ _speeds[_speedIndex];
      _c.forward();
    }
    setState(() {});
  }

  void _cycleSpeed() {
    HapticFeedback.selectionClick();
    setState(() => _speedIndex = (_speedIndex + 1) % _speeds.length);
    if (_c.isAnimating) {
      _c.duration = _baseDuration ~/ _speeds[_speedIndex];
      _c.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final p = widget.points[_index];
    final elapsed =
        p.timestamp.difference(widget.points.first.timestamp).inSeconds;
    final travelled = _latLngs.take(_index + 1).toList();
    final spots = <FlSpot>[
      for (var i = 0; i < widget.points.length; i++)
        FlSpot(i.toDouble(), widget.points[i].speed),
    ];
    final maxSpeed = spots.map((s) => s.y).fold<double>(10, math.max);

    return CupertinoPageScaffold(
      backgroundColor: rx.background,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCameraFit: CameraFit.coordinates(
                  coordinates: _latLngs,
                  padding: const EdgeInsets.fromLTRB(40, 120, 40, 300),
                  maxZoom: 17,
                ),
                onPositionChanged: (_, hasGesture) {
                  if (hasGesture && _follow) setState(() => _follow = false);
                },
              ),
              children: [
                const RxTileLayer(),
                PolylineLayer(polylines: [
                  Polyline(
                    points: _latLngs,
                    strokeWidth: 4,
                    color: rx.gray.withOpacity(0.5),
                  ),
                  if (travelled.length >= 2)
                    Polyline(
                      points: travelled,
                      strokeWidth: 5,
                      gradientColors: [
                        for (var i = 0; i <= _index; i++)
                          PolylineEngine.colorForSpeed(widget.points[i].speed),
                      ],
                    ),
                ]),
                MarkerLayer(markers: [
                  Marker(
                    point: _latLngs[_index],
                    width: 34,
                    height: 34,
                    child: Transform.rotate(
                      angle: (p.heading.isNaN ? 0 : p.heading) * math.pi / 180,
                      child: Container(
                        decoration: BoxDecoration(
                          color: rx.accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFFFFFFFF), width: 3),
                          boxShadow: const [
                            BoxShadow(color: Color(0x55000000), blurRadius: 8),
                          ],
                        ),
                        child: const Icon(CupertinoIcons.location_north_fill,
                            size: 14, color: Color(0xFFFFFFFF)),
                      ),
                    ),
                  ),
                ]),
                const RxMapAttribution(),
              ],
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(RxSpace.s + 4),
                child: Row(
                  children: [
                    RxMapButton(
                      icon: CupertinoIcons.xmark,
                      semanticLabel: 'Close replay',
                      onPressed: () => context.pop(),
                    ),
                    const Spacer(),
                    RxMapButton(
                      icon: CupertinoIcons.location_fill,
                      semanticLabel: 'Follow car',
                      active: _follow,
                      onPressed: () => setState(() => _follow = true),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: MediaQuery.paddingOf(context).bottom + 12,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                decoration: BoxDecoration(
                  color: rx.cardElevated,
                  borderRadius: BorderRadius.circular(RxSpace.radiusLarge + 4),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 24,
                        offset: Offset(0, 8)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: RxMetric(
                            label: 'Speed',
                            value: p.speed.toStringAsFixed(0),
                            unit: 'km/h',
                            valueSize: 26,
                          ),
                        ),
                        Expanded(
                          child: RxMetric(
                            label: 'Elapsed',
                            value: formatDuration(elapsed),
                            valueSize: 26,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: RxSpace.m),
                    SizedBox(
                      height: 64,
                      child: LineChart(
                        LineChartData(
                          minY: 0,
                          maxY: maxSpeed * 1.1,
                          gridData: const FlGridData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineTouchData: const LineTouchData(enabled: false),
                          extraLinesData: ExtraLinesData(verticalLines: [
                            VerticalLine(
                              x: _index.toDouble(),
                              color: rx.label,
                              strokeWidth: 1.5,
                            ),
                          ]),
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              isCurved: true,
                              preventCurveOverShooting: true,
                              color: rx.accent,
                              barWidth: 2,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: rx.accent.withOpacity(0.15),
                              ),
                            ),
                          ],
                        ),
                        duration: Duration.zero,
                      ),
                    ),
                    CupertinoSlider(
                      value: _c.value,
                      activeColor: rx.accent,
                      onChangeStart: (_) => _c.stop(),
                      onChanged: (v) => _c.value = v,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 44,
                          onPressed: _cycleSpeed,
                          child: Text('${_speeds[_speedIndex]}×',
                              style: rx.headline.copyWith(color: rx.accent)),
                        ),
                        Semantics(
                          button: true,
                          label: _c.isAnimating ? 'Pause' : 'Play',
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            minSize: 56,
                            onPressed: _togglePlay,
                            child: Icon(
                              _c.isAnimating
                                  ? CupertinoIcons.pause_circle_fill
                                  : CupertinoIcons.play_circle_fill,
                              size: 56,
                              color: rx.accent,
                            ),
                          ),
                        ),
                        Text(formatDuration(_totalSeconds), style: rx.footnote),
                      ],
                    ),
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
