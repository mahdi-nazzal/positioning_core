import 'dart:math' as math;

import '../model/imu_sample.dart';
import '../utils/num_safety.dart';
import 'mag_gating.dart';
import 'orientation_estimate.dart';
import 'orientation_estimator.dart';

/// Madgwick AHRS (IMU+MAG) estimator with magnetometer gating.
///
/// Notes:
/// - Accel is assumed to include gravity direction (typical raw accelerometer).
/// - Gyro inputs are rad/s.
/// - Mag is expected in µT. Gating handles disturbances.
class MadgwickAhrsEstimator implements OrientationEstimator {
  /// Algorithm gain (higher = faster correction, lower = smoother).
  /// Typical: 0.05–0.2.
  final double beta;

  final MagGating magGating;

  // Quaternion of sensor frame relative to Earth frame.
  // q = [w, x, y, z]
  double _qw = 1.0;
  double _qx = 0.0;
  double _qy = 0.0;
  double _qz = 0.0;

  MadgwickAhrsEstimator({
    this.beta = 0.12,
    MagGating? magGating,
  }) : magGating = magGating ?? MagGating();

  @override
  OrientationEstimate update(ImuSample sample, double dtSeconds) {
    if (dtSeconds <= 0) {
      return _toEstimate(magUsed: false);
    }

    // Read & sanitize IMU values.
    final gx = safeDouble(sample.gx, fallback: 0.0);
    final gy = safeDouble(sample.gy, fallback: 0.0);
    final gz = safeDouble(sample.gz, fallback: 0.0);

    var ax = safeDouble(sample.ax, fallback: 0.0);
    var ay = safeDouble(sample.ay, fallback: 0.0);
    var az = safeDouble(sample.az, fallback: 0.0);

    // Normalize accelerometer (if not zero).
    final aNorm = math.sqrt(ax * ax + ay * ay + az * az);
    if (aNorm > 1e-9) {
      ax /= aNorm;
      ay /= aNorm;
      az /= aNorm;
    } else {
      // If accel is invalid, fall back to gyro-only integration.
      _integrateGyro(gx, gy, gz, dtSeconds);
      _normalizeQuat();
      return _toEstimate(magUsed: false);
    }

    // Decide whether to use magnetometer.
    final magValid = magGating.isMagValid(sample.mx, sample.my, sample.mz);

    if (magValid) {
      // Full AHRS update (gyro + accel + mag).
      var mx = safeDouble(sample.mx, fallback: 0.0);
      var my = safeDouble(sample.my, fallback: 0.0);
      var mz = safeDouble(sample.mz, fallback: 0.0);

      // Normalize magnetometer.
      final mNorm = math.sqrt(mx * mx + my * my + mz * mz);
      if (mNorm > 1e-9) {
        mx /= mNorm;
        my /= mNorm;
        mz /= mNorm;
      } else {
        // Mag invalid in practice; do IMU-only update.
        _madgwickImu(gx, gy, gz, ax, ay, az, dtSeconds);
        return _toEstimate(magUsed: false);
      }

      _madgwickAhrs(gx, gy, gz, ax, ay, az, mx, my, mz, dtSeconds);
      return _toEstimate(magUsed: true);
    } else {
      // IMU-only update (gyro + accel). Note: yaw still drifts, but roll/pitch stabilized.
      _madgwickImu(gx, gy, gz, ax, ay, az, dtSeconds);
      return _toEstimate(magUsed: false);
    }
  }

  @override
  void reset(
      {double yawRad = 0.0, double pitchRad = 0.0, double rollRad = 0.0}) {
    // Build quaternion from yaw/pitch/roll (Z-Y-X convention).
    final cy = math.cos(yawRad * 0.5);
    final sy = math.sin(yawRad * 0.5);
    final cp = math.cos(pitchRad * 0.5);
    final sp = math.sin(pitchRad * 0.5);
    final cr = math.cos(rollRad * 0.5);
    final sr = math.sin(rollRad * 0.5);

    _qw = cr * cp * cy + sr * sp * sy;
    _qx = sr * cp * cy - cr * sp * sy;
    _qy = cr * sp * cy + sr * cp * sy;
    _qz = cr * cp * sy - sr * sp * cy;

    _normalizeQuat();
    magGating.reset();
  }

  // ---------------------------
  // Madgwick IMU (6-axis)
  // ---------------------------

  void _madgwickImu(
    double gx,
    double gy,
    double gz,
    double ax,
    double ay,
    double az,
    double dt,
  ) {
    // Quaternion rate from gyro
    var qDot1 = 0.5 * (-_qx * gx - _qy * gy - _qz * gz);
    var qDot2 = 0.5 * (_qw * gx + _qy * gz - _qz * gy);
    var qDot3 = 0.5 * (_qw * gy - _qx * gz + _qz * gx);
    var qDot4 = 0.5 * (_qw * gz + _qx * gy - _qy * gx);

    // Gradient descent corrective step (IMU)
    final f1 = 2.0 * (_qx * _qz - _qw * _qy) - ax;
    final f2 = 2.0 * (_qw * _qx + _qy * _qz) - ay;
    final f3 = 2.0 * (0.5 - _qx * _qx - _qy * _qy) - az;

    final s1 = -2.0 * _qy * f1 + 2.0 * _qx * f2;
    final s2 = 2.0 * _qz * f1 + 2.0 * _qw * f2 - 4.0 * _qx * f3;
    final s3 = -2.0 * _qw * f1 + 2.0 * _qz * f2 - 4.0 * _qy * f3;
    final s4 = 2.0 * _qx * f1 + 2.0 * _qy * f2;

    var norm = math.sqrt(s1 * s1 + s2 * s2 + s3 * s3 + s4 * s4);
    if (norm > 1e-9) {
      final inv = 1.0 / norm;
      final g1 = s1 * inv;
      final g2 = s2 * inv;
      final g3 = s3 * inv;
      final g4 = s4 * inv;

      qDot1 -= beta * g1;
      qDot2 -= beta * g2;
      qDot3 -= beta * g3;
      qDot4 -= beta * g4;
    }

    // Integrate
    _qw += qDot1 * dt;
    _qx += qDot2 * dt;
    _qy += qDot3 * dt;
    _qz += qDot4 * dt;

    _normalizeQuat();
  }

  // ---------------------------
  // Madgwick AHRS (9-axis)
  // ---------------------------

  void _madgwickAhrs(
    double gx,
    double gy,
    double gz,
    double ax,
    double ay,
    double az,
    double mx,
    double my,
    double mz,
    double dt,
  ) {
    // Reference direction of Earth's magnetic field
    final q0 = _qw, q1 = _qx, q2 = _qy, q3 = _qz;

    final hx = 2.0 * mx * (0.5 - q2 * q2 - q3 * q3) +
        2.0 * my * (q1 * q2 - q0 * q3) +
        2.0 * mz * (q1 * q3 + q0 * q2);

    final hy = 2.0 * mx * (q1 * q2 + q0 * q3) +
        2.0 * my * (0.5 - q1 * q1 - q3 * q3) +
        2.0 * mz * (q2 * q3 - q0 * q1);

    final bx = math.sqrt(hx * hx + hy * hy);
    final bz = 2.0 * mx * (q1 * q3 - q0 * q2) +
        2.0 * my * (q2 * q3 + q0 * q1) +
        2.0 * mz * (0.5 - q1 * q1 - q2 * q2);

    // Quaternion rate from gyro
    var qDot1 = 0.5 * (-q1 * gx - q2 * gy - q3 * gz);
    var qDot2 = 0.5 * (q0 * gx + q2 * gz - q3 * gy);
    var qDot3 = 0.5 * (q0 * gy - q1 * gz + q3 * gx);
    var qDot4 = 0.5 * (q0 * gz + q1 * gy - q2 * gx);

    // Gradient descent step
    final f1 = 2.0 * (q1 * q3 - q0 * q2) - ax;
    final f2 = 2.0 * (q0 * q1 + q2 * q3) - ay;
    final f3 = 2.0 * (0.5 - q1 * q1 - q2 * q2) - az;
    final f4 = 2.0 * bx * (0.5 - q2 * q2 - q3 * q3) +
        2.0 * bz * (q1 * q3 - q0 * q2) -
        mx;
    final f5 =
        2.0 * bx * (q1 * q2 - q0 * q3) + 2.0 * bz * (q0 * q1 + q2 * q3) - my;
    final f6 = 2.0 * bx * (q0 * q2 + q1 * q3) +
        2.0 * bz * (0.5 - q1 * q1 - q2 * q2) -
        mz;

    final s0 = (-2.0 * q2) * f1 +
        (2.0 * q1) * f2 +
        (-2.0 * bz * q2) * f4 +
        (-2.0 * bx * q3 + 2.0 * bz * q1) * f5 +
        (2.0 * bx * q2) * f6;
    final s1 = (2.0 * q3) * f1 +
        (2.0 * q0) * f2 +
        (-4.0 * q1) * f3 +
        (2.0 * bz * q3) * f4 +
        (2.0 * bx * q2 + 2.0 * bz * q0) * f5 +
        (2.0 * bx * q3 - 4.0 * bz * q1) * f6;
    final s2 = (-2.0 * q0) * f1 +
        (2.0 * q3) * f2 +
        (-4.0 * q2) * f3 +
        (-4.0 * bx * q2 - 2.0 * bz * q0) * f4 +
        (2.0 * bx * q1 + 2.0 * bz * q3) * f5 +
        (2.0 * bx * q0 - 4.0 * bz * q2) * f6;
    final s3 = (2.0 * q1) * f1 +
        (2.0 * q2) * f2 +
        (-2.0 * bx * q3 + 2.0 * bz * q1) * f4 +
        (-2.0 * bx * q0 + 2.0 * bz * q2) * f5 +
        (2.0 * bx * q1) * f6;

    var norm = math.sqrt(s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3);
    if (norm > 1e-9) {
      final inv = 1.0 / norm;
      final g0 = s0 * inv;
      final g1 = s1 * inv;
      final g2 = s2 * inv;
      final g3 = s3 * inv;

      qDot1 -= beta * g0;
      qDot2 -= beta * g1;
      qDot3 -= beta * g2;
      qDot4 -= beta * g3;
    }

    // Integrate
    _qw += qDot1 * dt;
    _qx += qDot2 * dt;
    _qy += qDot3 * dt;
    _qz += qDot4 * dt;

    _normalizeQuat();
  }

  // ---------------------------
  // Utilities
  // ---------------------------

  void _integrateGyro(double gx, double gy, double gz, double dt) {
    // Quaternion derivative from gyro:
    final q0 = _qw, q1 = _qx, q2 = _qy, q3 = _qz;

    final qDot1 = 0.5 * (-q1 * gx - q2 * gy - q3 * gz);
    final qDot2 = 0.5 * (q0 * gx + q2 * gz - q3 * gy);
    final qDot3 = 0.5 * (q0 * gy - q1 * gz + q3 * gx);
    final qDot4 = 0.5 * (q0 * gz + q1 * gy - q2 * gx);

    _qw += qDot1 * dt;
    _qx += qDot2 * dt;
    _qy += qDot3 * dt;
    _qz += qDot4 * dt;
  }

  void _normalizeQuat() {
    final norm = math.sqrt(_qw * _qw + _qx * _qx + _qy * _qy + _qz * _qz);
    if (norm <= 1e-12) return;
    final inv = 1.0 / norm;
    _qw *= inv;
    _qx *= inv;
    _qy *= inv;
    _qz *= inv;
  }

  OrientationEstimate _toEstimate({required bool magUsed}) {
    // Convert quaternion to yaw/pitch/roll (Z-Y-X).
    final q0 = _qw, q1 = _qx, q2 = _qy, q3 = _qz;

    final sinrCosp = 2.0 * (q0 * q1 + q2 * q3);
    final cosrCosp = 1.0 - 2.0 * (q1 * q1 + q2 * q2);
    final roll = math.atan2(sinrCosp, cosrCosp);

    final sinp = 2.0 * (q0 * q2 - q3 * q1);
    final pitch =
        sinp.abs() >= 1.0 ? math.sin(sinp) * (math.pi / 2.0) : math.asin(sinp);

    final sinyCosp = 2.0 * (q0 * q3 + q1 * q2);
    final cosyCosp = 1.0 - 2.0 * (q2 * q2 + q3 * q3);
    final yaw = _normalizeAngle(math.atan2(sinyCosp, cosyCosp));

    return OrientationEstimate(
      yawRad: yaw,
      pitchRad: pitch,
      rollRad: roll,
      magUsed: magUsed,
    );
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
