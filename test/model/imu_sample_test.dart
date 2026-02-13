import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  group('ImuSample', () {
    test('constructor assigns fields correctly', () {
      final t = DateTime.fromMillisecondsSinceEpoch(0);

      final sample = ImuSample(
        timestamp: t,
        ax: 0.1,
        ay: 9.81,
        az: -0.2,
        gx: 0.01,
        gy: 0.02,
        gz: 0.03,
        mx: 10.0,
        my: 20.0,
        mz: 30.0,
      );

      expect(sample.timestamp, t);
      expect(sample.ax, 0.1);
      expect(sample.ay, 9.81);
      expect(sample.az, -0.2);
      expect(sample.gx, 0.01);
      expect(sample.gy, 0.02);
      expect(sample.gz, 0.03);
      expect(sample.mx, 10.0);
      expect(sample.my, 20.0);
      expect(sample.mz, 30.0);
    });
  });
}
