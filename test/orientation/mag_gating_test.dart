import 'package:positioning_core/src/orientation/mag_gating.dart';
import 'package:test/test.dart';

void main() {
  test('MagGating rejects obviously disturbed magnitude', () {
    final g = MagGating();

    // Build baseline with valid norm ~30.
    expect(g.isMagValid(30, 0, 0), isTrue);
    expect(g.isMagValid(30, 0, 0), isTrue);

    // Disturbed: very large norm.
    expect(g.isMagValid(200, 0, 0), isFalse);
  });
}
