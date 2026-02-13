import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  test('StepDetector v2: stationary does not produce steps', () {
    final d = FilteredPeakStepDetectorV2(
      signalSource: StepSignalSource.magnitudeNoGravity,
      minPeak: 0.6,
      minStepInterval: const Duration(milliseconds: 300),
    );

    final t0 = DateTime.utc(2025, 1, 1, 0, 0, 0);
    var t = t0;

    var steps = 0;
    for (var i = 0; i < 500; i++) {
      final s = ImuSample(
        timestamp: t,
        ax: 0.0,
        ay: 0.0,
        az: 9.81,
        gx: 0.0,
        gy: 0.0,
        gz: 0.0,
        mx: 30.0,
        my: 0.0,
        mz: 0.0,
      );
      final e = d.update(s, 0.02);
      if (e != null) steps++;
      t = t.add(const Duration(milliseconds: 20));
    }

    expect(steps, 0);
  });
}
