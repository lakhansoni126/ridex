import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../database/models.dart';

/// Speed bands shared by the route colouring and its legend.
class SpeedBand {
  const SpeedBand(this.label, this.maxKmh, this.color);

  final String label;
  final double maxKmh;
  final Color color;
}

class PolylineEngine {
  static const bands = [
    SpeedBand('< 40', 40, Color(0xFF30D158)),
    SpeedBand('40–80', 80, Color(0xFFFFD60A)),
    SpeedBand('80–120', 120, Color(0xFFFF9F0A)),
    SpeedBand('120+', double.infinity, Color(0xFFFF453A)),
  ];

  static Color colorForSpeed(double speedKmh) {
    for (final b in bands) {
      if (speedKmh < b.maxKmh) return b.color;
    }
    return bands.last.color;
  }

  /// One gradient polyline coloured by speed at each vertex.
  static List<Polyline> generateHeatmap(List<RidePoint> points) {
    if (points.length < 2) return [];
    return [
      Polyline(
        points: [for (final p in points) LatLng(p.latitude, p.longitude)],
        strokeWidth: 5,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
        gradientColors: [for (final p in points) colorForSpeed(p.speed)],
        borderStrokeWidth: 1.5,
        borderColor: const Color(0x66000000),
      ),
    ];
  }

  /// Bounds that fit every point, or null when there are none.
  static LatLngBounds? bounds(List<RidePoint> points) {
    if (points.isEmpty) return null;
    return LatLngBounds.fromPoints(
        [for (final p in points) LatLng(p.latitude, p.longitude)]);
  }
}
