import 'dart:math' as math;

import '../model/imu_sample.dart';
import '../utils/num_safety.dart';
import 'orientation_estimate.dart';
import 'orientation_estimator.dart';

class GyroYawEstimator implements OrientationEstimator {
  double _yaw = 0.0;

  @override
  OrientationEstimate update(ImuSample sample, double dtSeconds) {
    final gz = safeDouble(sample.gz, fallback: 0.0);
    if (dtSeconds > 0) {
      _yaw = _normalizeAngle(_yaw + gz * dtSeconds);
    }
    return OrientationEstimate(
      yawRad: _yaw,
      pitchRad: 0.0,
      rollRad: 0.0,
      magUsed: false,
    );
  }

  @override
  void reset(
      {double yawRad = 0.0, double pitchRad = 0.0, double rollRad = 0.0}) {
    _yaw = _normalizeAngle(yawRad);
  }

  double _normalizeAngle(double angle) {
    while (angle <= -math.pi) {
      angle += 2 * math.pi;
    }
    while (angle > math.pi) {
      angle -= 2 * math.pi;
    }
    return angle;
  }
}
