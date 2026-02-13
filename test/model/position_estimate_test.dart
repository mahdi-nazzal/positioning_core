import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('PositionEstimate', () {
    test('copyWith preserves unspecified fields', () {
      final t = DateTime.fromMillisecondsSinceEpoch(0);

      final est = PositionEstimate(
        timestamp: t,
        source: PositionSource.gps,
        latitude: 10.0,
        longitude: 20.0,
        altitude: 100.0,
        x: 1.0,
        y: 2.0,
        z: 3.0,
        buildingId: '11',
        levelId: '11G',
        isIndoor: false,
        headingDeg: 45.0,
        speedMps: 1.5,
        accuracyMeters: 5.0,
        isFused: false,
      );

      final updated = est.copyWith(latitude: 11.0);

      expect(updated.latitude, 11.0);
      expect(updated.longitude, est.longitude);
      expect(updated.altitude, est.altitude);
      expect(updated.x, est.x);
      expect(updated.y, est.y);
      expect(updated.z, est.z);
      expect(updated.buildingId, est.buildingId);
      expect(updated.levelId, est.levelId);
      expect(updated.isIndoor, est.isIndoor);
      expect(updated.headingDeg, est.headingDeg);
      expect(updated.speedMps, est.speedMps);
      expect(updated.accuracyMeters, est.accuracyMeters);
      expect(updated.source, est.source);
      expect(updated.isFused, est.isFused);
    });
  });
}
