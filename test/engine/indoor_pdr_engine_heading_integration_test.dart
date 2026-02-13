import 'dart:math' as math;

import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('IndoorPdrEngine heading integration', () {
    test('integrates yaw rate into ~90 degree heading', () {
      // High accel threshold so no steps are emitted; we only test heading.
      final engine = IndoorPdrEngine(
        stepAccelThreshold: 1e6,
      );

      final t0 = DateTime.fromMillisecondsSinceEpoch(0);

      const targetHeadingRad = math.pi / 2; // 90 degrees
      const totalDurationSeconds = 1.0;
      const sampleCount = 100;

      final dtSeconds = totalDurationSeconds / sampleCount;
      final yawRate = targetHeadingRad / totalDurationSeconds; // rad/s

      for (var i = 0; i < sampleCount; i++) {
        final micros = ((i + 1) * dtSeconds * 1e6).round(); // from 10ms to ~1s
        final ts =
            t0.add(Duration(microseconds: micros)); // monotonically increasing

        final sample = ImuSample(
          timestamp: ts,
          ax: 0.0,
          ay: 0.0,
          az: 0.0,
          gx: 0.0,
          gy: 0.0,
          gz: yawRate, // constant yaw rate
        );

        engine.addImuSample(sample);
      }

      final headingRad = engine.debugHeadingRad;
      final headingDeg = headingRad * 180.0 / math.pi;

      // We allow a small numerical tolerance.
      expect(headingDeg, closeTo(90.0, 1.0));

      // Heading should be normalized into (-180, 180].
      expect(headingRad, inExclusiveRange(-math.pi, math.pi + 1e-9));
    });
  });
}
