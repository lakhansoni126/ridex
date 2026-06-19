import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/models.dart';

class ExportService {
  static Future<void> exportRideToJson(Ride ride) async {
    final Map<String, dynamic> rideData = {
      'startTime': ride.startTime.toIso8601String(),
      'endTime': ride.endTime?.toIso8601String(),
      'distance': ride.distance,
      'durationSeconds': ride.durationSeconds,
      'topSpeed': ride.topSpeed,
      'points': ride.points.map((p) => {
        'latitude': p.latitude,
        'longitude': p.longitude,
        'speed': p.speed,
        'timestamp': p.timestamp.toIso8601String(),
      }).toList(),
    };

    final jsonString = jsonEncode(rideData);
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/ride_${ride.id}.json');
    await file.writeAsString(jsonString);

    await Share.shareXFiles([XFile(file.path)], text: 'My Motorcycle Ride Data');
  }
}
