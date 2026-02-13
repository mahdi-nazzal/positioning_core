///packages/positioning_core/lib/src/model/imu_sample.dart
import 'package:meta/meta.dart';

/// IMU sample combining accelerometer + gyroscope (+ magnetometer later).
///
/// Assumes values are given in a consistent device coordinate frame.
@immutable
class ImuSample {
  final DateTime timestamp;

  // Linear acceleration in m/s^2.
  final double ax;
  final double ay;
  final double az;

  // Angular velocity in rad/s.
  final double gx;
  final double gy;
  final double gz;

  // Optional magnetometer (µT).
  final double? mx;
  final double? my;
  final double? mz;

  const ImuSample({
    required this.timestamp,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    this.mx,
    this.my,
    this.mz,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'timestamp': timestamp.toIso8601String(),
      'ax': ax,
      'ay': ay,
      'az': az,
      'gx': gx,
      'gy': gy,
      'gz': gz,
      'mx': mx,
      'my': my,
      'mz': mz,
    };
  }

  factory ImuSample.fromJson(Map<String, dynamic> json) {
    return ImuSample(
      timestamp: DateTime.parse(json['timestamp'] as String),
      ax: (json['ax'] as num).toDouble(),
      ay: (json['ay'] as num).toDouble(),
      az: (json['az'] as num).toDouble(),
      gx: (json['gx'] as num).toDouble(),
      gy: (json['gy'] as num).toDouble(),
      gz: (json['gz'] as num).toDouble(),
      mx: (json['mx'] as num?)?.toDouble(),
      my: (json['my'] as num?)?.toDouble(),
      mz: (json['mz'] as num?)?.toDouble(),
    );
  }
}
