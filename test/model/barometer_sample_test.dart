import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('BarometerSample', () {
    test('constructor assigns fields correctly', () {
      final t = DateTime.fromMillisecondsSinceEpoch(0);

      final sample = BarometerSample(
        timestamp: t,
        pressureHpa: 1013.25,
        temperatureC: 23.5,
      );

      expect(sample.timestamp, t);
      expect(sample.pressureHpa, 1013.25);
      expect(sample.temperatureC, 23.5);
    });
  });
}
