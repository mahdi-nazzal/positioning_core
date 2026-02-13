import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('OutdoorMapMatcher basic', () {
    test('returns estimate for GPS sample and preserves coordinates', () {
      final graph = const OutdoorGraph(
        nodes: <OutdoorGraphNode>[],
        edges: <OutdoorGraphEdge>[],
      );

      final matcher = OutdoorMapMatcher(graph: graph);

      final t0 = DateTime.fromMillisecondsSinceEpoch(0);
      final sample = GpsSample(
        timestamp: t0,
        latitude: 32.1000001,
        longitude: 35.2000002,
        altitude: 500.0,
        horizontalAccuracy: 3.0,
      );

      final est = matcher.addGpsSample(sample);

      expect(est.latitude, closeTo(sample.latitude, 1e-9));
      expect(est.longitude, closeTo(sample.longitude, 1e-9));
      expect(est.altitude, sample.altitude);
      expect(est.source, PositionSource.gps);
      expect(est.isIndoor, isFalse);
      expect(est.isFused, isFalse);
      expect(est.accuracyMeters, sample.horizontalAccuracy);
    });
  });
}
