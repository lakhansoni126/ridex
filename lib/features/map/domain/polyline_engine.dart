import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../database/models.dart';

class PolylineEngine {
  static Color _getColorForSpeed(double speedKmh) {
    if (speedKmh < 40) return Colors.greenAccent;
    if (speedKmh < 80) return Colors.yellowAccent;
    if (speedKmh < 120) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  static List<Polyline> generateHeatmap(List<RidePoint> points) {
    final List<Polyline> polylines = [];
    if (points.length < 2) return polylines;

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];

      final color = _getColorForSpeed(p1.speed);
      
      polylines.add(
        Polyline(
          points: [
            LatLng(p1.latitude, p1.longitude),
            LatLng(p2.latitude, p2.longitude),
          ],
          color: color,
          strokeWidth: 5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      );
    }
    return polylines;
  }
}
