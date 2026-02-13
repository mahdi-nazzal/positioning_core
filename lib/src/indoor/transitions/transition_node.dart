import 'package:meta/meta.dart';

enum TransitionType { stairs, elevator }

@immutable
class TransitionNode {
  final String buildingId;
  final String levelId;
  final String transitionId; // same across levels for the same shaft/stair
  final TransitionType type;
  final double x;
  final double y;

  const TransitionNode({
    required this.buildingId,
    required this.levelId,
    required this.transitionId,
    required this.type,
    required this.x,
    required this.y,
  });
}
