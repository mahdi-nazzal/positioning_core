import 'package:meta/meta.dart';

@immutable
class OrientationEstimate {
  /// Yaw (heading) in radians, normalized to [-pi, +pi].
  final double yawRad;

  /// Pitch in radians (optional for UI/diagnostics).
  final double pitchRad;

  /// Roll in radians (optional for UI/diagnostics).
  final double rollRad;

  /// True if magnetometer correction was applied on this update.
  final bool magUsed;

  const OrientationEstimate({
    required this.yawRad,
    required this.pitchRad,
    required this.rollRad,
    required this.magUsed,
  });

  double get yawDeg => yawRad * 180.0 / 3.141592653589793;
  double get pitchDeg => pitchRad * 180.0 / 3.141592653589793;
  double get rollDeg => rollRad * 180.0 / 3.141592653589793;
}
