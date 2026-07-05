import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

class DatabaseService {
  late Isar _isar;

  Isar get isar => _isar;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [BikeSchema, RideSchema, RidePointSchema],
      directory: dir.path,
    );
  }

  Future<void> saveRide(Ride ride, List<RidePoint> points) async {
    await _isar.writeTxn(() async {
      // Save ride first to get its ID
      await _isar.rides.put(ride);

      // Assign ride link to each point and save points
      for (var point in points) {
        point.ride.value = ride;
      }
      await _isar.ridePoints.putAll(points);
      
      // Save the links
      for (var point in points) {
        await point.ride.save();
      }
    });
  }

  Future<List<Ride>> getAllRides() async {
    return await _isar.rides.where().findAll();
  }

  Future<int> getRideCount() async {
    return await _isar.rides.count();
  }

  Future<double> getTotalDistance() async {
    final rides = await _isar.rides.where().findAll();
    double total = 0;
    for (final r in rides) {
      total += r.distance;
    }
    return total;
  }

  Future<double> getOverallTopSpeed() async {
    final rides = await _isar.rides.where().findAll();
    double top = 0;
    for (final r in rides) {
      if (r.topSpeed > top) top = r.topSpeed;
    }
    return top;
  }
}
