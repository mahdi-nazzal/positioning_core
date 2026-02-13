import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  test('Graph PF: deterministic outputs for same seed + same inputs', () {
    final edges = <CorridorEdge>[
      const CorridorEdge(id: 'E', ax: 0, ay: 0, bx: 40, by: 0),
    ];

    final cfg =
        GraphParticleFilterConfig.forMode(GraphParticleFilterMode.balanced);

    final a =
        GraphParticleFilterIndoorMatcher(edges: edges, config: cfg, seed: 123);
    final b =
        GraphParticleFilterIndoorMatcher(edges: edges, config: cfg, seed: 123);

    for (int i = 0; i < 20; i++) {
      final raw = PositionEstimate(
        timestamp: DateTime.fromMillisecondsSinceEpoch(i * 300),
        source: PositionSource.fused,
        x: i * 0.7,
        y: 0.3, // slight offset
        isIndoor: true,
        headingDeg: 0.0,
        isFused: true,
      );

      final ea = a.match(raw).estimate;
      final eb = b.match(raw).estimate;

      expect(ea.x, equals(eb.x));
      expect(ea.y, equals(eb.y));
    }
  });
}
