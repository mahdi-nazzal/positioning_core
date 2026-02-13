import 'dart:async';

import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('PositioningController stream lifecycle', () {
    test('emits for multiple GPS samples while running', () async {
      final controller = PositioningController(
        pdrEngine: IndoorPdrEngine(),
        mapMatcher: OutdoorMapMatcher(),
      );

      await controller.start();

      final events = <PositionEstimate>[];
      final sub = controller.position$.listen(events.add);

      final t0 = DateTime.fromMillisecondsSinceEpoch(0);
      for (var i = 0; i < 5; i++) {
        controller.addGpsSample(
          GpsSample(
            timestamp: t0.add(Duration(seconds: i)),
            latitude: 32.0 + i * 1e-4,
            longitude: 35.0,
          ),
        );
      }

      // Allow the stream to deliver events.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events.length, 5);

      await controller.stop();
      await sub.cancel();
    });

    test('no events are emitted after stop', () async {
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
