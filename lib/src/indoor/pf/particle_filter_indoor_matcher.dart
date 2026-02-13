import 'dart:math' as math;

import '../../model/position_estimate.dart';
import '../corridor_edge.dart';
import '../indoor_map_matcher.dart';
import 'particle.dart';
import 'particle_filter_config.dart';
import 'systematic_resampler.dart';

class ParticleFilterIndoorMatcher implements IndoorMapMatcher {
  final List<CorridorEdge> edges;
  final ParticleFilterConfig config;

  /// Seed controls determinism for replay/testing.
  final int seed;

  late final math.Random _rng;

  List<Particle> _particles = <Particle>[];
  String? _activeEdgeId;

  double? _lastRawX;
  double? _lastRawY;
  DateTime? _lastTs;

  late final Map<String, Set<String>> _adj;

  ParticleFilterIndoorMatcher({
    required this.edges,
    ParticleFilterConfig? config,
    this.seed = 1337,
  }) : config = config ??
            ParticleFilterConfig.forMode(ParticleFilterMode.balanced) {
    _rng = math.Random(seed);
    _adj = _buildAdjacency(edges, eps: this.config.adjacencyEpsMeters);
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
          extra: <String, dynamic>{
            'pf': true,
            'mode': config.mode.toString(),
            'n': config.numParticles,
          },
        ),
      );
    }

    // Initialize if needed.
    if (_particles.isEmpty) {
      _initParticlesAround(raw);
      _rememberRaw(raw);

      final best = _bestEstimate(raw, snapped: config.snapOutputToCorridor);
      return IndoorMapMatchResult(
        estimate: best.estimate,
        diagnostics: best.diagnostics,
      );
    }

    final dx = (_lastRawX == null) ? 0.0 : x - _lastRawX!;
    final dy = (_lastRawY == null) ? 0.0 : y - _lastRawY!;
    final moveDist = math.sqrt(dx * dx + dy * dy);

    final headingObsRad = _headingObsRad(raw);

    // 1) Propagate
    for (final p in _particles) {
      final nx = _randNormal(0.0, config.stepNoiseSigmaMeters);
      final ny = _randNormal(0.0, config.stepNoiseSigmaMeters);

      p.x += dx + nx;
      p.y += dy + ny;

      if (headingObsRad != null) {
        final hn = _degToRad(_randNormal(0.0, config.headingNoiseSigmaDeg));
        p.headingRad = _wrapPi(headingObsRad + hn);
      }
    }

    // 2) Weight
    double wSum = 0.0;
    for (final p in _particles) {
      final proj = _nearestEdgeProjection(p.x, p.y);
      if (proj == null) {
        p.w = 1e-12;
        continue;
      }

      // corridor proximity likelihood
      final d = proj.distanceMeters;
      final sigma = config.corridorSigmaMeters;
      final like = math.exp(-0.5 * (d * d) / (sigma * sigma));

      double w = like;

      // feasibility penalties when edge changes
      final prevEdge = p.edgeId ?? _activeEdgeId;
      if (prevEdge != null && prevEdge != proj.edge.id) {
        final adjacent = _adj[prevEdge]?.contains(proj.edge.id) ?? false;

        if (!adjacent) {
          w *= config.nonAdjacentPenalty;
        }

        // jump penalty (relative to last raw)
        if (_lastRawX != null && _lastRawY != null) {
          final jump = _dist(_lastRawX!, _lastRawY!, proj.px, proj.py);
          if (jump > config.maxSnapJumpMeters) {
            w *= config.jumpPenalty;
          }
        }

        // sharp turn penalty (motion direction vs candidate edge)
        if (moveDist >= config.minMoveForTurnCheckMeters) {
          final angle = _angleBetweenVectors(
            dx,
            dy,
            proj.edge.dx,
            proj.edge.dy,
          );
          if (angle > config.maxTurnDegrees) {
            w *= config.turnPenalty;
          }
        }
      }

      p.edgeId = proj.edge.id;
      p.w = (w <= 1e-15) ? 1e-15 : w;
      wSum += p.w;
    }

    // Normalize
    if (wSum <= 0) {
      final u = 1.0 / _particles.length;
      for (final p in _particles) {
        p.w = u;
      }
    } else {
      for (final p in _particles) {
        p.w = p.w / wSum;
      }
    }

    // 3) ESS + resample
    final ess = _effectiveSampleSize(_particles);
    final n = _particles.length;
    final essFrac = (n == 0) ? 0.0 : ess / n;

    if (essFrac < config.essThresholdFraction) {
      _particles = systematicResample(_particles, _rng);
    }

    // 4) Best estimate + diagnostics
    final best = _bestEstimate(raw,
        snapped: config.snapOutputToCorridor, ess: ess, essFrac: essFrac);
    _rememberRaw(raw);

    // Track a “global” active edge for debug/UX.
    _activeEdgeId = best.diagnostics.activeEdgeId;

    return IndoorMapMatchResult(
      estimate: best.estimate,
      diagnostics: best.diagnostics,
    );
  }

  @override
  void reset() {
    _particles = <Particle>[];
    _activeEdgeId = null;
    _lastRawX = null;
    _lastRawY = null;
    _lastTs = null;
  }

  // -------------------------
  // Internals
  // -------------------------

  void _initParticlesAround(PositionEstimate raw) {
    final x = raw.x!;
    final y = raw.y!;
    final headingRad = _headingObsRad(raw) ?? 0.0;

    final n = config.numParticles;
    _particles = List<Particle>.generate(n, (_) {
      // slightly larger init noise so PF can represent ambiguity at intersections
      final ix = x + _randNormal(0.0, config.stepNoiseSigmaMeters * 2.0);
      final iy = y + _randNormal(0.0, config.stepNoiseSigmaMeters * 2.0);
      final ih = _wrapPi(headingRad +
          _degToRad(_randNormal(0.0, config.headingNoiseSigmaDeg * 2.0)));

      final proj = _nearestEdgeProjection(ix, iy);
      final edgeId = proj?.edge.id;

      return Particle(
        x: ix,
        y: iy,
        headingRad: ih,
        w: 1.0 / n,
        edgeId: edgeId,
      );
    });
  }

  _Best _bestEstimate(
    PositionEstimate raw, {
    required bool snapped,
    double? ess,
    double? essFrac,
  }) {
    final x = raw.x!;
    final y = raw.y!;

    // Weighted mean for position
    double mx = 0.0;
    double my = 0.0;

    // Circular mean for heading
    double sumSin = 0.0;
    double sumCos = 0.0;

    // Find best particle for activeEdgeId (highest weight)
    Particle bestP = _particles.first;
    for (final p in _particles) {
      mx += p.w * p.x;
      my += p.w * p.y;
      sumSin += p.w * math.sin(p.headingRad);
      sumCos += p.w * math.cos(p.headingRad);
      if (p.w > bestP.w) bestP = p;
    }

    final mh = (sumSin.abs() < 1e-12 && sumCos.abs() < 1e-12)
        ? null
        : _wrapPi(math.atan2(sumSin, sumCos));

    double outX = mx;
    double outY = my;

    String? activeEdgeId = bestP.edgeId;
    double snapDist = 0.0;
    bool didSnap = false;

    if (snapped) {
      final proj = _nearestEdgeProjection(outX, outY);
      if (proj != null) {
        outX = proj.px;
        outY = proj.py;
        snapDist = proj.distanceMeters;
        didSnap = true;
        activeEdgeId = proj.edge.id;
      }
    } else {
      // still compute distance for diagnostics
      final proj = _nearestEdgeProjection(outX, outY);
      if (proj != null) {
        snapDist = proj.distanceMeters;
        activeEdgeId ??= proj.edge.id;
      }
    }

    // Confidence (ESS-based)
    final n = _particles.length;
    final ef =
        (essFrac ?? (n == 0 ? 0.0 : _effectiveSampleSize(_particles) / n))
            .clamp(0.0, 1.0);

    final ambiguous = ef < config.ambiguityThreshold;

    final headingDeg = (mh == null) ? raw.headingDeg : (_radToDeg(mh) % 360.0);

    final est = raw.copyWith(
      x: outX,
      y: outY,
      headingDeg: headingDeg,
    );

    final diag = IndoorSnapDiagnostics(
      snapped: didSnap,
      rawX: x,
      rawY: y,
      outX: outX,
      outY: outY,
      snapDistanceMeters: snapDist,
      activeEdgeId: activeEdgeId,
      decision: didSnap ? 'hold' : 'none',
      switchReason: null,
      extra: <String, dynamic>{
        'pf': true,
        'mode': config.mode.toString(),
        'n': config.numParticles,
        'ess': ess ?? _effectiveSampleSize(_particles),
        'essFrac': ef,
        'ambiguous': ambiguous,
      },
    );

    return _Best(est, diag);
  }

  void _rememberRaw(PositionEstimate raw) {
    _lastRawX = raw.x;
    _lastRawY = raw.y;
    _lastTs = raw.timestamp;
  }

  double? _headingObsRad(PositionEstimate raw) {
    final hd = raw.headingDeg;
    if (hd == null) return null;
    return _degToRad(hd);
  }

  // -------------------------
  // Geometry / projection
  // -------------------------

  _Proj? _nearestEdgeProjection(double x, double y) {
    _Proj? best;
    for (final e in edges) {
      final p = _projectPointToSegment(x, y, e);
      if (best == null || p.distanceMeters < best.distanceMeters) {
        best = p;
      }
    }
    return best;
  }

  _Proj _projectPointToSegment(double x, double y, CorridorEdge e) {
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

    return _Proj(edge: e, px: px, py: py, distanceMeters: d);
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

  static double _dist(double ax, double ay, double bx, double by) {
    final dx = bx - ax;
    final dy = by - ay;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _angleBetweenVectors(
      double ax, double ay, double bx, double by) {
    final aLen = math.sqrt(ax * ax + ay * ay);
    final bLen = math.sqrt(bx * bx + by * by);
    if (aLen <= 1e-9 || bLen <= 1e-9) return 0.0;

    final dot = (ax * bx + ay * by) / (aLen * bLen);
    final d = dot.abs().clamp(-1.0, 1.0);
    return math.acos(d) * 180.0 / math.pi;
  }

  // -------------------------
  // Math helpers
  // -------------------------

  double _effectiveSampleSize(List<Particle> ps) {
    double s = 0.0;
    for (final p in ps) {
      s += p.w * p.w;
    }
    if (s <= 1e-15) return 0.0;
    return 1.0 / s;
  }

  double _randNormal(double mean, double std) {
    // Box-Muller
    final u1 = (_rng.nextDouble()).clamp(1e-12, 1.0);
    final u2 = _rng.nextDouble();
    final z0 = math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2);
    return mean + z0 * std;
  }

  static double _wrapPi(double a) {
    while (a <= -math.pi) a += 2 * math.pi;
    while (a > math.pi) a -= 2 * math.pi;
    return a;
  }

  static double _degToRad(double deg) => deg * math.pi / 180.0;
  static double _radToDeg(double rad) => rad * 180.0 / math.pi;
}

class _Proj {
  final CorridorEdge edge;
  final double px;
  final double py;
  final double distanceMeters;

  const _Proj({
    required this.edge,
    required this.px,
    required this.py,
    required this.distanceMeters,
  });
}

class _Best {
  final PositionEstimate estimate;
  final IndoorSnapDiagnostics diagnostics;
  const _Best(this.estimate, this.diagnostics);
}
