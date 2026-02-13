import 'dart:async';

import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('PositioningController environment switching & fusion', () {
    test('starts unknown, becomes outdoor on good GPS, emits fused estimate',
        () async {
      final controller = PositioningController(
        pdrEngine: IndoorPdrEngine(),
        mapMatcher: OutdoorMapMatcher(),
        config: const FusionConfig(
          gpsGoodAccuracyThreshold: 10.0,
          gpsStaleDuration: Duration(seconds: 5),
          indoorStepCountThreshold: 2,
        ),
      );

      await controller.start();

      final events = <PositionEstimate>[];
      final sub = controller.position$.listen(events.add);

      final t0 = DateTime.fromMillisecondsSinceEpoch(0);

      controller.addGpsSample(
        GpsSample(
          timestamp: t0,
          latitude: 32.0,
          longitude: 35.0,
          horizontalAccuracy: 5.0, // good accuracy (< 10m)
          speed: 1.3,
          bearing: 45.0,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.debugEnvironmentMode, EnvironmentMode.outdoor);
      expect(events, isNotEmpty);

      final est = events.last;
      expect(est.source, PositionSource.fused);
      expect(est.isFused, isTrue);
      expect(est.isIndoor, isFalse);
      expect(est.latitude, closeTo(32.0, 1e-9));
      expect(est.longitude, closeTo(35.0, 1e-9));
      expect(est.headingDeg, closeTo(45.0, 1e-9));

      await controller.stop();
      await sub.cancel();
    });

    test('switches to indoor when GPS is stale and enough steps occur',
        () async {
      final pdrEngine = IndoorPdrEngine(
        stepLengthMeters: 1.0,
        stepAccelThreshold: 3.0,
        minStepInterval: const Duration(milliseconds: 300),
      );

      final controller = PositioningController(
        pdrEngine: pdrEngine,
        mapMatcher: OutdoorMapMatcher(),
        config: const FusionConfig(
          gpsGoodAccuracyThreshold: 10.0,
          gpsStaleDuration: Duration(seconds: 2),
          indoorStepCountThreshold: 2,
        ),
      );

      await controller.start();

      final events = <PositionEstimate>[];
      final sub = controller.position$.listen(events.add);

      final t0 = DateTime.fromMillisecondsSinceEpoch(0);

      // Good GPS fix at t = 0 → outdoor mode.
      controller.addGpsSample(
        GpsSample(
          timestamp: t0,
          latitude: 32.0,
          longitude: 35.0,
          horizontalAccuracy: 3.0,
        ),
      );

      // Three PDR steps, spaced by 3 seconds (so GPS becomes stale).
      DateTime current = t0;
      for (var i = 0; i < 3; i++) {
        current = current.add(const Duration(seconds: 3));

        final imu = ImuSample(
          timestamp: current,
          ax: 0.0,
          ay: 5.0, // above threshold → step
          az: 0.0,
          gx: 0.0,
          gy: 0.0,
          gz: 0.0,
        );

        controller.addImuSample(imu);
      }

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.debugEnvironmentMode, EnvironmentMode.indoor);

      // There should be at least one fused indoor estimate.
      final indoorEvents = events.where((e) => e.isIndoor).toList();
      expect(indoorEvents, isNotEmpty);

      final indoorEst = indoorEvents.last;
      expect(indoorEst.source, PositionSource.fused);
      expect(indoorEst.isFused, isTrue);
      expect(indoorEst.isIndoor, isTrue);
      expect(indoorEst.latitude, isNull);
      expect(indoorEst.longitude, isNull);
      expect(indoorEst.x, isNotNull);
      expect(indoorEst.y, isNotNull);

      await controller.stop();
      await sub.cancel();
    });
  });
}
