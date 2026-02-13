import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:positioning_core/positioning_core.dart';

class LocationFeed {
  final StreamController<GpsSample> _controller =
  StreamController<GpsSample>.broadcast();

  Stream<GpsSample> get samples => _controller.stream;

  StreamSubscription<Position>? _sub;

  Future<void> start() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw Exception('Location services disabled');
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }

    _sub?.cancel();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
          (p) {
        final ts = p.timestamp ?? DateTime.now();
        _controller.add(
          GpsSample(
            timestamp: ts,
            latitude: p.latitude,
            longitude: p.longitude,
            altitude: p.altitude,
            horizontalAccuracy: p.accuracy,
            verticalAccuracy: p.altitudeAccuracy,
            speed: p.speed,
            bearing: p.heading,
          ),
        );
      },
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
