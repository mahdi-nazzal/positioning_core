import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('PositioningController fusion stability', () {
    test('fused GPS estimates are valid and not NaN', () async {
      final controller = PositioningController(
        pdrEngine: IndoorPdrEngine(),
        mapMatcher: OutdoorMapMatcher(),
        config: const FusionConfig(
          gpsGoodAccuracyThreshold: 10.0,
        ),
      );

      await controller.start();

      final events = <PositionEstimate>[];
      final sub = controller.position$.listen(events.add);

      final t0 = DateTime.fromMillisecondsSinceEpoch(0);

      for (var i = 0; i < 5; i++) {
        controller.addGpsSample(
          GpsSample(
            timestamp: t0.add(Duration(seconds: i)),
            latitude: 32.0 + i * 1e-5,
            longitude: 35.0,
            horizontalAccuracy: 5.0,
            speed: 1.2,
            bearing: 45.0,
          ),
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events.length, 5);

      for (final est in events) {
        expect(est.source, PositionSource.fused);
        expect(est.isFused, isTrue);
        expect(est.isIndoor, isFalse);
        expect(est.latitude, isNotNull);
        expect(est.longitude, isNotNull);

        // Ensure we do not produce NaNs.
        expect(est.latitude!.isNaN, isFalse);
        expect(est.longitude!.isNaN, isFalse);
        if (est.headingDeg != null) {
          expect(est.headingDeg!.isNaN, isFalse);
        }
        if (est.accuracyMeters != null) {
          expect(est.accuracyMeters!.isNaN, isFalse);
        }
      }

      await controller.stop();
      await sub.cancel();
    });
  });
}
