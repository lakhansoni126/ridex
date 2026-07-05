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
    if (points.length < 2) return [];

    final List<LatLng> latLngs = [];
    final List<Color> colors = [];

    for (var p in points) {
      latLngs.add(LatLng(p.latitude, p.longitude));
      colors.add(_getColorForSpeed(p.speed));
    }

    return [
      Polyline(
        points: latLngs,
        strokeWidth: 5,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
        gradientColors: colors,
      )
    ];
  }
}
