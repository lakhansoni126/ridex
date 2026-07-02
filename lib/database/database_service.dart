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

  Future<void> saveRide(Ride ride) async {
    await _isar.writeTxn(() async {
      // Save ride first to get its ID
      await _isar.rides.put(ride);

      // Save each point individually and link it to the ride
      for (var point in ride.points) {
        point.ride.value = ride;
        await _isar.ridePoints.put(point);
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
