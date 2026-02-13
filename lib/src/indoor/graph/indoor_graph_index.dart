import 'dart:math' as math;

import '../corridor_edge.dart';

class IndoorGraphIndex {
  final List<CorridorEdge> edges;
  final double epsMeters;

  final Map<String, CorridorEdge> edgesById = <String, CorridorEdge>{};

  // edgeId -> endpoints node keys
  final Map<String, _EdgeEnds> _ends = <String, _EdgeEnds>{};

  // nodeKey -> incident edges (edgeId)
  final Map<String, List<String>> _incidents = <String, List<String>>{};

  // edgeId -> neighbor edgeIds
  final Map<String, Set<String>> adjacency = <String, Set<String>>{};

  IndoorGraphIndex({
    required this.edges,
    this.epsMeters = 0.35,
  }) {
    for (final e in edges) {
      edgesById[e.id] = e;
      adjacency[e.id] = <String>{};
    }
    _buildNodesAndIncidents();
    _buildAdjacency();
  }

  String nodeKeyFor(double x, double y) {
    final gx = (x / epsMeters).round();
    final gy = (y / epsMeters).round();
    return '$gx:$gy';
  }

  String nodeA(String edgeId) => _ends[edgeId]!.a;
  String nodeB(String edgeId) => _ends[edgeId]!.b;

  List<String> incidentEdges(String nodeKey) =>
      _incidents[nodeKey] ?? const <String>[];

  bool areAdjacent(String edgeA, String edgeB) =>
      adjacency[edgeA]?.contains(edgeB) ?? false;

  /// Edge angle for A->B direction.
  double edgeAngleRad(String edgeId) {
    final e = edgesById[edgeId]!;
    return math.atan2(e.by - e.ay, e.bx - e.ax);
  }

  double edgeLength(String edgeId) => edgesById[edgeId]!.length;

  /// Public point type (no private type leak).
  GraphPoint pointOnEdge(String edgeId, double t) {
    final e = edgesById[edgeId]!;
    final tt = t.clamp(0.0, 1.0);
    return GraphPoint(
      e.ax + (e.bx - e.ax) * tt,
      e.ay + (e.by - e.ay) * tt,
    );
  }

  /// Returns leaving angle from a node along an edge (away from that node).
  /// If node is A, leaving direction is A->B; if node is B, leaving is B->A.
  double leavingAngleFromNodeRad(String edgeId, String nodeKey) {
    final a = nodeA(edgeId);
    final base = edgeAngleRad(edgeId);
    if (nodeKey == a) return base;
    return _wrapPi(base + math.pi);
  }

  /// Nearest projection (used only for initialization + optional diagnostics).
  EdgeProjection nearestProjection(double x, double y) {
    EdgeProjection? best;

    for (final e in edges) {
      final p = _projectPointToSegment(x, y, e);
      if (best == null || p.distanceMeters < best.distanceMeters) best = p;
    }

    return best!;
  }

  EdgeProjection _projectPointToSegment(double x, double y, CorridorEdge e) {
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

    return EdgeProjection(
      edgeId: e.id,
      t: t,
      px: px,
      py: py,
      distanceMeters: d,
    );
  }

  void _buildNodesAndIncidents() {
    for (final e in edges) {
      final na = nodeKeyFor(e.ax, e.ay);
      final nb = nodeKeyFor(e.bx, e.by);

      _ends[e.id] = _EdgeEnds(a: na, b: nb);

      _incidents.putIfAbsent(na, () => <String>[]).add(e.id);
      _incidents.putIfAbsent(nb, () => <String>[]).add(e.id);
    }
  }

  void _buildAdjacency() {
    for (final entry in _incidents.entries) {
      final list = entry.value;
      for (int i = 0; i < list.length; i++) {
        for (int j = i + 1; j < list.length; j++) {
          final a = list[i];
          final b = list[j];
          adjacency[a]!.add(b);
          adjacency[b]!.add(a);
        }
      }
    }
  }

  static double _dist(double ax, double ay, double bx, double by) {
    final dx = bx - ax;
    final dy = by - ay;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _wrapPi(double a) {
    while (a <= -math.pi) {
      a += 2 * math.pi;
    }
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    return a;
  }
}

class GraphPoint {
  final double x;
  final double y;
  const GraphPoint(this.x, this.y);
}

class EdgeProjection {
  final String edgeId;
  final double t;
  final double px;
  final double py;
  final double distanceMeters;

  const EdgeProjection({
    required this.edgeId,
    required this.t,
    required this.px,
    required this.py,
    required this.distanceMeters,
  });
}

class _EdgeEnds {
  final String a;
  final String b;
  const _EdgeEnds({required this.a, required this.b});
}
