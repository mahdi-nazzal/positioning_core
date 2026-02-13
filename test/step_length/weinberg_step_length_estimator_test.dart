import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  test('Weinberg estimator calibrates towards known distance', () {
    final est = WeinbergStepLengthEstimator(k: 0.55, fallbackMeters: 0.7);

    // Simulate stable step intensity via repeated samples.
    final t0 = DateTime.utc(2025, 1, 1);
    var t = t0;

    // Create 20 "steps" with some accel magnitude variation.
    for (var i = 0; i < 50; i++) {
      final sample = ImuSample(
        timestamp: t,
        ax: 0.0,
        ay: 0.0,
        az: 9.81 + 1.8,
        gx: 0.0,
        gy: 0.0,
        gz: 0.0,
        mx: null,
        my: null,
        mz: null,
      );
      est.estimateMeters(
        step: StepEvent(timestamp: t, confidence: 1.0, cadenceHz: 2.0),
        sample: sample,
        dtSeconds: 0.02,
      );
      t = t.add(const Duration(milliseconds: 20));
    }

    // Calibrate: 20 steps == 14 meters => 0.7m per step.
    est.calibrateWithKnownDistance(distanceMeters: 14.0, steps: 20);

    final sample2 = ImuSample(
      timestamp: t,
      ax: 0.0,
      ay: 0.0,
      az: 9.81 + 1.8,
      gx: 0.0,
      gy: 0.0,
      gz: 0.0,
      mx: null,
      my: null,
      mz: null,
    );

    final out = est.estimateMeters(
      step: StepEvent(timestamp: t, confidence: 1.0, cadenceHz: 2.0),
      sample: sample2,
      dtSeconds: 0.02,
    );

    expect(out, closeTo(0.7, 0.25));
  });
}
