import 'dart:math' as math;

import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  test('Outdoor snapping projects to nearest edge with heading continuity', () {
    const baseLat = 32.2210;
    const baseLon = 35.2430;

    double metersToLat(double m) => m / 111320.0;
    double metersToLon(double m, double lat) =>
        m / (111320.0 * math.cos(lat * math.pi / 180.0));

    // Build a simple straight edge 60m north.
    final n0 = OutdoorGraphNode(id: 'A', latitude: baseLat, longitude: baseLon);
    final n1 = OutdoorGraphNode(
      id: 'B',
      latitude: baseLat + metersToLat(60),
      longitude: baseLon,
    );

    final g = OutdoorGraph(
      nodes: [n0, n1],
      edges: [
        OutdoorGraphEdge(
          id: 'E1',
          fromNodeId: 'A',
          toNodeId: 'B',
          lengthMeters: 60,
        ),
      ],
    );

    final matcher = OutdoorMapMatcher(graph: g);

    // Feed points 10m east of the edge; expect snapped lon ~ baseLon.
    DateTime t = DateTime(2026, 1, 1, 12, 0, 0);

    for (var i = 0; i < 20; i++) {
      final north = i * 2.0;
      final lat = baseLat + metersToLat(north);
      final lon = baseLon + metersToLon(10.0, baseLat); // 10m east

      final s = GpsSample(
        timestamp: t,
        latitude: lat,
        longitude: lon,
        horizontalAccuracy: 6.0,
        speed: 1.2,
        bearing: 0.0, // moving north
        altitude: null,
      );

      t = t.add(const Duration(milliseconds: 250));

      final est = matcher.addGpsSample(s);

      final outLon = est.longitude!;
      final dx =
          (outLon - baseLon) * (111320.0 * math.cos(baseLat * math.pi / 180.0));

      // snapped should be close to centerline (within ~2m)
      expect(dx.abs(), lessThan(2.0));
    }
  });
}
