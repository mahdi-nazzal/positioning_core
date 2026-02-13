import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  test('haversineMeters returns ~0 for identical points', () {
    final d = haversineMeters(
      lat1Deg: 32.0,
      lon1Deg: 35.0,
      lat2Deg: 32.0,
      lon2Deg: 35.0,
    );
    expect(d, closeTo(0.0, 1e-6));
  });

  test('rmse1d works', () {
    final v = rmse1d([3, 4]); // sqrt((9+16)/2)=sqrt(12.5)=3.535...
    expect(v, closeTo(3.5355339, 1e-6));
  });
}
