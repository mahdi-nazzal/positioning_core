import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('PositioningController indoor/outdoor mode switching', () {
    test(
        'starts unknown, becomes outdoor on good GPS, then indoor after stale GPS + steps',
        () async {
      final pdrEngine = IndoorPdrEngine(
        stepLengthMeters: 0.8,
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

      // Initial state.
      expect(controller.debugEnvironmentMode, EnvironmentMode.unknown);

      // Good GPS at t=0 → outdoor.
      controller.addGpsSample(
        GpsSample(
          timestamp: t0,
          latitude: 32.0,
          longitude: 35.0,
          horizontalAccuracy: 3.0,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(controller.debugEnvironmentMode, EnvironmentMode.outdoor);

      // Now feed IMU steps with timestamps far enough to make GPS stale.
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

      // We should have at least one indoor fused estimate.
      final indoorEvents = events.where((e) => e.isIndoor).toList();
      expect(indoorEvents, isNotEmpty);

      final lastIndoor = indoorEvents.last;
      expect(lastIndoor.source, PositionSource.fused);
      expect(lastIndoor.latitude, isNull);
      expect(lastIndoor.longitude, isNull);
      expect(lastIndoor.x, isNotNull);
      expect(lastIndoor.y, isNotNull);

      await controller.stop();
      await sub.cancel();
    });
  });
}
