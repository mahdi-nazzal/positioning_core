import 'package:positioning_core/src/utils/num_safety.dart';
import 'package:test/test.dart';

void main() {
  test('safeDouble returns fallback for null', () {
    expect(safeDouble(null, fallback: 7.0), 7.0);
  });

  test('safeDouble clamps min/max', () {
    expect(safeDouble(5, min: 6), 6.0);
    expect(safeDouble(10, max: 9), 9.0);
  });
}
