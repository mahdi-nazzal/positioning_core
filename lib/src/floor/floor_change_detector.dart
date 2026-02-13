import 'dart:math' as math;

import '../model/barometer_sample.dart';
import '../model/imu_sample.dart';
import 'baro_altimeter.dart';
import 'floor_detection_config.dart';
import 'floor_height_model.dart';

enum FloorMotionMode { unknown, stairs, elevator }

enum _FloorState { idle, candidateUp, candidateDown, cooldown }

class FloorChangeEvent {
  final DateTime timestamp;
  final String newLevelId;
  final int newLevelIndex;
  final int deltaFloors;
  final double confidence; // 0..1
  final FloorMotionMode mode;
  final Map<String, dynamic> diagnostics;

  const FloorChangeEvent({
    required this.timestamp,
    required this.newLevelId,
    required this.newLevelIndex,
    required this.deltaFloors,
    required this.confidence,
    required this.mode,
    required this.diagnostics,
  });
}

/// Company-grade floor detector:
/// - primary sensor: barometer (relative altitude + vertical speed)
/// - supporting evidence: step cadence + "vertical acceleration energy"
/// - strong hysteresis + settle requirement + cooldown to prevent oscillation
class FloorChangeDetector {
  final FloorDetectionConfig config;
  final LevelIdCodec levelIdCodec;

  final BaroAltimeter _altimeter;

  // Context
  String? _buildingId;
  String? _levelId;
  int? _levelIndex;

  // Relative altitude reference at the current floor "anchor".
  double? _levelAltRefMeters;

  // State machine
  _FloorState _state = _FloorState.idle;
  DateTime? _candidateStartTs;
  double? _candidateStartDeltaAlt;

  DateTime? _settleStartTs;
  DateTime? _cooldownUntil;

  // Vertical accel (gravity-removed projection)
  final _VerticalAccelEstimator _vEstimator;
  final _WindowStats _vWindow;

  // Steps in recent window (for stairs/elevator classification)
  final List<DateTime> _stepTimes = <DateTime>[];
  FloorMotionMode? _candidateMode;
  final FloorHeightModel _floorHeightModel;

  double _floorH() =>
      _floorHeightModel.floorHeightMeters(buildingId: _buildingId);

  FloorChangeDetector({
    FloorDetectionConfig config = const FloorDetectionConfig(),
    LevelIdCodec levelIdCodec = const DefaultLevelIdCodec(),
    FloorHeightModel? floorHeightModel,
  })  : config = config,
        levelIdCodec = levelIdCodec,
        _altimeter = BaroAltimeter(config: config),
        _vEstimator =
            _VerticalAccelEstimator(gravityAlpha: config.gravityEmaAlpha),
        _floorHeightModel = floorHeightModel ??
            ConstantFloorHeightModel(config.floorHeightMeters),
        _vWindow = _WindowStats(window: config.stepWindowDuration);
  void calibrateFloorHeightWithKnownLevels({
    required String buildingId,
    required String fromLevelId,
    required String toLevelId,
    required double observedDeltaAltMeters,
    double smoothingAlpha = 0.35,
  }) {
    _floorHeightModel.applyCalibration(
      buildingId: buildingId,
      fromLevelId: fromLevelId,
      toLevelId: toLevelId,
      observedDeltaAltMeters: observedDeltaAltMeters,
      codec: levelIdCodec,
      smoothingAlpha: smoothingAlpha,
    );
  }

  void reset() {
    _buildingId = null;
    _levelId = null;
    _levelIndex = null;
    _levelAltRefMeters = null;
    _candidateMode = null;

    _state = _FloorState.idle;
    _candidateStartTs = null;
    _candidateStartDeltaAlt = null;
    _settleStartTs = null;
    _cooldownUntil = null;

    _altimeter.reset();
    _vEstimator.reset();
    _vWindow.reset();
    _stepTimes.clear();
  }

  void setContext({
    String? buildingId,
    String? levelId,
  }) {
    _buildingId = buildingId;
    _levelId = levelId;
    _candidateMode = null;

    _levelIndex =
        (levelId == null) ? null : levelIdCodec.tryParseIndex(levelId);
    // Note: we keep altimeter state; only reset ref when first baro arrives.
    _levelAltRefMeters = null;

    _state = _FloorState.idle;
    _candidateStartTs = null;
    _candidateStartDeltaAlt = null;
    _settleStartTs = null;
    _cooldownUntil = null;

    _stepTimes.clear();
    _vWindow.reset();
  }

  String? get currentLevelId => _levelId;
  int? get currentLevelIndex => _levelIndex;

  /// Current baro relative altitude (meters), if available.
  double? get currentRelativeAltitudeMeters => _lastBaro?.altitudeMeters;

  BaroAltimeterState? _lastBaro;

  /// Feed IMU at full rate to maintain vertical-motion evidence.
  void addImuSample(ImuSample sample) {
    final aVert = _vEstimator.update(sample);
    _vWindow.add(sample.timestamp, aVert);
  }

  /// Notify step events (from your StepDetector / PDR).
  void notifyStep(DateTime timestamp) {
    _stepTimes.add(timestamp);
    _pruneSteps(timestamp);
  }

  /// Feed barometer samples; returns a floor-change event when committed.
  FloorChangeEvent? addBarometerSample(BarometerSample sample) {
    if (_cooldownUntil != null && sample.timestamp.isBefore(_cooldownUntil!)) {
      // Still update internals so signals stay fresh.
      _updateBaro(sample);
      return null;
    }

    final baro = _updateBaro(sample);
    final alt = baro.altitudeMeters;
    final vz = baro.verticalSpeedMps;

    _levelAltRefMeters ??= alt;
    final deltaAlt = alt - (_levelAltRefMeters ?? alt);

    // Guard: ignore invalid numeric states.
    if (!alt.isFinite || !vz.isFinite || !deltaAlt.isFinite) {
      return null;
    }

    // Evidence
    final now = sample.timestamp;
    _pruneSteps(now);
    final stepsInWindow = _stepTimes.length;

    final aVertRms = _vWindow.rms(now);
    final stationary = _isStationary(now, aVertRms, vz);

    // Candidate gating: avoid committing when stationary (pressure drift / HVAC).
    final verticalMotionLikely = _verticalMotionLikely(
      stepsInWindow: stepsInWindow,
      vz: vz,
      aVertRms: aVertRms,
    );

    final mode = _classifyMode(
      stepsInWindow: stepsInWindow,
      vz: vz,
      aVertRms: aVertRms,
    );

    // State machine
    // Stationary gating should prevent *starting* false transitions due to HVAC/drift,
    // but MUST NOT cancel an already-active candidate that is trying to "settle" and commit.
    if (stationary && _state == _FloorState.idle) {
      _candidateStartTs = null;
      _candidateStartDeltaAlt = null;
      _settleStartTs = null;
      return null;
    }

    final floorH = _floorH();

    // ✅ FIX: Use a safe default threshold fraction (35% of floor height).
    // If you later add it to FloorDetectionConfig, replace this constant with config field.
    const double candidateThresholdFloors = 0.35;
    final candThresh = floorH * candidateThresholdFloors;

    final commitThresh = config.commitFrac * floorH;

    final sign = deltaAlt.sign.toInt();

    // Enter candidate
    if (_state == _FloorState.idle &&
        verticalMotionLikely &&
        deltaAlt.abs() >= candThresh) {
      _state = sign >= 0 ? _FloorState.candidateUp : _FloorState.candidateDown;
      _candidateStartTs = now;
      _candidateStartDeltaAlt = deltaAlt;
      _candidateMode = mode; // latch mode at candidate start
      _settleStartTs = null;
      return null;
    }

    // While in candidate: ensure direction consistency.
    if (_state == _FloorState.candidateUp ||
        _state == _FloorState.candidateDown) {
      final isUp = _state == _FloorState.candidateUp;
      if ((isUp && deltaAlt < 0) || (!isUp && deltaAlt > 0)) {
        // Direction flipped -> reset candidate.
        _state = _FloorState.idle;
        _candidateStartTs = null;
        _candidateStartDeltaAlt = null;
        _candidateMode = null;
        _settleStartTs = null;
        return null;
      }

      final start = _candidateStartTs ?? now;
      final heldFor = now.difference(start);

      // Need candidate to persist long enough.
      if (heldFor < config.candidateMinDuration) {
        return null;
      }

      // Strong enough to consider committing?
      final strongByAlt = deltaAlt.abs() >= commitThresh;

      // Elevator can commit slightly earlier if vertical speed is strong and steps are few.
      final elevatorFastPath = mode == FloorMotionMode.elevator &&
          deltaAlt.abs() >= (0.70 * floorH) &&
          vz.abs() >= config.minVzForVerticalMotion;

      if (!(strongByAlt || elevatorFastPath)) {
        return null;
      }

      // Require settling before commit (prevents mid-transition flip-flops).
      final settledNow = vz.abs() <= config.settleVzThreshold;

      if (!settledNow) {
        _settleStartTs = null;
        return null;
      }

      _settleStartTs ??= now;
      if (now.difference(_settleStartTs!) < config.settleDuration) {
        return null;
      }

      // Commit (requires known level index).
      if (_levelIndex == null || _levelId == null) {
        _state = _FloorState.cooldown;
        _cooldownUntil = now.add(config.cooldownDuration);
        return null;
      }

      final commitMode = _candidateMode ?? mode;
      final deltaFloors = _computeDeltaFloors(deltaAlt, commitMode);
      final newIndex = _levelIndex! + deltaFloors;
      final newLevelId = levelIdCodec.formatIndex(newIndex);

      // Update reference altitude to reduce accumulation drift:
      _levelAltRefMeters = (_levelAltRefMeters ?? alt) + deltaFloors * floorH;

      _levelIndex = newIndex;
      _levelId = newLevelId;

      _state = _FloorState.cooldown;
      _cooldownUntil = now.add(config.cooldownDuration);
      _candidateStartTs = null;
      _candidateStartDeltaAlt = null;
      _candidateMode = null;
      _settleStartTs = null;

      final confidence = _confidenceScore(
        deltaAlt: deltaAlt,
        floorH: floorH,
        stepsInWindow: stepsInWindow,
        mode: commitMode,
        aVertRms: aVertRms,
        vz: vz,
      );

      return FloorChangeEvent(
        timestamp: now,
        newLevelId: newLevelId,
        newLevelIndex: newIndex,
        deltaFloors: deltaFloors,
        confidence: confidence,
        mode: commitMode,
        diagnostics: <String, dynamic>{
          'buildingId': _buildingId,
          'prevLevelId': levelIdCodec.formatIndex(newIndex - deltaFloors),
          'newLevelId': newLevelId,
          'deltaAltMeters': deltaAlt,
          'floorHeightMeters': floorH,
          'stepsInWindow': stepsInWindow,
          'aVertRms': aVertRms,
          'vzMps': vz,
          'mode': commitMode.name,
          'baro': baro.toJson(),
        },
      );
    }

    return null;
  }

  BaroAltimeterState _updateBaro(BarometerSample sample) {
    // Stationary hint: derived from step + vertical accel RMS (baro vz is part of output).
    final now = sample.timestamp;
    _pruneSteps(now);
    final stepsInWindow = _stepTimes.length;
    final aVertRms = _vWindow.rms(now);

    final noStepsLongEnough =
        _timeSinceLastStep(now) >= config.stationaryNoStepDuration;
    final stationaryHint =
        noStepsLongEnough && aVertRms <= config.stationaryAVertRms;

    _lastBaro = _altimeter.update(sample, stationary: stationaryHint);
    return _lastBaro!;
  }

  bool _verticalMotionLikely({
    required int stepsInWindow,
    required double vz,
    required double aVertRms,
  }) {
    if (stepsInWindow >= 2) return true;
    if (vz.abs() >= config.minVzForVerticalMotion) return true;
    if (aVertRms >= config.minAVertRmsForVerticalMotion) return true;
    return false;
  }

  FloorMotionMode _classifyMode({
    required int stepsInWindow,
    required double vz,
    required double aVertRms,
  }) {
    if (stepsInWindow >= config.stairsMinStepsInWindow)
      return FloorMotionMode.stairs;

    // Elevator: few/no steps + strong vz is a good production heuristic.
    if (stepsInWindow <= config.elevatorMaxStepsInWindow &&
        vz.abs() >= config.minVzForVerticalMotion &&
        aVertRms >= 0.12) {
      return FloorMotionMode.elevator;
    }

    return FloorMotionMode.unknown;
  }

  int _computeDeltaFloors(double deltaAltMeters, FloorMotionMode mode) {
    final floorH = _floorH();

    if (floorH <= 0) return deltaAltMeters >= 0 ? 1 : -1;

    final sign = deltaAltMeters >= 0 ? 1 : -1;
    final floorsAbs = (deltaAltMeters.abs() / floorH);

    // Elevator: allow multi-floor (round to nearest, minimum 1).
    if (mode == FloorMotionMode.elevator) {
      final n = floorsAbs.round().clamp(1, 50);
      return sign * n;
    }

    // Stairs/unknown: commit single floor (more conservative).
    return sign * 1;
  }

  bool _isStationary(DateTime now, double aVertRms, double vz) {
    final noStepsLongEnough =
        _timeSinceLastStep(now) >= config.stationaryNoStepDuration;
    final accelQuiet = aVertRms <= config.stationaryAVertRms;

    // Baro stability check (optional but useful):
    final vzQuiet = vz.abs() <= (config.settleVzThreshold * 0.8);

    return noStepsLongEnough && accelQuiet && vzQuiet;
  }

  Duration _timeSinceLastStep(DateTime now) {
    if (_stepTimes.isEmpty) return const Duration(days: 999);
    final last = _stepTimes.last;
    return now.difference(last);
  }

  void _pruneSteps(DateTime now) {
    final w = config.stepWindowDuration;
    while (_stepTimes.isNotEmpty && now.difference(_stepTimes.first) > w) {
      _stepTimes.removeAt(0);
    }
  }

  double _confidenceScore({
    required double deltaAlt,
    required double floorH,
    required int stepsInWindow,
    required FloorMotionMode mode,
    required double aVertRms,
    required double vz,
  }) {
    // Simple bounded score (deterministic, stable).
    final altScore = (deltaAlt.abs() / floorH).clamp(0.0, 1.5);
    final base = (altScore / 1.2).clamp(0.0, 1.0);

    final stepScore = (stepsInWindow / 5.0).clamp(0.0, 1.0);
    final vzScore = (vz.abs() / 0.6).clamp(0.0, 1.0);
    final aScore = (aVertRms / 0.6).clamp(0.0, 1.0);

    final modeBoost = mode == FloorMotionMode.stairs
        ? 0.10
        : (mode == FloorMotionMode.elevator ? 0.12 : 0.0);

    final combined = (0.55 * base) +
        (0.20 * stepScore) +
        (0.15 * vzScore) +
        (0.10 * aScore) +
        modeBoost;
    return combined.clamp(0.0, 1.0);
  }
}

// -----------------------------------------------------------------------------
// Internals: vertical accel estimator + window RMS
// -----------------------------------------------------------------------------

class _VerticalAccelEstimator {
  final double gravityAlpha;

  _Vec3? _g; // gravity estimate in device frame

  _VerticalAccelEstimator({required this.gravityAlpha});

  void reset() => _g = null;

  /// Returns "vertical linear accel" along gravity axis (m/s^2).
  double update(ImuSample sample) {
    final a = _Vec3(sample.ax, sample.ay, sample.az);

    _g ??= _Vec3(a.x, a.y, a.z);
    _g = _Vec3(
      _g!.x + gravityAlpha * (a.x - _g!.x),
      _g!.y + gravityAlpha * (a.y - _g!.y),
      _g!.z + gravityAlpha * (a.z - _g!.z),
    );

    final g = _g!;
    final lin = _Vec3(a.x - g.x, a.y - g.y, a.z - g.z);

    final gNorm = g.norm();
    if (gNorm < 1e-6) return 0.0;

    // "Up" is opposite gravity.
    final up = _Vec3(-g.x / gNorm, -g.y / gNorm, -g.z / gNorm);

    return lin.dot(up);
  }
}

class _WindowStats {
  final Duration window;
  final List<_Sample> _samples = <_Sample>[];

  _WindowStats({required this.window});

  void reset() => _samples.clear();

  void add(DateTime ts, double value) {
    _samples.add(_Sample(ts, value));
    _prune(ts);
  }

  double rms(DateTime now) {
    _prune(now);
    if (_samples.isEmpty) return 0.0;

    var sumSq = 0.0;
    for (final s in _samples) {
      sumSq += s.v * s.v;
    }
    return math.sqrt(sumSq / _samples.length);
  }

  void _prune(DateTime now) {
    while (_samples.isNotEmpty && now.difference(_samples.first.t) > window) {
      _samples.removeAt(0);
    }
  }
}

class _Sample {
  final DateTime t;
  final double v;
  _Sample(this.t, this.v);
}

class _Vec3 {
  final double x;
  final double y;
  final double z;

  _Vec3(this.x, this.y, this.z);

  double dot(_Vec3 o) => x * o.x + y * o.y + z * o.z;
  double norm() => math.sqrt(x * x + y * y + z * z);
}
