import '../model/imu_sample.dart';
import 'orientation_estimate.dart';

/// Interface for orientation estimation (yaw/pitch/roll).
///
/// Implementations may use:
/// - gyro-only (yaw integration),
/// - 6-axis IMU (gyro+accel),
/// - 9-axis AHRS (gyro+accel+mag).
abstract class OrientationEstimator {
  /// Update filter state and return latest estimate.
  ///
  /// [dtSeconds] is the time delta between samples (already clamped in PR-3).
  OrientationEstimate update(ImuSample sample, double dtSeconds);

  /// Reset estimator state.
  void reset({
    double yawRad = 0.0,
    double pitchRad = 0.0,
    double rollRad = 0.0,
  });
}
