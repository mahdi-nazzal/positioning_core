import 'dart:math' as math;

import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  test('StepDetector v2: detects periodic peaks and estimates cadence', () {
    final d = FilteredPeakStepDetectorV2(
      signalSource: StepSignalSource.magnitudeNoGravity,
      minPeak: 0.35,
      minStepInterval: const Duration(milliseconds: 250),
    );

    final t0 = DateTime.utc(2025, 1, 1, 0, 0, 0);
    var t = t0;

    // 10 seconds @ 50Hz; inject a pulse every 0.5s (2 Hz).
    final dt = 0.02;
    final total = (10.0 / dt).toInt();

    final events = <StepEvent>[];
    for (var i = 0; i < total; i++) {
      final timeSec = i * dt;

      // Pulse: positive bumps at 2 Hz.
      final bump = math.max(0.0, math.sin(2 * math.pi * 2.0 * timeSec));

      final s = ImuSample(
        timestamp: t,
        ax: 0.0,
        ay: 0.0,
        az: 9.81 + 2.2 * bump,
        gx: 0.0,
        gy: 0.0,
        gz: 0.0,
        mx: 30.0,
        my: 0.0,
        mz: 0.0,
      );

      final e = d.update(s, dt);
      if (e != null) events.add(e);

      t = t.add(const Duration(milliseconds: 20));
    }

    // Conservative expectation: detector should find many steps, but gating may miss some.
    expect(events.length, greaterThanOrEqualTo(8));

    final cadenceSamples = events
        .map((e) => e.cadenceHz)
        .whereType<double>()
        .where((hz) => hz > 0)
        .toList();

    expect(cadenceSamples.isNotEmpty, isTrue);

    final avg = cadenceSamples.reduce((a, b) => a + b) / cadenceSamples.length;
    expect(avg, closeTo(2.0, 0.8));
  });
}
