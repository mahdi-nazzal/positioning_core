import 'dart:math' as math;

import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('OutdoorMapMatcher path continuity', () {
    test('sequential GPS samples produce a continuous path without big jumps',
        () {
      final matcher = OutdoorMapMatcher();

      const baseLat = 32.0;
      const baseLon = 35.0;
      const deltaLat = 1e-5; // ~1.11 m per step
      const deltaLon = 0.0;

      final t0 = DateTime.fromMillisecondsSinceEpoch(0);

      final estimates = <PositionEstimate>[];

      for (var i = 0; i < 20; i++) {
        final lat = baseLat + i * deltaLat;
        final lon = baseLon + i * deltaLon;

        final sample = GpsSample(
          timestamp: t0.add(Duration(seconds: i)),
          latitude: lat,
          longitude: lon,
          horizontalAccuracy: 3.0,
        );

        final est = matcher.addGpsSample(sample);
        estimates.add(est);
      }

      expect(estimates.length, 20);

      // Check that the step-to-step distance is > 0 and not exploding.
      // Use a simple local approximation in meters.
      const earthRadius = 6371000.0;
      for (var i = 1; i < estimates.length; i++) {
        final prev = estimates[i - 1];
        final curr = estimates[i];

        final lat1 = (prev.latitude ?? baseLat) * math.pi / 180.0;
        final lon1 = (prev.longitude ?? baseLon) * math.pi / 180.0;
        final lat2 = (curr.latitude ?? baseLat) * math.pi / 180.0;
        final lon2 = (curr.longitude ?? baseLon) * math.pi / 180.0;

        final dLat = lat2 - lat1;
        final dLon = lon2 - lon1;

        final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
            math.cos(lat1) *
                math.cos(lat2) *
                math.sin(dLon / 2) *
                math.sin(dLon / 2);
        final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
        final distance = earthRadius * c;

        // For our synthetic path, we expect ~1 meter between samples.
        expect(distance, greaterThan(0.1));
        expect(distance, lessThan(10.0));
      }
    });
  });
}
