import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('IndoorPdrEngine step detection', () {
    test('emits one estimate per synthetic high-acceleration step pulse', () {
      final engine = IndoorPdrEngine(
        stepLengthMeters: 0.8,
        stepAccelThreshold: 5.0,
        minStepInterval: const Duration(milliseconds: 400),
      );

      final t0 = DateTime.fromMillisecondsSinceEpoch(0);

      final estimates = <PositionEstimate>[];

      // 10 step pulses, each separated by 0.5 seconds (> 0.4 s min interval).
      for (var i = 0; i < 10; i++) {
        final ts = t0.add(Duration(milliseconds: i * 500));

        final sample = ImuSample(
          timestamp: ts,
          ax: 0.0,
          ay: 6.0, // above threshold → step candidate
          az: 0.0,
          gx: 0.0,
          gy: 0.0,
          gz: 0.0,
        );

        final est = engine.addImuSample(sample);
        if (est != null) {
          estimates.add(est);
        }
      }

      expect(estimates.length, 10);

      final last = estimates.last;
      expect(last.x, closeTo(0.8 * 10, 1e-6));
      expect(last.y!.abs(), lessThan(1e-6));
      expect(last.isIndoor, isTrue);
      expect(last.source, PositionSource.pdr);
      expect(last.accuracyMeters, isNotNull);
    });
  });
}
