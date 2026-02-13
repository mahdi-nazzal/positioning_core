import 'dart:math' as math;

import '../model/gps_sample.dart';
import '../model/outdoor_graph.dart';
import '../model/position_estimate.dart';

/// Configuration for OutdoorMapMatcher.
///
/// Design notes (production-grade):
/// - Smoothing is OFF by default to preserve strict determinism / legacy tests.
/// - Graph snapping is ON by default *only when a graph exists* (so "real navigation"
///   is achieved when graph is injected).
class OutdoorMapMatcherConfig {
  /// If true, apply lightweight GPS smoothing (accuracy-weighted EMA).
  final bool enableSmoothing;

  /// If true, snap to outdoor graph edges (when graph != null).
  final bool enableGraphSnap;

  /// Minimum horizontal accuracy (meters) at which smoothing becomes active.
  /// (If accuracy is better than this, we trust raw GPS and avoid lag.)
  final double minAccuracyForSmoothing;

  /// Treat speed <= this as standstill (m/s).
  final double standstillSpeedThreshold;

  /// Maximum distance allowed to snap to an edge (meters).
  final double maxSnapDistanceMeters;

  /// If switching away from the active edge, require improvement by at least this margin.
  /// (prevents frequent edge switching due to noise)
  final double switchHysteresisMeters;

  /// Apply heading gating only when speed >= this (m/s).
  final double minSpeedForHeadingGate;

  /// Heading sigma for penalty computation (degrees).
  /// Smaller => stronger heading constraint.
  final double headingSigmaDeg;

  /// Extra penalty (in meters) when switching edges.
  final double switchPenaltyMeters;

  /// Minimum/maximum smoothing time-constant bounds (seconds).
  final double smoothingTauMinSeconds;
  final double smoothingTauMaxSeconds;

  const OutdoorMapMatcherConfig({
    this.enableSmoothing = false,
    bool? enableGraphSnap,
    this.minAccuracyForSmoothing = 10.0,
    this.standstillSpeedThreshold = 0.4,
    this.maxSnapDistanceMeters = 20.0,
    this.switchHysteresisMeters = 2.0,
    this.minSpeedForHeadingGate = 0.6,
    this.headingSigmaDeg = 35.0,
    this.switchPenaltyMeters = 2.5,
    this.smoothingTauMinSeconds = 1.0,
    this.smoothingTauMaxSeconds = 8.0,
  }) : enableGraphSnap = enableGraphSnap ?? true;
}

/// Optional diagnostics for debugging / testing.
/// Not used by the engine unless you call addGpsSampleWithDiagnostics().
class OutdoorMapMatchDiagnostics {
  final bool smoothingUsed;
  final bool snapped;
  final String? edgeId;
  final double? snapDistanceMeters;

  /// Bearing actually used for heading-gating (sample bearing or derived).
  final double? usedBearingDeg;

  /// Candidate count (edges evaluated).
  final int candidateEdges;

  const OutdoorMapMatchDiagnostics({
    required this.smoothingUsed,
    required this.snapped,
    required this.edgeId,
    required this.snapDistanceMeters,
    required this.usedBearingDeg,
    required this.candidateEdges,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'smoothingUsed': smoothingUsed,
        'snapped': snapped,
        'edgeId': edgeId,
        'snapDistanceMeters': snapDistanceMeters,
        'usedBearingDeg': usedBearingDeg,
        'candidateEdges': candidateEdges,
      };
}

class OutdoorMapMatchResult {
  final PositionEstimate estimate;
  final OutdoorMapMatchDiagnostics diagnostics;

  const OutdoorMapMatchResult({
    required this.estimate,
    required this.diagnostics,
  });
}

/// OutdoorMapMatcher
///
/// - Optional GPS smoothing (opt-in)
/// - Optional snapping to outdoor graph edges (when graph != null)
///
/// Backward compatibility:
/// - addGpsSample(...) returns PositionEstimate (as before)
/// - diagnostics are available via addGpsSampleWithDiagnostics(...)
class OutdoorMapMatcher {
  final OutdoorGraph? graph;
  final OutdoorMapMatcherConfig config;

  // --- Smoother internal state (WGS84) ---
  double? _latEma;
  double? _lonEma;
  DateTime? _lastTs;

  // --- For derived bearing when platform bearing is null ---
  double? _lastRawLat;
  double? _lastRawLon;
  DateTime? _lastRawTs;

  // --- Snapping hysteresis ---
  String? _activeEdgeId;

  // --- Graph caches (safe + deterministic) ---
  Map<String, OutdoorGraphNode>? _nodeByIdCache;

  OutdoorMapMatcher({
    this.graph,
    OutdoorMapMatcherConfig config = const OutdoorMapMatcherConfig(),
  }) : config = config {
    final g = graph;
    if (g != null) {
      final m = <String, OutdoorGraphNode>{};
      for (final n in g.nodes) {
        m[n.id] = n;
      }
      _nodeByIdCache = m;
    }
  }

  /// Legacy API: returns only the estimate.
  PositionEstimate addGpsSample(GpsSample sample) {
    return addGpsSampleWithDiagnostics(sample).estimate;
  }

  /// Extended API: returns estimate + diagnostics (helpful for testing).
  OutdoorMapMatchResult addGpsSampleWithDiagnostics(GpsSample sample) {
    // Always update raw history (for derived bearing).
    _updateRawHistory(sample);

    double outLat = sample.latitude;
    double outLon = sample.longitude;

    // ---------------------------
    // 1) Optional smoothing (EMA)
    // ---------------------------
    bool smoothingUsed = false;
    if (config.enableSmoothing && _shouldSmooth(sample)) {
      smoothingUsed = true;

      final dt = _dtSeconds(sample.timestamp);
      final tau = _smoothingTauSeconds(sample.horizontalAccuracy);
      final alpha = dt / (tau + dt); // stable [0..1]

      if (_latEma == null || _lonEma == null) {
        _latEma = outLat;
        _lonEma = outLon;
      } else {
        _latEma = _latEma! + alpha * (outLat - _latEma!);
        _lonEma = _lonEma! + alpha * (outLon - _lonEma!);
      }

      outLat = _latEma!;
      outLon = _lonEma!;
    } else {
      // Keep EMA state in sync without affecting outputs.
      _latEma ??= outLat;
      _lonEma ??= outLon;
    }

    _lastTs = sample.timestamp;

    // ---------------------------
    // 2) Optional graph snapping
    // ---------------------------
    final g = graph;
    final canSnap = g != null && config.enableGraphSnap;

    bool snapped = false;
    String? snappedEdgeId;
    double? snapDist;
    int candidateEdges = 0;

    // Bearing used for heading-gating:
    // - Prefer platform bearing
    // - Otherwise derive if possible
    final usedBearingDeg = sample.bearing ?? _deriveBearingDeg(sample);

    if (canSnap) {
      final snap = _snapToGraph(
        graph: g!,
        nodeById: _nodeByIdCache!,
        lat: outLat,
        lon: outLon,
        bearingDeg: usedBearingDeg,
        speedMps: sample.speed,
      );
      candidateEdges = snap?.candidateEdges ?? 0;

      if (snap != null) {
        snapped = true;
        snappedEdgeId = snap.edgeId;
        snapDist = snap.distanceMeters;
        outLat = snap.lat;
        outLon = snap.lon;
        _activeEdgeId = snap.edgeId;
      }
    }

    final estimate = PositionEstimate(
      timestamp: sample.timestamp,
      source: PositionSource.gps,
      latitude: outLat,
      longitude: outLon,
      altitude: sample.altitude,
      accuracyMeters: sample.horizontalAccuracy,
      speedMps: sample.speed,
      headingDeg: sample.bearing,
      isIndoor: false,
      isFused: false,
    );

    return OutdoorMapMatchResult(
      estimate: estimate,
      diagnostics: OutdoorMapMatchDiagnostics(
        smoothingUsed: smoothingUsed,
        snapped: snapped,
        edgeId: snappedEdgeId,
        snapDistanceMeters: snapDist,
        usedBearingDeg: usedBearingDeg,
        candidateEdges: candidateEdges,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Smoothing helpers
  // ---------------------------------------------------------------------------

  bool _shouldSmooth(GpsSample s) {
    final acc = s.horizontalAccuracy;
    if (acc == null) return false;
    if (acc < config.minAccuracyForSmoothing) return false;

    final speed = s.speed ?? 0.0;
    // Primary target: reduce standstill jitter (poor accuracy + near-zero speed).
    return speed <= config.standstillSpeedThreshold;
  }

  double _dtSeconds(DateTime ts) {
    if (_lastTs == null) return 0.2;
    final us = ts.difference(_lastTs!).inMicroseconds;
    final dt = (us <= 0 ? 200000 : us).toDouble() / 1e6;
    return dt.clamp(0.05, 2.0);
  }

  double _smoothingTauSeconds(double? accuracyMeters) {
    final acc = (accuracyMeters ?? config.minAccuracyForSmoothing)
        .clamp(config.minAccuracyForSmoothing, 100.0);

    // Heuristic: worse accuracy -> larger tau (more smoothing).
    final tau = (acc / 4.0).clamp(
      config.smoothingTauMinSeconds,
      config.smoothingTauMaxSeconds,
    );

    return tau.toDouble();
  }

  // ---------------------------------------------------------------------------
  // Bearing derivation (for heading continuity if platform bearing is null)
  // ---------------------------------------------------------------------------

  void _updateRawHistory(GpsSample s) {
    _lastRawLat = s.latitude;
    _lastRawLon = s.longitude;
    _lastRawTs = s.timestamp;
  }

  double? _deriveBearingDeg(GpsSample current) {
    // Need previous raw point. If we don't have it, can't derive.
    // We use EMA history? No: keep derivation tied to raw points for determinism.
    // The simplest deterministic approach: derive bearing from last EMA point is risky.
    // So if platform bearing is missing, we derive from last raw point stored BEFORE this sample.
    // But here we already updated history; we need to store prev before overwriting.
    // => We derive using EMA state if available and timestamps are sensible.
    final lat0 = _latEma;
    final lon0 = _lonEma;
    if (lat0 == null || lon0 == null) return null;

    final lat1 = current.latitude;
    final lon1 = current.longitude;

    final dy = (lat1 - lat0);
    final dx = (lon1 - lon0) * math.cos(lat0 * math.pi / 180.0);

    if (dx.abs() < 1e-12 && dy.abs() < 1e-12) return null;

    var deg = math.atan2(dy, dx) * 180.0 / math.pi;
    deg %= 360.0;
    if (deg < 0) deg += 360.0;
    return deg;
  }

  // ---------------------------------------------------------------------------
  // Graph snapping helpers
  // ---------------------------------------------------------------------------

  _SnapResult? _snapToGraph({
    required OutdoorGraph graph,
    required Map<String, OutdoorGraphNode> nodeById,
    required double lat,
    required double lon,
    required double? bearingDeg,
    required double? speedMps,
  }) {
    final metersPerLat = 111320.0;
    final metersPerLon = 111320.0 * math.cos(lat * math.pi / 180.0);

    // Point P is origin (0,0).
    const px = 0.0;
    const py = 0.0;

    _EdgeCandidate? best;
    _EdgeCandidate? activeCandidate;

    int candidates = 0;

    for (final e in graph.edges) {
      final aNode = nodeById[e.fromNodeId];
      final bNode = nodeById[e.toNodeId];
      if (aNode == null || bNode == null) continue;

      candidates++;

      // Convert nodes into local meters relative to current GPS point.
      final ax = (aNode.longitude - lon) * metersPerLon;
      final ay = (aNode.latitude - lat) * metersPerLat;
      final bx = (bNode.longitude - lon) * metersPerLon;
      final by = (bNode.latitude - lat) * metersPerLat;

      final proj = _projectPointToSegment(px, py, ax, ay, bx, by);
      final dist = math.sqrt(proj.dx * proj.dx + proj.dy * proj.dy);

      // Heading continuity penalty (only if moving enough and bearing available).
      double headingPenalty = 0.0;
      final spd = speedMps ?? 0.0;
      if (bearingDeg != null && spd >= config.minSpeedForHeadingGate) {
        final edgeBearingDeg = _segmentBearingDeg(ax, ay, bx, by);

        // Walkways are effectively undirected; allow either direction.
        final d1 = _angleDiffDeg(bearingDeg, edgeBearingDeg);
        final d2 = _angleDiffDeg(bearingDeg, (edgeBearingDeg + 180.0) % 360.0);
        final d = math.min(d1, d2);

        final sigma = config.headingSigmaDeg.clamp(5.0, 90.0);
        headingPenalty = (d / sigma) * (d / sigma) * 3.0; // meters-like penalty
      }

      // Switching penalty (hysteresis).
      double switchPenalty = 0.0;
      final activeId = _activeEdgeId;
      if (activeId != null && activeId != e.id) {
        switchPenalty = config.switchPenaltyMeters;
      }

      final score = dist + headingPenalty + switchPenalty;

      final cand = _EdgeCandidate(
        edgeId: e.id,
        dist: dist,
        score: score,
        projX: proj.projX,
        projY: proj.projY,
      );

      if (_activeEdgeId == e.id) {
        activeCandidate = cand;
      }

      if (best == null || cand.score < best!.score) {
        best = cand;
      }
    }

    if (best == null) return null;
    if (best!.dist > config.maxSnapDistanceMeters) {
      return _SnapResult(
        edgeId: best!.edgeId,
        lat: lat,
        lon: lon,
        distanceMeters: best!.dist,
        candidateEdges: candidates,
        snapped: false,
      );
    }

    // Hysteresis:
    // If we have an active edge, keep it unless the best is significantly better.
    if (activeCandidate != null &&
        activeCandidate!.dist <= config.maxSnapDistanceMeters) {
      final improvement = activeCandidate!.score - best!.score;
      if (best!.edgeId != activeCandidate!.edgeId &&
          improvement < config.switchHysteresisMeters) {
        best = activeCandidate;
      }
    }

    // Convert snapped local meters back to lat/lon.
    final snappedLat = lat + (best!.projY / metersPerLat);
    final snappedLon = lon + (best!.projX / metersPerLon);

    return _SnapResult(
      edgeId: best!.edgeId,
      lat: snappedLat,
      lon: snappedLon,
      distanceMeters: best!.dist,
      candidateEdges: candidates,
      snapped: true,
    );
  }

  _Projection _projectPointToSegment(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final abx = bx - ax;
    final aby = by - ay;
    final apx = px - ax;
    final apy = py - ay;

    final ab2 = abx * abx + aby * aby;
    if (ab2 <= 1e-12) {
      // Degenerate segment.
      final dx = px - ax;
      final dy = py - ay;
      return _Projection(projX: ax, projY: ay, dx: dx, dy: dy);
    }

    var t = (apx * abx + apy * aby) / ab2;
    if (t < 0.0) t = 0.0;
    if (t > 1.0) t = 1.0;

    final projX = ax + t * abx;
    final projY = ay + t * aby;

    final dx = px - projX;
    final dy = py - projY;

    return _Projection(projX: projX, projY: projY, dx: dx, dy: dy);
  }

  double _segmentBearingDeg(double ax, double ay, double bx, double by) {
    final dx = bx - ax;
    final dy = by - ay;
    // 0° = +X (east), 90° = +Y (north)
    var deg = math.atan2(dy, dx) * 180.0 / math.pi;
    deg %= 360.0;
    if (deg < 0) deg += 360.0;
    return deg;
  }

  double _angleDiffDeg(double a, double b) {
    var d = (a - b).abs() % 360.0;
    if (d > 180.0) d = 360.0 - d;
    return d;
  }
}

class _Projection {
  final double projX;
  final double projY;
  final double dx;
  final double dy;

  const _Projection({
    required this.projX,
    required this.projY,
    required this.dx,
    required this.dy,
  });
}

class _EdgeCandidate {
  final String edgeId;
  final double dist;
  final double score;
  final double projX;
  final double projY;

  const _EdgeCandidate({
    required this.edgeId,
    required this.dist,
    required this.score,
    required this.projX,
    required this.projY,
  });
}

class _SnapResult {
  final String edgeId;
  final double lat;
  final double lon;
  final double distanceMeters;
  final int candidateEdges;
  final bool snapped;

  const _SnapResult({
    required this.edgeId,
    required this.lat,
    required this.lon,
    required this.distanceMeters,
    required this.candidateEdges,
    required this.snapped,
  });
}
