import 'dart:math' as math;

import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('Replay indoor corridor walk', () {
    test('PDR fused indoor path has small RMSE vs synthetic ground truth',
        () async {
      const stepLength = 0.8; // meters

      final pdrEngine = IndoorPdrEngine(
        stepLengthMeters: stepLength,
        stepAccelThreshold: 3.0,
        minStepInterval: const Duration(milliseconds: 300),
        baseAccuracyMeters: 0.5,
        driftRatePerMeter: 0.02,
      );

      final logger = InMemoryPositioningLogger();

      final controller = PositioningController(
        pdrEngine: pdrEngine,
        mapMatcher: OutdoorMapMatcher(),
        // indoorStepCountThreshold=1 so the first PDR step switches us to indoor
        config: const FusionConfig(
          gpsGoodAccuracyThreshold: 10.0,
          gpsStaleDuration: Duration(seconds: 2),
          indoorStepCountThreshold: 1,
        ),
        logger: logger,
      );

      final replayer = PositioningReplayer(controller);

      final t0 = DateTime.fromMillisecondsSinceEpoch(0);
      final events = <ReplayEvent>[];
      final truthX = <double>[];

      const stepCount = 20;

      for (var i = 0; i < stepCount; i++) {
        final ts = t0.add(Duration(milliseconds: i * 500));

        final imu = ImuSample(
          timestamp: ts,
          ax: 0.0,
          ay: 5.0, // above threshold → step
          az: 0.0,
          gx: 0.0,
          gy: 0.0,
          gz: 0.0, // no rotation → straight corridor
        );

        events.add(ImuReplayEvent(imu));
        truthX.add((i + 1) * stepLength); // after Nth step, x = N * stepLength
      }

      final estimates = await replayer.replay(events);

      // We expect one fused estimate per step once indoor mode is active.
      // With indoorStepCountThreshold=1, it should be stepCount.
      expect(estimates.length, stepCount);

      // All fused estimates should be indoor.
      for (final e in estimates) {
        expect(e.isIndoor, isTrue);
        expect(e.source, PositionSource.fused);
        expect(e.latitude, isNull);
        expect(e.longitude, isNull);
        expect(e.x, isNotNull);
      }

      expect(logger.imuSamples.length, stepCount);
      expect(logger.estimates.length, stepCount);

      final xs = estimates.map((e) => e.x ?? 0.0).toList();
      final rmse = _rmse1D(xs, truthX);

      // PDR baseline in this synthetic scenario should be essentially perfect.
      expect(rmse, lessThan(1e-6));
    });
  });
}

double _rmse1D(List<double> estimates, List<double> truth) {
  assert(estimates.length == truth.length);
  if (estimates.isEmpty) return 0.0;

  var sumSq = 0.0;
  for (var i = 0; i < estimates.length; i++) {
    final diff = estimates[i] - truth[i];
    sumSq += diff * diff;
  }
  return math.sqrt(sumSq / estimates.length);
}
