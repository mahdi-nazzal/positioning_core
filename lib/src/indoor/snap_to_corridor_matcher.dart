import 'dart:math' as math;

import '../model/position_estimate.dart';
import 'corridor_edge.dart';
import 'indoor_map_matcher.dart';

class SnapToCorridorMatcher implements IndoorMapMatcher {
  final List<CorridorEdge> edges;

  /// Hysteresis:
  /// - attach: start snapping when within this distance.
  /// - detach: keep current edge until farther than this.
  final double attachDistanceMeters;
  final double detachDistanceMeters;

  /// Hard cap: never snap if farther than this.
  final double maxSnapDistanceMeters;

  /// Reject switching if snapped point would jump too far.
  final double maxSnapJumpMeters;

  /// Reject switching if turn is too sharp for the observed motion direction.
  final double maxTurnDegrees;

  /// Only apply turn check if we moved at least this much since last update.
  final double minMoveForTurnCheckMeters;

  /// Edges considered adjacent if endpoints within epsilon.
  final double adjacencyEpsMeters;

  String? _activeEdgeId;

  // For motion / turn checking.
  double? _lastRawX;
  double? _lastRawY;
  DateTime? _lastTs;

  // Precomputed adjacency.
  late final Map<String, Set<String>> _adj;

  SnapToCorridorMatcher({
    required this.edges,
    this.attachDistanceMeters = 1.2,
    this.detachDistanceMeters = 2.0,
    this.maxSnapDistanceMeters = 3.0,
    this.maxSnapJumpMeters = 3.0,
    this.maxTurnDegrees = 120.0,
    this.minMoveForTurnCheckMeters = 0.6,
    this.adjacencyEpsMeters = 0.35,
  }) {
    _adj = _buildAdjacency(edges, eps: adjacencyEpsMeters);
  }

  @override
  IndoorMapMatchResult match(PositionEstimate raw) {
    final x = raw.x;
    final y = raw.y;

    if (x == null || y == null || edges.isEmpty) {
      return IndoorMapMatchResult(
        estimate: raw,
        diagnostics: IndoorSnapDiagnostics(
          snapped: false,
          rawX: x ?? 0.0,
          rawY: y ?? 0.0,
          outX: x ?? 0.0,
          outY: y ?? 0.0,
          snapDistanceMeters: double.infinity,
          activeEdgeId: _activeEdgeId,
          decision: 'none',
          switchReason: 'missing_xy_or_no_edges',
        ),
      );
    }

    final best = _nearestEdgeProjection(x, y);
    if (best == null) {
      return IndoorMapMatchResult(
        estimate: raw,
        diagnostics: IndoorSnapDiagnostics(
          snapped: false,
          rawX: x,
          rawY: y,
          outX: x,
          outY: y,
          snapDistanceMeters: double.infinity,
          activeEdgeId: _activeEdgeId,
          decision: 'none',
          switchReason: 'no_candidate',
        ),
      );
    }

    // Optionally compute current edge distance.
    _NearestProjection? activeProj;
    if (_activeEdgeId != null) {
      activeProj = _nearestToSpecificEdge(x, y, _activeEdgeId!);
      if (activeProj == null) {
        _activeEdgeId = null; // stale edge id
      }
    }

    // Decide snap based on hysteresis.
    final maxSnap = maxSnapDistanceMeters;

    // No active edge: attach if close enough.
    if (_activeEdgeId == null) {
      if (best.distanceMeters <= attachDistanceMeters &&
          best.distanceMeters <= maxSnap) {
        _activeEdgeId = best.edge.id;

        final out = raw.copyWith(x: best.px, y: best.py);
        _updateMotionMemory(raw);
        return IndoorMapMatchResult(
          estimate: out,
          diagnostics: IndoorSnapDiagnostics(
            snapped: true,
            rawX: x,
            rawY: y,
            outX: best.px,
            outY: best.py,
            snapDistanceMeters: best.distanceMeters,
            activeEdgeId: _activeEdgeId,
            decision: 'attach',
            switchReason: null,
          ),
        );
      }

      _updateMotionMemory(raw);
      return IndoorMapMatchResult(
        estimate: raw,
        diagnostics: IndoorSnapDiagnostics(
          snapped: false,
          rawX: x,
          rawY: y,
          outX: x,
          outY: y,
          snapDistanceMeters: best.distanceMeters,
          activeEdgeId: null,
          decision: 'none',
          switchReason: 'too_far_to_attach',
        ),
      );
    }

    // Active edge exists.
    final cur = activeProj;
    if (cur != null) {
      // If still close to active edge: hold it.
      if (cur.distanceMeters <= detachDistanceMeters &&
          cur.distanceMeters <= maxSnap) {
        final out = raw.copyWith(x: cur.px, y: cur.py);
        _updateMotionMemory(raw);
        return IndoorMapMatchResult(
          estimate: out,
          diagnostics: IndoorSnapDiagnostics(
            snapped: true,
            rawX: x,
            rawY: y,
            outX: cur.px,
            outY: cur.py,
            snapDistanceMeters: cur.distanceMeters,
            activeEdgeId: _activeEdgeId,
            decision: 'hold',
            switchReason: null,
          ),
        );
      }
    }

    // Consider switching to best edge (attach threshold).
    if (best.distanceMeters <= attachDistanceMeters &&
        best.distanceMeters <= maxSnap) {
      final can = _canSwitch(
        fromEdgeId: _activeEdgeId!,
        to: best,
        raw: raw,
      );

      if (can.ok) {
        _activeEdgeId = best.edge.id;
        final out = raw.copyWith(x: best.px, y: best.py);
        _updateMotionMemory(raw);
        return IndoorMapMatchResult(
          estimate: out,
          diagnostics: IndoorSnapDiagnostics(
            snapped: true,
            rawX: x,
            rawY: y,
            outX: best.px,
            outY: best.py,
            snapDistanceMeters: best.distanceMeters,
            activeEdgeId: _activeEdgeId,
            decision: 'attach',
            switchReason: can.reason,
          ),
        );
      }

      // Reject switch -> detach (no snap) or continue raw.
      _updateMotionMemory(raw);
      return IndoorMapMatchResult(
        estimate: raw,
        diagnostics: IndoorSnapDiagnostics(
          snapped: false,
          rawX: x,
          rawY: y,
          outX: x,
          outY: y,
          snapDistanceMeters: best.distanceMeters,
          activeEdgeId: _activeEdgeId,
          decision: 'reject_switch',
          switchReason: can.reason,
        ),
      );
    }

    // Too far from best -> detach completely (raw).
    _updateMotionMemory(raw);
    return IndoorMapMatchResult(
      estimate: raw,
      diagnostics: IndoorSnapDiagnostics(
        snapped: false,
        rawX: x,
        rawY: y,
        outX: x,
        outY: y,
        snapDistanceMeters: best.distanceMeters,
        activeEdgeId: _activeEdgeId,
        decision: 'detach',
        switchReason: 'too_far',
      ),
    );
  }

  @override
  void reset() {
    _activeEdgeId = null;
    _lastRawX = null;
    _lastRawY = null;
    _lastTs = null;
  }

  // -----------------------
  // Switching penalties
  // -----------------------

  _SwitchDecision _canSwitch({
    required String fromEdgeId,
    required _NearestProjection to,
    required PositionEstimate raw,
  }) {
    // 1) Adjacency gate (basic "wall-crossing" proxy):
    // if edges are not adjacent, allow only if extremely close.
    final adjacent = _adj[fromEdgeId]?.contains(to.edge.id) ?? false;
    final veryClose = to.distanceMeters <= (attachDistanceMeters * 0.45);

    if (!adjacent && !veryClose) {
      return const _SwitchDecision(false, 'non_adjacent');
    }

    // 2) Jump gate: switching should not teleport snapped point far away.
    // Use last raw point as reference if available.
    final lx = _lastRawX;
    final ly = _lastRawY;
    if (lx != null && ly != null) {
      final jump = _dist(lx, ly, to.px, to.py);
      if (jump > maxSnapJumpMeters && !veryClose) {
        return const _SwitchDecision(false, 'snap_jump');
      }
    }

    // 3) Impossible turn gate based on motion direction vs target edge direction.
    final turn = _turnTooSharp(raw, to.edge);
    if (turn) {
      return const _SwitchDecision(false, 'turn_too_sharp');
    }

    return const _SwitchDecision(true, 'ok');
  }

  bool _turnTooSharp(PositionEstimate raw, CorridorEdge targetEdge) {
    final lx = _lastRawX;
    final ly = _lastRawY;
    final lt = _lastTs;
    if (lx == null || ly == null || lt == null) return false;

    final x = raw.x;
    final y = raw.y;
    if (x == null || y == null) return false;

    final move = _dist(lx, ly, x, y);
    if (move < minMoveForTurnCheckMeters) return false;

    final vx = x - lx;
    final vy = y - ly;

    final vLen = math.sqrt(vx * vx + vy * vy);
    if (vLen <= 1e-9) return false;

    final ex = targetEdge.dx;
    final ey = targetEdge.dy;
    final eLen = math.sqrt(ex * ex + ey * ey);
    if (eLen <= 1e-9) return false;

    // Compare to both directions (edge forward/backward). Take smallest angle.
    final dot = (vx * ex + vy * ey) / (vLen * eLen);
    final dotAbs = dot.abs().clamp(-1.0, 1.0);
    final angle = math.acos(dotAbs) * 180.0 / math.pi;

    return angle > maxTurnDegrees;
  }

  // -----------------------
  // Geometry
  // -----------------------

  _NearestProjection? _nearestEdgeProjection(double x, double y) {
    _NearestProjection? best;
    for (final e in edges) {
      final p = _projectPointToSegment(x, y, e);
      if (best == null || p.distanceMeters < best.distanceMeters) {
        best = p;
      }
    }
    return best;
  }

  _NearestProjection? _nearestToSpecificEdge(
      double x, double y, String edgeId) {
    for (final e in edges) {
      if (e.id == edgeId) {
        return _projectPointToSegment(x, y, e);
      }
    }
    return null;
  }

  _NearestProjection _projectPointToSegment(
      double x, double y, CorridorEdge e) {
    final ax = e.ax;
    final ay = e.ay;
    final bx = e.bx;
    final by = e.by;

    final abx = bx - ax;
    final aby = by - ay;

    final apx = x - ax;
    final apy = y - ay;

    final ab2 = abx * abx + aby * aby;
    double t = 0.0;
    if (ab2 > 1e-12) {
      t = (apx * abx + apy * aby) / ab2;
    }
    t = t.clamp(0.0, 1.0);

    final px = ax + t * abx;
    final py = ay + t * aby;

    final d = _dist(x, y, px, py);

    return _NearestProjection(edge: e, px: px, py: py, distanceMeters: d);
  }

  void _updateMotionMemory(PositionEstimate raw) {
    final x = raw.x;
    final y = raw.y;
    if (x != null && y != null) {
      _lastRawX = x;
      _lastRawY = y;
      _lastTs = raw.timestamp;
    }
  }

  static double _dist(double ax, double ay, double bx, double by) {
    final dx = bx - ax;
    final dy = by - ay;
    return math.sqrt(dx * dx + dy * dy);
  }

  static Map<String, Set<String>> _buildAdjacency(
    List<CorridorEdge> edges, {
    required double eps,
  }) {
    final m = <String, Set<String>>{};
    for (final e in edges) {
      m[e.id] = <String>{};
    }

    bool close(double x1, double y1, double x2, double y2) =>
        _dist(x1, y1, x2, y2) <= eps;

    for (var i = 0; i < edges.length; i++) {
      for (var j = i + 1; j < edges.length; j++) {
        final a = edges[i];
        final b = edges[j];

        final adjacent = close(a.ax, a.ay, b.ax, b.ay) ||
            close(a.ax, a.ay, b.bx, b.by) ||
            close(a.bx, a.by, b.ax, b.ay) ||
            close(a.bx, a.by, b.bx, b.by);

        if (adjacent) {
          m[a.id]!.add(b.id);
          m[b.id]!.add(a.id);
        }
      }
    }

    return m;
  }
}

class _NearestProjection {
  final CorridorEdge edge;
  final double px;
  final double py;
  final double distanceMeters;

  const _NearestProjection({
    required this.edge,
    required this.px,
    required this.py,
    required this.distanceMeters,
  });
}

class _SwitchDecision {
  final bool ok;
  final String reason;
  const _SwitchDecision(this.ok, this.reason);
}
