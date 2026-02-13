//positioning_core\lib\src\engine\positioning_controller.dart
import 'dart:async';
import 'dart:math' as math;

import '../floor/floor_change_detector.dart';
import '../fusion/confidence_fuser.dart';
import '../indoor/indoor_level_switcher.dart';
import '../indoor/indoor_map_matcher.dart';
import '../indoor/transitions/transition_snapper.dart';
import '../logging/positioning_logger.dart';
import '../model/barometer_sample.dart';
import '../model/fusion_config.dart';
import '../model/gps_sample.dart';
import '../model/imu_sample.dart';
import '../model/position_estimate.dart';
import '../model/positioning_event.dart';
import 'indoor_pdr_engine.dart';
import 'outdoor_map_matcher.dart';

enum EnvironmentMode {
  unknown,
  outdoor,
  indoor,
}

class PositioningController {
  final IndoorPdrEngine _pdrEngine;
  final OutdoorMapMatcher _mapMatcher;
  final FusionConfig _config;
  final PositioningLogger? _logger;

  final IndoorMapMatcher? _indoorMapMatcher;
  final void Function(IndoorMapMatchResult result)? _onIndoorMatch;

  final FloorChangeDetector? _floorDetector;
  final void Function(FloorChangeEvent event)? _onFloorChanged;
  final TransitionSnapper? _transitionSnapper;

  // PR-11
  final ConfidenceFuser _confidenceFuser = const ConfidenceFuser();
  _TransitionBlend? _transitionBlend;
  PositionEstimate? _lastEmitted;

  int _stepsSinceLastGps = 0;
  int _pdrStepCountTotal = 0;

  final StreamController<PositionEstimate> _positionController =
      StreamController<PositionEstimate>.broadcast();

  Stream<PositionEstimate> get position$ => _positionController.stream;

  bool _running = false;
  bool _disposed = false;

  EnvironmentMode _envMode = EnvironmentMode.unknown;
  EnvironmentMode? _envOverride;

  _IndoorAnchor? _indoorAnchor;

  PositionEstimate? _lastGpsEstimate;
  DateTime? _lastGpsTimestamp;

  PositionEstimate? _lastPdrEstimate;

  PositioningController({
    required IndoorPdrEngine pdrEngine,
    required OutdoorMapMatcher mapMatcher,
    FusionConfig config = const FusionConfig(),
    PositioningLogger? logger,
    IndoorMapMatcher? indoorMapMatcher,
    void Function(IndoorMapMatchResult result)? onIndoorMatch,
    FloorChangeDetector? floorDetector,
    void Function(FloorChangeEvent event)? onFloorChanged,
    TransitionSnapper? transitionSnapper,
  })  : _pdrEngine = pdrEngine,
        _mapMatcher = mapMatcher,
        _config = config,
        _logger = logger,
        _indoorMapMatcher = indoorMapMatcher,
        _onIndoorMatch = onIndoorMatch,
        _transitionSnapper = transitionSnapper,
        _floorDetector = floorDetector,
        _onFloorChanged = onFloorChanged;

  void _logEvent(
    String name,
    DateTime timestamp, [
    Map<String, dynamic> data = const <String, dynamic>{},
  ]) {
    final l = _logger;
    if (l is PositioningEventLogger) {
      l.logEvent(
        PositioningEvent(timestamp: timestamp, name: name, data: data),
      );
    }
  }

  void _applyIndoorLevel(String? buildingId, String? levelId) {
    final m = _indoorMapMatcher;
    if (m == null) return;

    final IndoorLevelSwitcher? switcher =
        m is IndoorLevelSwitcher ? m as IndoorLevelSwitcher : null;

    if (switcher != null) {
      switcher.setActiveLevel(buildingId: buildingId, levelId: levelId);
    } else {
      m.reset();
    }
  }

  Future<void> start() async {
    if (_disposed) return;
    _running = true;
  }

  Future<void> stop() async {
    _running = false;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _running = false;
    await _positionController.close();
  }

  // ---------------------------------------------------------------------------
  // Overrides / anchors
  // ---------------------------------------------------------------------------

  void setPdrStepLengthMeters(double meters) {
    _pdrEngine.setStepLengthMeters(meters);
    _logEvent('pdr_step_length_set', DateTime.now(), <String, dynamic>{
      'stepLengthMeters': meters,
    });
  }

  void setEnvironmentOverride(EnvironmentMode? mode) {
    _envOverride = mode;
    _logEvent('environment_override_set', DateTime.now(), <String, dynamic>{
      'override': mode?.name,
    });
  }

  EnvironmentMode? get environmentOverride => _envOverride;

  EnvironmentMode get environmentMode => _effectiveEnvMode;

  EnvironmentMode get _effectiveEnvMode => _envOverride ?? _envMode;

  void setIndoorAnchor({
    required double x,
    required double y,
    String? buildingId,
    String? levelId,
    double? headingDeg,
    bool forceIndoorMode = true,
    bool emitInitial = true,
  }) {
    if (_disposed) return;

    _indoorAnchor = _IndoorAnchor(
      x: x,
      y: y,
      buildingId: buildingId,
      levelId: levelId,
    );

    _floorDetector?.setContext(buildingId: buildingId, levelId: levelId);
    _applyIndoorLevel(buildingId, levelId);

    final headingRad =
        headingDeg == null ? 0.0 : (headingDeg * math.pi / 180.0);

    _pdrEngine.reset(
      x: x,
      y: y,
      headingRad: headingRad,
    );
    _indoorMapMatcher?.reset();

    _logEvent('indoor_anchor_set', DateTime.now(), <String, dynamic>{
      'x': x,
      'y': y,
      'buildingId': buildingId,
      'levelId': levelId,
      'headingDeg': headingDeg,
      'forceIndoorMode': forceIndoorMode,
      'emitInitial': emitInitial,
    });

    if (forceIndoorMode && _envOverride == null) {
      _envMode = EnvironmentMode.indoor;
    }

    if (emitInitial) {
      final now = DateTime.now();
      final fused = PositionEstimate(
        timestamp: now,
        source: PositionSource.fused,
        x: x,
        y: y,
        buildingId: buildingId,
        levelId: levelId,
        isIndoor: true,
        headingDeg: headingDeg,
        speedMps: 0.0,
        accuracyMeters: 2.0,
        isFused: true,
      );
      _emitIfPossible(fused);
    }
  }

  void clearIndoorAnchor() {
    _indoorAnchor = null;
    _logEvent('indoor_anchor_cleared', DateTime.now());
    _indoorMapMatcher?.reset();
    _applyIndoorLevel(null, null);
    _floorDetector?.setContext(buildingId: null, levelId: null);
  }

  // ---------------------------------------------------------------------------
  // Input samples
  // ---------------------------------------------------------------------------

  void addGpsSample(GpsSample sample) {
    if (!_running || _disposed) return;

    _logger?.logGpsSample(sample);

    final gpsEst = _mapMatcher.addGpsSample(sample);
    _lastGpsEstimate = gpsEst;
    _lastGpsTimestamp = gpsEst.timestamp;

    final before = _envMode;
    _updateEnvironmentFromGps(gpsEst);
    final after = _envMode;

    if (before != after) {
      _logEvent('environment_mode_changed', gpsEst.timestamp, <String, dynamic>{
        'from': before.name,
        'to': after.name,
        'reason': 'gps',
        'gpsAccuracyMeters': gpsEst.accuracyMeters,
        'gpsGoodThreshold': _config.gpsGoodAccuracyThreshold,
      });
    }

    // Build GPS-fused baseline.
    var fused = _buildFusedFromGps(gpsEst);

    // PR-11 Level A (guarded):
    // Do NOT blend indoor PDR with outdoor GPS (different frames -> causes drift).
    if (_config.enableConfidenceFusion) {
      final pdr = _lastPdrEstimate;
      final prev = _lastEmitted;

      final bool isIndoorToOutdoorHandoff =
          prev != null && prev.isIndoor && !fused.isIndoor;

      final bool pdrIsOutdoorFrame = pdr != null && !pdr.isIndoor;

      if (!isIndoorToOutdoorHandoff && pdrIsOutdoorFrame && pdr != null) {
        final age = fused.timestamp.difference(pdr.timestamp);
        if (age.abs() <= _config.pdrFusionRecencyWindow) {
          fused = _confidenceFuser.fuseGpsWithPdr(
            gpsFused: fused,
            pdrFused: pdr.copyWith(
              source: PositionSource.fused,
              isFused: true,
            ),
          );
        }
      }
    }

    _emitIfPossible(fused);
  }

  void addImuSample(ImuSample sample) {
    if (!_running || _disposed) return;

    _logger?.logImuSample(sample);
    _floorDetector?.addImuSample(sample);

    final pdrEst = _pdrEngine.addImuSample(sample);
    if (pdrEst == null) return;

    _pdrStepCountTotal++;
    _lastPdrEstimate = pdrEst;
    _stepsSinceLastGps++;
    _floorDetector?.notifyStep(pdrEst.timestamp);

    final before = _envMode;
    final gpsStale = _isGpsStaleAt(pdrEst.timestamp);
    _updateEnvironmentFromPdr(pdrEst);
    final after = _envMode;

    if (before != after) {
      _logEvent('environment_mode_changed', pdrEst.timestamp, <String, dynamic>{
        'from': before.name,
        'to': after.name,
        'reason': 'pdr',
        'gpsStale': gpsStale,
        'stepsSinceLastGps': _stepsSinceLastGps,
        'indoorStepCountThreshold': _config.indoorStepCountThreshold,
        'gpsStaleDurationMs': _config.gpsStaleDuration.inMilliseconds,
      });
    }

    _logEvent('pdr_step', pdrEst.timestamp, <String, dynamic>{
      'stepIndex': _pdrStepCountTotal,
      'x': pdrEst.x,
      'y': pdrEst.y,
      'headingDeg': pdrEst.headingDeg,
      'stepLengthMeters': _pdrEngine.stepLengthMeters,
      'isIndoorEffective': _effectiveEnvMode == EnvironmentMode.indoor,
    });

    final fused = _buildFusedFromPdr(pdrEst);
    if (fused != null) {
      _emitIfPossible(fused);
    }
  }

  void addBarometerSample(BarometerSample sample) {
    if (!_running || _disposed) return;

    _logger?.logBarometerSample(sample);

    final event = _floorDetector?.addBarometerSample(sample);
    if (event == null) return;

    final anchor = _indoorAnchor;
    if (anchor != null) {
      _indoorAnchor = _IndoorAnchor(
        x: anchor.x,
        y: anchor.y,
        buildingId: anchor.buildingId,
        levelId: event.newLevelId,
      );
      _applyIndoorLevel(anchor.buildingId, event.newLevelId);
      _indoorMapMatcher?.reset();
    }

    final snapper = _transitionSnapper;
    final last = _lastPdrEstimate ?? _lastGpsEstimate;
    final curX = (last?.x ?? _indoorAnchor?.x);
    final curY = (last?.y ?? _indoorAnchor?.y);

    if (snapper != null &&
        anchor?.buildingId != null &&
        anchor?.levelId != null &&
        curX != null &&
        curY != null) {
      final snap = snapper.snapOnLevelChange(
        buildingId: anchor!.buildingId!,
        fromLevelId: anchor.levelId ?? 'GF',
        toLevelId: event.newLevelId,
        x: curX,
        y: curY,
      );

      if (snap != null) {
        _logEvent('floor_transition_snap', event.timestamp, snap.toJson());
      }
    }

    _logEvent('floor_changed', event.timestamp, event.diagnostics);
    _onFloorChanged?.call(event);

    if (last != null) {
      final fused = last.copyWith(
        timestamp: event.timestamp,
        source: PositionSource.fused,
        buildingId: anchor?.buildingId ?? last.buildingId,
        levelId: event.newLevelId,
        isIndoor: true,
        isFused: true,
        z: _floorDetector?.currentRelativeAltitudeMeters,
      );
      _emitIfPossible(fused);
    }
  }

  // ---------------------------------------------------------------------------
  // Environment mode logic
  // ---------------------------------------------------------------------------

  void _updateEnvironmentFromGps(PositionEstimate gpsEst) {
    final acc = gpsEst.accuracyMeters;
    if (acc != null && acc <= _config.gpsGoodAccuracyThreshold) {
      _envMode = EnvironmentMode.outdoor;
    } else {
      if (_envMode == EnvironmentMode.unknown) {
        _envMode = EnvironmentMode.outdoor;
      }
    }
  }

  void _updateEnvironmentFromPdr(PositionEstimate pdrEst) {
    final gpsStale = _isGpsStaleAt(pdrEst.timestamp);
    if (gpsStale && _stepsSinceLastGps >= _config.indoorStepCountThreshold) {
      _envMode = EnvironmentMode.indoor;
    }
  }

  bool _isGpsStaleAt(DateTime t) {
    if (_lastGpsTimestamp == null) return true;
    final dt = t.difference(_lastGpsTimestamp!);
    return dt >= _config.gpsStaleDuration;
  }

  // ---------------------------------------------------------------------------
  // Fusion builders
  // ---------------------------------------------------------------------------

  PositionEstimate _buildFusedFromGps(PositionEstimate gpsEst) {
    return PositionEstimate(
      timestamp: gpsEst.timestamp,
      source: PositionSource.fused,
      latitude: gpsEst.latitude,
      longitude: gpsEst.longitude,
      altitude: gpsEst.altitude,
      x: gpsEst.x,
      y: gpsEst.y,
      z: gpsEst.z,
      isIndoor: false,
      headingDeg: gpsEst.headingDeg,
      speedMps: gpsEst.speedMps,
      accuracyMeters: gpsEst.accuracyMeters,
      isFused: true,
    );
  }

  PositionEstimate? _buildFusedFromPdr(PositionEstimate pdrEst) {
    if (_effectiveEnvMode != EnvironmentMode.indoor) return null;

    final anchor = _indoorAnchor;

    final rawFused = PositionEstimate(
      timestamp: pdrEst.timestamp,
      source: PositionSource.fused,
      x: pdrEst.x,
      y: pdrEst.y,
      z: _floorDetector?.currentRelativeAltitudeMeters ?? pdrEst.z,
      buildingId: pdrEst.buildingId ?? anchor?.buildingId,
      levelId: pdrEst.levelId ?? anchor?.levelId,
      isIndoor: true,
      headingDeg: pdrEst.headingDeg,
      speedMps: pdrEst.speedMps,
      accuracyMeters: pdrEst.accuracyMeters,
      isFused: true,
    );

    final matcher = _indoorMapMatcher;
    if (matcher == null) return rawFused;

    final res = matcher.match(rawFused);
    _onIndoorMatch?.call(res);

    _logEvent(
      'indoor_snap',
      res.estimate.timestamp,
      res.diagnostics.toJson(),
    );

    return res.estimate;
  }

  // ---------------------------------------------------------------------------
  // PR-11: Transition blending (remove jumps)
  // ---------------------------------------------------------------------------

  PositionEstimate _applyTransitionBlend(PositionEstimate next) {
    if (!_config.enableTransitionBlending) {
      return next;
    }

    final prev = _lastEmitted;

    // Start a blend when indoor<->outdoor flips.
    if (prev != null && prev.isIndoor != next.isIndoor && next.isFused) {
      final jump = _distanceMeters(prev, next);
      if (jump >= _config.transitionJumpThresholdMeters) {
        final d = _computeBlendDuration(next);
        _transitionBlend =
            _TransitionBlend(start: prev, startTs: next.timestamp, duration: d);
        _logEvent('transition_blend_start', next.timestamp, <String, dynamic>{
          'fromIndoor': prev.isIndoor,
          'toIndoor': next.isIndoor,
          'jumpMeters': jump,
          'durationMs': d.inMilliseconds,
          'gpsAccuracyMeters': next.isIndoor ? null : next.accuracyMeters,
        });
      } else {
        _transitionBlend = null;
      }
    }

    final tb = _transitionBlend;
    if (tb == null) return next;

    final elapsed = next.timestamp.difference(tb.startTs);
    if (elapsed.isNegative) return next;

    final totalMs = math.max(1, tb.duration.inMilliseconds);
    final t = (elapsed.inMilliseconds / totalMs).clamp(0.0, 1.0);

    if (t >= 1.0) {
      _transitionBlend = null;
      return next;
    }

    return _lerpEstimate(tb.start, next, t);
  }

  Duration _computeBlendDuration(PositionEstimate next) {
    final acc = next.accuracyMeters ?? _config.gpsAccuracyBadForBlend;
    final good = _config.gpsAccuracyGoodForBlend;
    final bad = _config.gpsAccuracyBadForBlend;

    final a = acc.clamp(good, bad);
    final u = (a - good) / (bad - good);

    final minUs = _config.transitionBlendMin.inMicroseconds;
    final maxUs = _config.transitionBlendMax.inMicroseconds;
    final outUs = (minUs + (u * (maxUs - minUs))).round();

    return Duration(microseconds: outUs);
  }

  double _distanceMeters(PositionEstimate a, PositionEstimate b) {
    // Prefer x/y if both present.
    if (a.x != null && a.y != null && b.x != null && b.y != null) {
      final dx = b.x! - a.x!;
      final dy = b.y! - a.y!;
      return math.sqrt(dx * dx + dy * dy);
    }
    // Fallback: lat/lon (rough).
    if (a.latitude != null &&
        a.longitude != null &&
        b.latitude != null &&
        b.longitude != null) {
      final lat = a.latitude! * math.pi / 180.0;
      final mPerDegLat = 111320.0;
      final mPerDegLon = 111320.0 * math.cos(lat);
      final dx = (b.longitude! - a.longitude!) * mPerDegLon;
      final dy = (b.latitude! - a.latitude!) * mPerDegLat;
      return math.sqrt(dx * dx + dy * dy);
    }
    return 0.0;
  }

  PositionEstimate _lerpEstimate(
      PositionEstimate from, PositionEstimate to, double t) {
    double lerp(double a, double b) => a + (b - a) * t;

    double? lerpN(double? a, double? b) {
      if (a == null || b == null) return b ?? a;
      return lerp(a, b);
    }

    // Heading (circular lerp)
    double? lerpHeading(double? aDeg, double? bDeg) {
      if (aDeg == null || bDeg == null) return bDeg ?? aDeg;
      final a = aDeg % 360.0;
      final b = bDeg % 360.0;
      var d = b - a;
      if (d > 180.0) d -= 360.0;
      if (d < -180.0) d += 360.0;
      final out = (a + d * t) % 360.0;
      return out < 0 ? out + 360.0 : out;
    }

    return to.copyWith(
      x: lerpN(from.x, to.x),
      y: lerpN(from.y, to.y),
      z: lerpN(from.z, to.z),
      latitude: lerpN(from.latitude, to.latitude),
      longitude: lerpN(from.longitude, to.longitude),
      altitude: lerpN(from.altitude, to.altitude),
      accuracyMeters: lerpN(from.accuracyMeters, to.accuracyMeters),
      headingDeg: lerpHeading(from.headingDeg, to.headingDeg),
    );
  }

  void _emitIfPossible(PositionEstimate estimate) {
    if (_positionController.isClosed) return;

    final out = _applyTransitionBlend(estimate);

    _logger?.logEstimate(out);
    _positionController.add(out);

    _lastEmitted = out;
  }

  // Debug getters
  EnvironmentMode get debugEnvironmentMode => _effectiveEnvMode;
  FusionConfig get debugFusionConfig => _config;
  PositionEstimate? get debugLastGpsEstimate => _lastGpsEstimate;
  PositionEstimate? get debugLastPdrEstimate => _lastPdrEstimate;

  int get debugPdrStepCountTotal => _pdrStepCountTotal;
  double get debugPdrStepLengthMeters => _pdrEngine.stepLengthMeters;
}

class _IndoorAnchor {
  const _IndoorAnchor({
    required this.x,
    required this.y,
    required this.buildingId,
    required this.levelId,
  });

  final double x;
  final double y;
  final String? buildingId;
  final String? levelId;
}

class _TransitionBlend {
  final PositionEstimate start;
  final DateTime startTs;
  final Duration duration;

  const _TransitionBlend({
    required this.start,
    required this.startTs,
    required this.duration,
  });
}
