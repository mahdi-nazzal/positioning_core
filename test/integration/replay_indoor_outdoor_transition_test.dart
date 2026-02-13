import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('Replay indoor/outdoor transition', () {
    test(
        'starts outdoor on GPS, then transitions to indoor on PDR after GPS stale',
        () async {
      final pdrEngine = IndoorPdrEngine(
        stepLengthMeters: 1.0,
        stepAccelThreshold: 3.0,
        minStepInterval: const Duration(milliseconds: 300),
      );

      final logger = InMemoryPositioningLogger();

      final controller = PositioningController(
        pdrEngine: pdrEngine,
        mapMatcher: OutdoorMapMatcher(),
        config: const FusionConfig(
          gpsGoodAccuracyThreshold: 10.0,
          gpsStaleDuration: Duration(seconds: 2),
          indoorStepCountThreshold: 2,
        ),
        logger: logger,
      );

      final replayer = PositioningReplayer(controller);

      final t0 = DateTime.fromMillisecondsSinceEpoch(0);
      final events = <ReplayEvent>[];

      // 1) Outdoor GPS fix at t=0
      events.add(
        GpsReplayEvent(
          GpsSample(
            timestamp: t0,
            latitude: 32.0,
            longitude: 35.0,
            horizontalAccuracy: 3.0,
          ),
        ),
      );

      // 2) PDR steps after GPS becomes stale (t >= 3s).
      DateTime current = t0;
      for (var i = 0; i < 4; i++) {
        current = current.add(const Duration(seconds: 3));
        events.add(
          ImuReplayEvent(
            ImuSample(
              timestamp: current,
              ax: 0.0,
              ay: 5.0, // above threshold
              az: 0.0,
              gx: 0.0,
              gy: 0.0,
              gz: 0.0,
            ),
          ),
        );
      }

      final estimates = await replayer.replay(events);

      // We expect at least one outdoor fused estimate and at least one indoor fused estimate.
      final outdoor = estimates.where((e) => !e.isIndoor).toList();
      final indoor = estimates.where((e) => e.isIndoor).toList();

      expect(outdoor, isNotEmpty);
      expect(indoor, isNotEmpty);

      final first = estimates.first;
      final last = estimates.last;

      expect(first.isIndoor, isFalse);
      expect(first.latitude, isNotNull);
      expect(first.longitude, isNotNull);

      expect(last.isIndoor, isTrue);
      expect(last.latitude, isNull);
      expect(last.longitude, isNull);
      expect(last.x, isNotNull);
      expect(last.y, isNotNull);

      // Logger should have captured all IMU samples and fused estimates.
      expect(logger.imuSamples.length, 4);
      expect(logger.estimates.length, estimates.length);
    });
  });
}
