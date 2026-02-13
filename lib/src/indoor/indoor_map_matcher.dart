import '../model/position_estimate.dart';

class IndoorSnapDiagnostics {
  final bool snapped;
  final double rawX;
  final double rawY;
  final double outX;
  final double outY;
  final double snapDistanceMeters;

  final String? activeEdgeId;
  final String decision; // attach|hold|detach|none|reject_switch
  final String? switchReason; // adjacency|turn|jump|too_far|etc.

  /// Extra diagnostics for advanced matchers (particle filter, etc.)
  final Map<String, dynamic> extra;

  const IndoorSnapDiagnostics({
    required this.snapped,
    required this.rawX,
    required this.rawY,
    required this.outX,
    required this.outY,
    required this.snapDistanceMeters,
    required this.activeEdgeId,
    required this.decision,
    required this.switchReason,
    this.extra = const <String, dynamic>{},
  });

  /// No-op diagnostics: "matcher did nothing".
  static IndoorSnapDiagnostics identity(PositionEstimate estimate) {
    final x = estimate.x ?? 0.0;
    final y = estimate.y ?? 0.0;
    return IndoorSnapDiagnostics(
      snapped: false,
      rawX: x,
      rawY: y,
      outX: x,
      outY: y,
      snapDistanceMeters: 0.0,
      activeEdgeId: null,
      decision: 'none',
      switchReason: null,
      extra: const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'snapped': snapped,
        'rawX': rawX,
        'rawY': rawY,
        'outX': outX,
        'outY': outY,
        'snapDistanceMeters': snapDistanceMeters,
        'activeEdgeId': activeEdgeId,
        'decision': decision,
        'switchReason': switchReason,
        'extra': extra,
      };
}

class IndoorMapMatchResult {
  final PositionEstimate estimate;
  final IndoorSnapDiagnostics diagnostics;

  const IndoorMapMatchResult({
    required this.estimate,
    required this.diagnostics,
  });

  static IndoorMapMatchResult identity(PositionEstimate estimate) =>
      IndoorMapMatchResult(
        estimate: estimate,
        diagnostics: IndoorSnapDiagnostics.identity(estimate),
      );
}

/// Applies indoor map constraints to an indoor estimate (x/y must be present).
abstract class IndoorMapMatcher {
  IndoorMapMatchResult match(PositionEstimate raw);
  void reset();
}
