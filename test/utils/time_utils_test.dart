import 'package:positioning_core/src/utils/time_utils.dart';
import 'package:test/test.dart';

void main() {
  test('clampedDtSeconds returns 0 when prev is null', () {
    final dt = clampedDtSeconds(null, DateTime.utc(2025, 1, 1));
    expect(dt, 0.0);
  });

  test('clampedDtSeconds clamps large dt', () {
    final t0 = DateTime.utc(2025, 1, 1, 0, 0, 0);
    final t1 = t0.add(const Duration(seconds: 10));
    final dt = clampedDtSeconds(t0, t1, maxDtSeconds: 0.2);
    expect(dt, 0.2);
  });

  test('clampedDtSeconds clamps tiny dt', () {
    final t0 = DateTime.utc(2025, 1, 1, 0, 0, 0);
    final t1 = t0.add(const Duration(microseconds: 10)); // 10us => 0.00001s
    final dt = clampedDtSeconds(t0, t1, minDtSeconds: 0.001);
    expect(dt, 0.001);
  });
}
