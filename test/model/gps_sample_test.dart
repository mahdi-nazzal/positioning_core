import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('GpsSample', () {
    test('constructor assigns fields correctly', () {
      final t = DateTime.fromMillisecondsSinceEpoch(123456);
      const lat = 32.1234;
      const lon = 35.5678;
      const alt = 500.0;
      const hAcc = 3.0;
      const vAcc = 5.0;
      const speed = 1.2;
      const bearing = 90.0;

      final sample = GpsSample(
        timestamp: t,
        latitude: lat,
        longitude: lon,
        altitude: alt,
        horizontalAccuracy: hAcc,
        verticalAccuracy: vAcc,
        speed: speed,
        bearing: bearing,
      );

      expect(sample.timestamp, t);
      expect(sample.latitude, lat);
      expect(sample.longitude, lon);
      expect(sample.altitude, alt);
      expect(sample.horizontalAccuracy, hAcc);
      expect(sample.verticalAccuracy, vAcc);
      expect(sample.speed, speed);
      expect(sample.bearing, bearing);
    });
  });
}
