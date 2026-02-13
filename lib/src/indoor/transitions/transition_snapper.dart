import 'dart:math' as math;

import 'transition_node.dart';

class TransitionSnapResult {
  final double x;
  final double y;
  final String transitionId;
  final TransitionType type;
  final double snapDistanceMeters;

  const TransitionSnapResult({
    required this.x,
    required this.y,
    required this.transitionId,
    required this.type,
    required this.snapDistanceMeters,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'x': x,
        'y': y,
        'transitionId': transitionId,
        'type': type.name,
        'snapDistanceMeters': snapDistanceMeters,
      };
}

/// Strategy interface.
/// On floor change commit, we try to snap the user's x/y to the corresponding
/// transition connector on the new floor (stairs/elevator shaft).
abstract class TransitionSnapper {
  TransitionSnapResult? snapOnLevelChange({
    required String buildingId,
    required String fromLevelId,
    required String toLevelId,
    required double x,
    required double y,
  });
}

/// In-memory implementation (production-ready for your campus):
/// - pick nearest transition node on from-level within radius
/// - map by transitionId to the target floor
class InMemoryTransitionSnapper implements TransitionSnapper {
  InMemoryTransitionSnapper({
    required List<TransitionNode> nodes,
    this.searchRadiusMeters = 6.0,
  }) : _nodes = nodes;

  final List<TransitionNode> _nodes;
  final double searchRadiusMeters;

  @override
  TransitionSnapResult? snapOnLevelChange({
    required String buildingId,
    required String fromLevelId,
    required String toLevelId,
    required double x,
    required double y,
  }) {
    // 1) find nearest transition node on from floor
    TransitionNode? nearestFrom;
    var nearestFromD = double.infinity;

    for (final n in _nodes) {
      if (n.buildingId != buildingId) continue;
      if (n.levelId != fromLevelId) continue;

      final d = _dist(x, y, n.x, n.y);
      if (d < nearestFromD) {
        nearestFromD = d;
        nearestFrom = n;
      }
    }

    if (nearestFrom == null || nearestFromD > searchRadiusMeters) return null;

    // 2) find matching node on target floor by transitionId
    TransitionNode? bestTo;
    var bestToD = double.infinity;

    for (final n in _nodes) {
      if (n.buildingId != buildingId) continue;
      if (n.levelId != toLevelId) continue;
      if (n.transitionId != nearestFrom.transitionId) continue;

      // choose closest in xy (usually only one)
      final d = _dist(x, y, n.x, n.y);
      if (d < bestToD) {
        bestToD = d;
        bestTo = n;
      }
    }

    if (bestTo == null) return null;

    return TransitionSnapResult(
      x: bestTo.x,
      y: bestTo.y,
      transitionId: bestTo.transitionId,
      type: bestTo.type,
      snapDistanceMeters: bestToD,
    );
  }

  static double _dist(double x1, double y1, double x2, double y2) {
    final dx = x1 - x2;
    final dy = y1 - y2;
    return math.sqrt(dx * dx + dy * dy);
  }
}
