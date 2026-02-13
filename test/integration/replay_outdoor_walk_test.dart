import 'dart:math' as math;

import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('Replay outdoor walk', () {
    test('RMSE vs synthetic ground truth is ~0 and logging is consistent',
        () async {
      final logger = InMemoryPositioningLogger();

      final controller = PositioningController(
        pdrEngine: IndoorPdrEngine(),
        mapMatcher: OutdoorMapMatcher(),
        config: const FusionConfig(
          gpsGoodAccuracyThreshold: 10.0,
          gpsStaleDuration: Duration(seconds: 5),
          indoorStepCountThreshold: 3,
        ),
        logger: logger,
      );

      final replayer = PositioningReplayer(controller);

      final baseLat = 32.100000;
      final baseLon = 35.200000;
      const deltaLat = 1e-5; // ~1.11 m per step

      final t0 = DateTime.fromMillisecondsSinceEpoch(0);
      final events = <ReplayEvent>[];

      final truth = <_LatLon>[];

      for (var i = 0; i < 10; i++) {
        final lat = baseLat + i * deltaLat;
        final lon = baseLon;

        final sample = GpsSample(
          timestamp: t0.add(Duration(seconds: i)),
          latitude: lat,
          longitude: lon,
          horizontalAccuracy: 3.0,
          speed: 1.3,
          bearing: 90.0,
        );

        events.add(GpsReplayEvent(sample));
        truth.add(_LatLon(lat, lon));
      }

      final estimates = await replayer.replay(events);

      // We expect one fused estimate per GPS sample.
      expect(estimates.length, truth.length);

      // Logger should have logged all raw GPS samples and same number of estimates.
      expect(logger.gpsSamples.length, truth.length);
      expect(logger.estimates.length, truth.length);

      final rmse = _rmseHaversineMeters(estimates, truth);

      // With the current stub (no map-matching noise), RMSE is essentially zero.
      // We allow a tiny epsilon for floating-point operations.
      expect(rmse, lessThan(0.01)); // < 1 cm
    });
  });
}

class _LatLon {
  final double lat;
  final double lon;

  _LatLon(this.lat, this.lon);
}

double _rmseHaversineMeters(
  List<PositionEstimate> estimates,
  List<_LatLon> truth,
) {
  assert(estimates.length == truth.length);
  if (estimates.isEmpty) return 0.0;

  const earthRadius = 6371000.0; // meters
  var sumSq = 0.0;

  for (var i = 0; i < estimates.length; i++) {
    final est = estimates[i];
    final gt = truth[i];

    final lat1 = (est.latitude ?? gt.lat) * math.pi / 180.0;
    final lon1 = (est.longitude ?? gt.lon) * math.pi / 180.0;
    final lat2 = gt.lat * math.pi / 180.0;
    final lon2 = gt.lon * math.pi / 180.0;

    final dLat = lat2 - lat1;
    final dLon = lon2 - lon1;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final d = earthRadius * c;

    sumSq += d * d;
  }

  return math.sqrt(sumSq / estimates.length);
}
