import 'dart:math' as math;

import 'package:positioning_core/positioning_core.dart' show GpsSample;
import 'package:positioning_core/src/engine/outdoor_map_matcher.dart';
import 'package:test/test.dart';

void main() {
  test('Outdoor smoothing reduces standstill jitter when accuracy is poor', () {
    // ✅ PR-10: smoothing is opt-in (keeps legacy tests stable by default)
    final matcher = OutdoorMapMatcher(
      config: const OutdoorMapMatcherConfig(enableSmoothing: true),
    );

    const baseLat = 32.2210;
    const baseLon = 35.2430;

    // Deterministic jitter pattern (+/- 5m).
    final offsetsMeters = <List<double>>[
      [5, 0],
      [-5, 0],
      [0, 5],
      [0, -5],
      [4, 3],
      [-4, -3],
      [3, -4],
      [-3, 4],
    ];

    double metersToLat(double m) => m / 111320.0;
    double metersToLon(double m, double lat) =>
        m / (111320.0 * math.cos(lat * math.pi / 180.0));

    double rawAvg = 0;
    double outAvg = 0;

    DateTime t = DateTime(2026, 1, 1, 12, 0, 0);

    for (var i = 0; i < 80; i++) {
      final off = offsetsMeters[i % offsetsMeters.length];
      final lat = baseLat + metersToLat(off[1]);
      final lon = baseLon + metersToLon(off[0], baseLat);

      final s = GpsSample(
        timestamp: t,
        latitude: lat,
        longitude: lon,
        horizontalAccuracy: 20.0, // enables smoothing path
        speed: 0.0, // standstill
        bearing: null,
        altitude: null,
      );
      t = t.add(const Duration(milliseconds: 200));

      final est = matcher.addGpsSample(s);

      final dxRaw = off[0];
      final dyRaw = off[1];
      rawAvg += math.sqrt(dxRaw * dxRaw + dyRaw * dyRaw);

      // Approx output offset in meters (compare to base using same approx)
      final outLat = est.latitude!;
      final outLon = est.longitude!;
      final dy = (outLat - baseLat) * 111320.0;
      final dx =
          (outLon - baseLon) * (111320.0 * math.cos(baseLat * math.pi / 180.0));
      outAvg += math.sqrt(dx * dx + dy * dy);
    }

    rawAvg /= 80.0;
    outAvg /= 80.0;

    // Expect meaningful reduction (not perfect, but clearly less than raw).
    expect(outAvg, lessThan(rawAvg * 0.65));
  });
}
