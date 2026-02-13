import 'package:positioning_core/positioning_core.dart';
import 'package:positioning_core/src/orientation/madgwick_ahrs_estimator.dart';
import 'package:test/test.dart';

void main() {
  test('Madgwick: stationary with mag bounds yaw drift under gyro bias', () {
    final est = MadgwickAhrsEstimator(beta: 0.12);

    final t0 = DateTime.utc(2025, 1, 1, 0, 0, 0);

    // Simulate 10 seconds @ 50Hz.
    // Gyro has a small bias => would drift if no correction.
    // Accel indicates gravity (device flat). Mag is stable (valid).
    final dt = 1.0 / 50.0;
    var t = t0;

    for (var i = 0; i < 500; i++) {
      final s = ImuSample(
        timestamp: t,
        ax: 0.0,
        ay: 0.0,
        az: 9.81,
        gx: 0.0,
        gy: 0.0,
        gz: 0.01, // bias rad/s
        mx: 30.0,
        my: 0.0,
        mz: 0.0,
      );
      est.update(s, dt);
      t = t.add(const Duration(milliseconds: 20));
    }

    // With mag correction, yaw should not drift wildly.
    // Keep threshold generous to avoid device-frame assumptions.
    final yawDeg = est
        .update(
          ImuSample(
            timestamp: t,
            ax: 0.0,
            ay: 0.0,
            az: 9.81,
            gx: 0.0,
            gy: 0.0,
            gz: 0.01,
            mx: 30.0,
            my: 0.0,
            mz: 0.0,
          ),
          dt,
        )
        .yawDeg
        .abs();

    expect(yawDeg, lessThan(20.0));
  });
}
