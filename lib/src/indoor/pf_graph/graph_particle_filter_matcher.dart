import 'dart:math' as math;

import '../../model/position_estimate.dart';
import '../indoor_map_matcher.dart';
import '../corridor_edge.dart';
import '../graph/indoor_graph_index.dart';
import 'graph_particle.dart';
import 'graph_pf_config.dart';
import 'systematic_resampler.dart';

class GraphParticleFilterIndoorMatcher implements IndoorMapMatcher {
  final List<CorridorEdge> edges;
  final GraphParticleFilterConfig config;
  final int seed;

  late final math.Random _rng;
  late final IndoorGraphIndex _index;

  List<GraphParticle> _ps = <GraphParticle>[];

  double? _lastRawX;
  double? _lastRawY;

  GraphParticleFilterIndoorMatcher({
    required this.edges,
    GraphParticleFilterConfig? config,
    this.seed = 2026,
  }) : config = config ??
            GraphParticleFilterConfig.forMode(
                GraphParticleFilterMode.balanced) {
    _rng = math.Random(seed);
    _index = IndoorGraphIndex(edges: edges, epsMeters: this.config.epsMeters);
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
          activeEdgeId: null,
          decision: 'none',
          switchReason: 'missing_xy_or_no_edges',
          extra: <String, dynamic>{
            'pf_graph': true,
            'mode': config.mode.toString(),
            'n': config.numParticles,
          },
        ),
      );
    }

    // init
    if (_ps.isEmpty) {
      _init(raw);
      _rememberRaw(raw);

      final res = _estimate(raw);
      return res;
    }

    // compute motion magnitude from raw (controller supplies per-step updates).
    final dx = (_lastRawX == null) ? 0.0 : x - _lastRawX!;
    final dy = (_lastRawY == null) ? 0.0 : y - _lastRawY!;
    final ds = math.sqrt(dx * dx + dy * dy);

    // If ds is tiny, we still update weights (observation), but avoid transitions.
    final dsEff = (ds < config.minMoveMeters) ? 0.0 : ds;

    final headingObsRad = _headingObsRad(raw);

    // Propagate + weight
    double wSum = 0.0;
    for (final p in _ps) {
      _propagateOne(p, dsEff, headingObsRad);

      final particleXY = _index.pointOnEdge(p.edgeId, p.t);
      final dObs = _dist(x, y, particleXY.x, particleXY.y);

      // observation likelihood (distance from raw to particle)
      final sigma = config.obsSigmaMeters;
      final like = math.exp(-0.5 * (dObs * dObs) / (sigma * sigma));

      // optional heading agreement weight (soft)
      double headW = 1.0;
      if (headingObsRad != null) {
        final edgeAngle = _index.edgeAngleRad(p.edgeId);
        final dirAngle =
            (p.dir >= 0) ? edgeAngle : _wrapPi(edgeAngle + math.pi);
        final dAng = _angleDiffRad(headingObsRad, dirAngle);
        final s = _degToRad(config.headingSigmaDeg).clamp(1e-6, 10.0);
        headW = math.exp(-0.5 * (dAng * dAng) / (s * s));
      }

      p.w = (like * headW).clamp(1e-15, 1.0);
      wSum += p.w;
    }

    // normalize
    if (wSum <= 0) {
      final u = 1.0 / _ps.length;
      for (final p in _ps) {
        p.w = u;
      }
    } else {
      for (final p in _ps) {
        p.w = p.w / wSum;
      }
    }

    // resample
    final ess = _effectiveSampleSize(_ps);
    final essFrac = (_ps.isEmpty) ? 0.0 : (ess / _ps.length).clamp(0.0, 1.0);

    if (essFrac < config.essThresholdFraction) {
      _ps = systematicResample(_ps, _rng);
    }

    final out = _estimate(raw, ess: ess, essFrac: essFrac);
    _rememberRaw(raw);
    return out;
  }

  @override
  void reset() {
    _ps = <GraphParticle>[];
    _lastRawX = null;
    _lastRawY = null;
  }

  // -------------------------
  // Init
  // -------------------------

  void _init(PositionEstimate raw) {
    final x = raw.x!;
    final y = raw.y!;
    final proj = _index.nearestProjection(x, y);

    final baseEdge = proj.edgeId;
    final baseT = proj.t;

    final headingObs = _headingObsRad(raw);
    final baseDir =
        _chooseDirForEdge(baseEdge, headingObs, lastDx: null, lastDy: null);

    final n = config.numParticles;
    _ps = List<GraphParticle>.generate(n, (_) {
      // init spread mainly in t (along-edge), not off-edge
      final len = _index.edgeLength(baseEdge).clamp(1e-6, 1e9);
      final tNoise = (_randNormal(0.0, config.stepSigmaMeters) / len);
      final t = (baseT + tNoise).clamp(0.0, 1.0);

      return GraphParticle(
        edgeId: baseEdge,
        t: t,
        dir: baseDir,
        w: 1.0 / n,
      );
    });

    // If near endpoint and heading exists, sprinkle some particles on incident edges.
    final nearA = baseT < 0.08;
    final nearB = baseT > 0.92;

    if ((nearA || nearB) && headingObs != null) {
      final node = nearA ? _index.nodeA(baseEdge) : _index.nodeB(baseEdge);
      final inc = _index.incidentEdges(node);
      if (inc.length >= 2) {
        // replace a small portion with branched initialization
        final k = (n * 0.20).round().clamp(1, n);
        for (int i = 0; i < k; i++) {
          final chosen = _sampleNextEdgeAtNode(
            node: node,
            currentEdge: baseEdge,
            headingObsRad: headingObs,
          );

          final edgeId = chosen.edgeId;
          final startT = chosen.startT;
          final dir = chosen.dir;

          _ps[i] = GraphParticle(
            edgeId: edgeId,
            t: startT,
            dir: dir,
            w: 1.0 / n,
          );
        }
      }
    }
  }

  // -------------------------
  // Propagation (graph-param)
  // -------------------------

  void _propagateOne(GraphParticle p, double dsMeters, double? headingObsRad) {
    // add distance noise
    final ds = (dsMeters <= 0.0)
        ? 0.0
        : (dsMeters + _randNormal(0.0, config.stepSigmaMeters))
            .clamp(0.0, 10.0);

    // choose direction using heading (or fallback to prior dir)
    final chosenDir =
        _chooseDirForEdge(p.edgeId, headingObsRad, lastDx: null, lastDy: null);
    p.dir = chosenDir;

    if (ds <= 0.0) return;

    double remaining = ds;
    int hops = 0;

    while (remaining > 1e-9 && hops < config.maxHopsPerUpdate) {
      hops++;

      final len = _index.edgeLength(p.edgeId).clamp(1e-6, 1e9);
      final dt = (remaining / len);

      final nextT = p.t + p.dir * dt;

      if (nextT >= 0.0 && nextT <= 1.0) {
        p.t = nextT;
        remaining = 0.0;
        break;
      }

      // crossed endpoint: compute leftover after reaching endpoint
      if (nextT < 0.0) {
        // hit A endpoint
        final used = p.t * len; // distance from A to current point
        remaining = (remaining - used).clamp(0.0, 1e9);
        p.t = 0.0;

        final node = _index.nodeA(p.edgeId);
        final next = _sampleNextEdgeAtNode(
          node: node,
          currentEdge: p.edgeId,
          headingObsRad: headingObsRad,
          forceUTurnIfDeadEnd: true,
        );

        p.edgeId = next.edgeId;
        p.t = next.startT;
        p.dir = next.dir;

        continue;
      } else {
        // nextT > 1.0 => hit B endpoint
        final used = (1.0 - p.t) * len; // distance to B endpoint
        remaining = (remaining - used).clamp(0.0, 1e9);
        p.t = 1.0;

        final node = _index.nodeB(p.edgeId);
        final next = _sampleNextEdgeAtNode(
          node: node,
          currentEdge: p.edgeId,
          headingObsRad: headingObsRad,
          forceUTurnIfDeadEnd: true,
        );

        p.edgeId = next.edgeId;
        p.t = next.startT;
        p.dir = next.dir;

        continue;
      }
    }
  }

  _NextChoice _sampleNextEdgeAtNode({
    required String node,
    required String currentEdge,
    required double? headingObsRad,
    bool forceUTurnIfDeadEnd = false,
  }) {
    final inc = _index.incidentEdges(node);

    // If dead-end, either u-turn or stay.
    if (inc.isEmpty || (inc.length == 1 && inc.first == currentEdge)) {
      if (forceUTurnIfDeadEnd && config.allowUTurn) {
        // U-turn on current edge
        final isA = (_index.nodeA(currentEdge) == node);
        return _NextChoice(
          edgeId: currentEdge,
          startT: isA ? 0.0 : 1.0,
          dir: isA ? 1 : -1, // away from node
        );
      }
      // fallback: stay
      final isA = (_index.nodeA(currentEdge) == node);
      return _NextChoice(
        edgeId: currentEdge,
        startT: isA ? 0.0 : 1.0,
        dir: isA ? 1 : -1,
      );
    }

    // Candidate set: all incident edges, optionally excluding currentEdge if u-turn disabled.
    final candidates = <String>[];
    for (final e in inc) {
      if (e == currentEdge && !config.allowUTurn) continue;
      candidates.add(e);
    }
    if (candidates.isEmpty) {
      candidates.add(currentEdge);
    }

    // If no heading, choose uniformly.
    if (headingObsRad == null) {
      final chosen = candidates[_rng.nextInt(candidates.length)];
      final isA = (_index.nodeA(chosen) == node);
      return _NextChoice(
        edgeId: chosen,
        startT: isA ? 0.0 : 1.0,
        dir: isA ? 1 : -1,
      );
    }

    // Heading-based branching
    final sigma = _degToRad(config.headingSigmaDeg).clamp(1e-6, 10.0);

    final weights = <double>[];
    double sum = 0.0;

    for (final e in candidates) {
      final ang = _index.leavingAngleFromNodeRad(e, node);
      final dAng = _angleDiffRad(headingObsRad, ang);
      var w = math.exp(-0.5 * (dAng * dAng) / (sigma * sigma));

      // penalize u-turn choice (same edge) softly
      if (e == currentEdge) {
        w *= config.uTurnPenalty;
      }

      w = w.clamp(1e-12, 1.0);
      weights.add(w);
      sum += w;
    }

    if (sum <= 0.0) {
      final chosen = candidates[_rng.nextInt(candidates.length)];
      final isA = (_index.nodeA(chosen) == node);
      return _NextChoice(
          edgeId: chosen, startT: isA ? 0.0 : 1.0, dir: isA ? 1 : -1);
    }

    // sample categorical
    final r = _rng.nextDouble() * sum;
    double c = 0.0;
    int idx = 0;
    for (; idx < candidates.length; idx++) {
      c += weights[idx];
      if (r <= c) break;
    }
    idx = idx.clamp(0, candidates.length - 1);

    final chosen = candidates[idx];
    final isA = (_index.nodeA(chosen) == node);
    return _NextChoice(
      edgeId: chosen,
      startT: isA ? 0.0 : 1.0,
      dir: isA ? 1 : -1,
    );
  }

  int _chooseDirForEdge(String edgeId, double? headingObsRad,
      {double? lastDx, double? lastDy}) {
    // if heading known: choose direction along edge that matches heading
    if (headingObsRad != null) {
      final a = _index.edgeAngleRad(edgeId);
      final df = _angleDiffRad(headingObsRad, a);
      final db = _angleDiffRad(headingObsRad, _wrapPi(a + math.pi));
      return (df <= db) ? 1 : -1;
    }
    // fallback: keep direction positive
    return 1;
  }

  // -------------------------
  // Estimate + confidence
  // -------------------------

  IndoorMapMatchResult _estimate(PositionEstimate raw,
      {double? ess, double? essFrac}) {
    final x = raw.x!;
    final y = raw.y!;

    // sum weight per edge
    final edgeMass = <String, double>{};
    for (final p in _ps) {
      edgeMass[p.edgeId] = (edgeMass[p.edgeId] ?? 0.0) + p.w;
    }

    // best edge
    String bestEdge = _ps.first.edgeId;
    double bestMass = -1.0;

    edgeMass.forEach((k, v) {
      if (v > bestMass) {
        bestMass = v;
        bestEdge = k;
      }
    });

    final bestProb = bestMass.clamp(0.0, 1.0);

    // mean t on best edge
    double tw = 0.0;
    double w = 0.0;
    for (final p in _ps) {
      if (p.edgeId != bestEdge) continue;
      tw += p.w * p.t;
      w += p.w;
    }
    final tMean = (w <= 1e-12) ? 0.5 : (tw / w).clamp(0.0, 1.0);
    final pt = _index.pointOnEdge(bestEdge, tMean);

    // output distance from raw (diagnostic)
    final dObs = _dist(x, y, pt.x, pt.y);

    // ESS confidence
    final essVal = ess ?? _effectiveSampleSize(_ps);
    final essF = essFrac ??
        ((_ps.isEmpty) ? 0.0 : (essVal / _ps.length).clamp(0.0, 1.0));

    // confidence: edge dominance * ESS fraction
    final confidence = (bestProb * essF).clamp(0.0, 1.0);

    final ambiguous = (bestProb < config.edgeDominanceThreshold) ||
        (confidence < config.confidenceThreshold);

    // top edges (for UI/diagnostics)
    final top = edgeMass.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topEdges = top
        .take(3)
        .map((e) => <String, dynamic>{'edgeId': e.key, 'prob': e.value})
        .toList();

    final heading = raw
        .headingDeg; // keep raw heading; you can switch to edge-based if you want.

    final est = raw.copyWith(
      x: pt.x,
      y: pt.y,
      headingDeg: heading,
    );

    return IndoorMapMatchResult(
      estimate: est,
      diagnostics: IndoorSnapDiagnostics(
        snapped: true,
        rawX: x,
        rawY: y,
        outX: pt.x,
        outY: pt.y,
        snapDistanceMeters: dObs,
        activeEdgeId: bestEdge,
        decision: 'pf_graph',
        switchReason: ambiguous ? 'ambiguous' : null,
        extra: <String, dynamic>{
          'pf_graph': true,
          'mode': config.mode.toString(),
          'n': config.numParticles,
          'ess': essVal,
          'essFrac': essF,
          'bestEdgeProb': bestProb,
          'confidence': confidence,
          'ambiguous': ambiguous,
          'topEdges': topEdges,
        },
      ),
    );
  }

  void _rememberRaw(PositionEstimate raw) {
    _lastRawX = raw.x;
    _lastRawY = raw.y;
  }

  // -------------------------
  // Math helpers
  // -------------------------

  double _effectiveSampleSize(List<GraphParticle> ps) {
    double s = 0.0;
    for (final p in ps) {
      s += p.w * p.w;
    }
    if (s <= 1e-15) return 0.0;
    return 1.0 / s;
  }

  double _randNormal(double mean, double std) {
    final u1 = (_rng.nextDouble()).clamp(1e-12, 1.0);
    final u2 = _rng.nextDouble();
    final z0 = math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2);
    return mean + z0 * std;
  }

  double? _headingObsRad(PositionEstimate raw) {
    final hd = raw.headingDeg;
    if (hd == null) return null;
    return _degToRad(hd);
  }

  static double _degToRad(double d) => d * math.pi / 180.0;

  static double _dist(double ax, double ay, double bx, double by) {
    final dx = bx - ax;
    final dy = by - ay;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _wrapPi(double a) {
    while (a <= -math.pi) a += 2 * math.pi;
    while (a > math.pi) a -= 2 * math.pi;
    return a;
  }

  static double _angleDiffRad(double a, double b) {
    var d = _wrapPi(a - b);
    if (d < 0) d = -d;
    return d;
  }
}

class _NextChoice {
  final String edgeId;
  final double startT;
  final int dir; // away from node (+1 from A, -1 from B)

  const _NextChoice({
    required this.edgeId,
    required this.startT,
    required this.dir,
  });
}
