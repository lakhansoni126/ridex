import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

class DatabaseService {
  late Isar _isar;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [BikeSchema, RideSchema, RidePointSchema],
      directory: dir.path,
    );
  }

  Future<void> saveRide(Ride ride) async {
    await _isar.writeTxn(() async {
      await _isar.rides.put(ride);
      for (var point in ride.points) {
        await _isar.ridePoints.put(point);
        point.ride.value = ride;
        await point.ride.save();
      }
    });
  }

  Future<List<Ride>> getAllRides() async {
    return await _isar.rides.where().findAll();
  }
}
