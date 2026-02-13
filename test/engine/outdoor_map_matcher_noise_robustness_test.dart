import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('OutdoorMapMatcher noise robustness (stub)', () {
    test('emits one estimate per noisy GPS sample', () {
      final matcher = OutdoorMapMatcher();

      const baseLat = 32.0;
      const baseLon = 35.0;
      final t0 = DateTime.fromMillisecondsSinceEpoch(0);

      final samples = <GpsSample>[];
      for (var i = 0; i < 20; i++) {
        final latJitter = (i - 10) * 1e-5;
        final lonJitter = (10 - i) * 1e-5;
        samples.add(
          GpsSample(
            timestamp: t0.add(Duration(seconds: i)),
            latitude: baseLat + latJitter,
            longitude: baseLon + lonJitter,
            horizontalAccuracy: 5.0,
          ),
        );
      }

      final estimates = <PositionEstimate>[];
      for (final s in samples) {
        estimates.add(matcher.addGpsSample(s));
      }

      expect(estimates.length, samples.length);

      for (var i = 0; i < samples.length; i++) {
        final est = estimates[i];
        final sample = samples[i];

        expect(est.source, PositionSource.gps);
        expect(est.isIndoor, isFalse);
        expect(est.latitude, closeTo(sample.latitude, 1e-9));
        expect(est.longitude, closeTo(sample.longitude, 1e-9));
      }
    });
  });
}
