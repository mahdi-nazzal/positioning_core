import 'dart:async';

import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('PositioningCore basic sanity', () {
    test('controller can start, receive GPS sample, and emit estimate',
        () async {
      final controller = PositioningController(
        pdrEngine: IndoorPdrEngine(),
        mapMatcher: OutdoorMapMatcher(),
      );

      await controller.start();

      final events = <PositionEstimate>[];
      final sub = controller.position$.listen(events.add);

      controller.addGpsSample(
        GpsSample(
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          latitude: 32.0,
          longitude: 35.0,
        ),
      );

      // Give the stream a short time to deliver the event.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events, isNotEmpty);
      expect(events.first.latitude, 32.0);
      expect(events.first.longitude, 35.0);

      await controller.stop();
      await sub.cancel();
    });

    test('controller ignores samples after stop', () async {
      final controller = PositioningController(
        pdrEngine: IndoorPdrEngine(),
        mapMatcher: OutdoorMapMatcher(),
      );

      await controller.start();
      final events = <PositionEstimate>[];
      final sub = controller.position$.listen(events.add);

      await controller.stop();

      controller.addGpsSample(
        GpsSample(
          timestamp: DateTime.now(),
          latitude: 0.0,
          longitude: 0.0,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events, isEmpty);
      await sub.cancel();
    });
  });
}
