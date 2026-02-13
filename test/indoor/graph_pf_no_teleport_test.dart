import 'dart:math' as math;

import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  test('Graph PF: T-junction turn without teleport jumps', () {
    final edges = <CorridorEdge>[
      const CorridorEdge(id: 'H', ax: 0, ay: 0, bx: 20, by: 0),
      const CorridorEdge(id: 'V', ax: 12, ay: 0, bx: 12, by: 10),
    ];

    final matcher = GraphParticleFilterIndoorMatcher(
      edges: edges,
      config:
          GraphParticleFilterConfig.forMode(GraphParticleFilterMode.balanced),
      seed: 9,
    );

    final outputs = <PositionEstimate>[];

    // Along H
    for (int i = 0; i < 18; i++) {
      final raw = PositionEstimate(
        timestamp: DateTime.fromMillisecondsSinceEpoch(i * 300),
        source: PositionSource.fused,
        x: i * 0.7,
        y: 0.25,
        isIndoor: true,
        headingDeg: 0.0,
        isFused: true,
      );
      outputs.add(matcher.match(raw).estimate);
    }

    // Turn up on V
    for (int i = 18; i < 30; i++) {
      final t = i - 18;
      final raw = PositionEstimate(
        timestamp: DateTime.fromMillisecondsSinceEpoch(i * 300),
        source: PositionSource.fused,
        x: 12.0,
        y: t * 0.7,
        isIndoor: true,
        headingDeg: 90.0,
        isFused: true,
      );
      outputs.add(matcher.match(raw).estimate);
    }

    // No teleport: consecutive outputs shouldn't jump wildly.
    for (int i = 1; i < outputs.length; i++) {
      final a = outputs[i - 1];
      final b = outputs[i];
      final dx = b.x! - a.x!;
      final dy = b.y! - a.y!;
      final dist = math.sqrt(dx * dx + dy * dy);
      expect(dist, lessThan(2.2));
    }
  });
}
