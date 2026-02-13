import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('IndoorPdrEngine drift growth', () {
    test('distance and accuracy grow monotonically over straight steps', () {
      final engine = IndoorPdrEngine(
        stepLengthMeters: 0.75,
        stepAccelThreshold: 4.0,
        minStepInterval: const Duration(milliseconds: 400),
        baseAccuracyMeters: 0.5,
        driftRatePerMeter: 0.02,
      );

      final t0 = DateTime.fromMillisecondsSinceEpoch(0);
      final estimates = <PositionEstimate>[];

      // 20 steps in a straight line along heading 0 (east).
      // We keep gz = 0 so heading stays at 0 rad.
      for (var i = 0; i < 20; i++) {
        final ts = t0.add(Duration(milliseconds: i * 500));

        final sample = ImuSample(
          timestamp: ts,
          ax: 0.0,
          ay: 5.0, // above threshold
          az: 0.0,
          gx: 0.0,
          gy: 0.0,
          gz: 0.0, // no turn
        );

        final est = engine.addImuSample(sample);
        if (est != null) {
          estimates.add(est);
        }
      }

      expect(estimates.length, 20);

      final last = estimates.last;
      final expectedDistance = 20 * 0.75; // 15 meters

      expect(last.x, closeTo(expectedDistance, 1e-6));
      expect(last.y!.abs(), lessThan(1e-6));

      // Accuracy should be non-decreasing and larger at the end.
      for (var i = 1; i < estimates.length; i++) {
        final prevAcc = estimates[i - 1].accuracyMeters!;
        final currAcc = estimates[i].accuracyMeters!;
        expect(currAcc + 1e-9, greaterThanOrEqualTo(prevAcc));
      }

      final firstAcc = estimates.first.accuracyMeters!;
      final lastAcc = estimates.last.accuracyMeters!;
      expect(lastAcc, greaterThan(firstAcc));

      // Heading should remain near zero.
      final headingRad = engine.debugHeadingRad;
      expect(headingRad.abs(), lessThan(1e-3));
      expect(engine.debugDistanceTraveled, closeTo(expectedDistance, 1e-6));
    });
  });
}
