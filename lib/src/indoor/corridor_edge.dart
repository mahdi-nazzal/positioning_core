import 'dart:math' as math;

/// A single corridor centerline segment in the same coordinate system as indoor x/y.
///
/// Typical source: indoor graph edges projected into floor-plan meters.
class CorridorEdge {
  final String id;
  final double ax;
  final double ay;
  final double bx;
  final double by;

  /// Optional semantic tags.
  final String? buildingId;
  final String? levelId;

  const CorridorEdge({
    required this.id,
    required this.ax,
    required this.ay,
    required this.bx,
    required this.by,
    this.buildingId,
    this.levelId,
  });

  double get dx => bx - ax;
  double get dy => by - ay;

  double get length => math.sqrt(dx * dx + dy * dy);

  /// Direction angle in radians.
  double get headingRad => math.atan2(dy, dx);
}
