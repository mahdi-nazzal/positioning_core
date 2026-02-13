import 'dart:math' as math;

import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  test('PF: keeps track near a straight corridor and reduces lateral noise',
      () {
    final edges = <CorridorEdge>[
      const CorridorEdge(id: 'E1', ax: 0, ay: 0, bx: 50, by: 0),
    ];

    final pf = ParticleFilterIndoorMatcher(
      edges: edges,
      config: ParticleFilterConfig.forMode(ParticleFilterMode.balanced),
      seed: 7,
    );

    final r = math.Random(1);

    double x = 0.0;
    double y = 0.0;

    double lastOutY = 999;

    for (int i = 0; i < 40; i++) {
      x += 0.7;
      // raw noisy PDR (simulate lateral drift)
      y = (r.nextDouble() - 0.5) * 1.2; // [-0.6..0.6]

      final raw = PositionEstimate(
        timestamp: DateTime.fromMillisecondsSinceEpoch(i * 300),
        source: PositionSource.fused,
        x: x,
        y: y,
        isIndoor: true,
        headingDeg: 0.0,
        isFused: true,
      );

      final res = pf.match(raw);
      final outY = res.estimate.y!;

      // After a few steps, PF should stay close to corridor y=0
      if (i > 10) {
        expect(outY.abs(), lessThan(0.30));
      }

      lastOutY = outY;
    }

    expect(lastOutY.abs(), lessThan(0.30));
  });

  test('PF: intersection handling avoids large jumps (T junction)', () {
    final edges = <CorridorEdge>[
      const CorridorEdge(id: 'H', ax: 0, ay: 0, bx: 20, by: 0), // horizontal
      const CorridorEdge(id: 'V', ax: 12, ay: 0, bx: 12, by: 10), // vertical up
    ];

    final pf = ParticleFilterIndoorMatcher(
      edges: edges,
      config: ParticleFilterConfig.forMode(ParticleFilterMode.balanced),
      seed: 9,
    );

    final outputs = <PositionEstimate>[];

    // move along H
    for (int i = 0; i < 20; i++) {
      final raw = PositionEstimate(
        timestamp: DateTime.fromMillisecondsSinceEpoch(i * 300),
        source: PositionSource.fused,
        x: i * 0.7,
        y: 0.25, // slight offset
        isIndoor: true,
        headingDeg: 0.0,
        isFused: true,
      );
      outputs.add(pf.match(raw).estimate);
    }

    // turn up on V near x=12
    for (int i = 20; i < 35; i++) {
      final t = i - 20;
      final raw = PositionEstimate(
        timestamp: DateTime.fromMillisecondsSinceEpoch(i * 300),
        source: PositionSource.fused,
        x: 12.0,
        y: t * 0.7,
        isIndoor: true,
        headingDeg: 90.0,
        isFused: true,
      );
      outputs.add(pf.match(raw).estimate);
    }

    // Check no “teleport” jumps
    for (int i = 1; i < outputs.length; i++) {
      final a = outputs[i - 1];
      final b = outputs[i];
      final dx = (b.x! - a.x!);
      final dy = (b.y! - a.y!);
      final dist = math.sqrt(dx * dx + dy * dy);
      expect(dist, lessThan(2.0));
    }
  });
}
