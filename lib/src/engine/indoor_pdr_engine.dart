import 'dart:math' as math;

import '../model/imu_sample.dart';
import '../model/position_estimate.dart';
import '../orientation/gyro_yaw_estimator.dart';
import '../orientation/orientation_estimate.dart';
import '../orientation/orientation_estimator.dart';
import '../step/filtered_peak_step_detector_v2.dart';
import '../step/step_detector.dart';
import '../step/step_event.dart';
import '../step_length/step_length_estimator.dart';
import '../step_length/weinberg_step_length_estimator.dart';
import '../utils/time_utils.dart';

class IndoorPdrEngine {
  /// Manual override step length (if set by user calibration explicitly).
  /// If null, we use dynamic step length estimation.
  double? _manualStepLengthMeters;

  DateTime? _lastImuTimestamp;
  final double _defaultStepLengthMeters;

  final double stepAccelThreshold;
  final Duration minStepInterval;

  final double baseAccuracyMeters;
  final double driftRatePerMeter;

  final OrientationEstimator _orientation;
  final StepDetector _stepDetector;
  final StepLengthEstimator _stepLengthEstimator;

  double _x = 0.0;
  double _y = 0.0;

  double _headingRad = 0.0;

  double _distanceTraveled = 0.0;
  int _stepCount = 0;

  DateTime? _lastTimestamp;
  DateTime? _lastStepTime;

  IndoorPdrEngine({
    bool useDynamicStepLength = false,
    OrientationEstimator? orientationEstimator,
    StepDetector? stepDetector,
    StepLengthEstimator? stepLengthEstimator,
    double stepLengthMeters = 0.7,
    this.stepAccelThreshold = 3.0,
    this.minStepInterval = const Duration(milliseconds: 300),
    this.baseAccuracyMeters = 0.5,
    this.driftRatePerMeter = 0.02,
  })  : _defaultStepLengthMeters = stepLengthMeters,
        _orientation = orientationEstimator ?? GyroYawEstimator(),
        _stepDetector = stepDetector ??
            FilteredPeakStepDetectorV2(
              signalSource: StepSignalSource.verticalAy,
              minStepInterval: minStepInterval,
              minPeak: stepAccelThreshold,
            ),
        _stepLengthEstimator = stepLengthEstimator ??
            WeinbergStepLengthEstimator(fallbackMeters: stepLengthMeters) {
    // Backward-compatible default: keep fixed step length unless explicitly enabled.
    if (!useDynamicStepLength) {
      _manualStepLengthMeters = stepLengthMeters;
    }
  }

  // ---------------------------
  // Public getters
  // ---------------------------

  /// Manual override if set; otherwise return the default baseline step length.
  /// Note: dynamic step length is computed per-step inside addImuSample().
  double get stepLengthMeters =>
      _manualStepLengthMeters ?? _defaultStepLengthMeters;

  int get debugStepCount => _stepCount;
  double get debugX => _x;
  double get debugY => _y;
  double get debugHeadingRad => _headingRad;
  double get debugDistanceTraveled => _distanceTraveled;
  DateTime? get debugLastTimestamp => _lastTimestamp;
  DateTime? get debugLastStepTime => _lastStepTime;

  /// Manual step length override (meters).
  ///
  /// Guarded to avoid nonsense values.
  void setStepLengthMeters(double meters) {
    const min = 0.35;
    const max = 1.40;
    if (meters.isNaN || meters.isInfinite) return;
    if (meters < min || meters > max) return;

    _manualStepLengthMeters = meters;
  }

  /// Clears manual override so the engine goes back to dynamic estimation.
  void clearManualStepLength() {
    _manualStepLengthMeters = null;
  }

  /// Calibration helper:
  /// Provide known distance and steps (from a calibration walk),
  /// updates the internal estimator parameters.
  void calibrateWithKnownDistance({
    required double distanceMeters,
    required int steps,
  }) {
    _stepLengthEstimator.calibrateWithKnownDistance(
      distanceMeters: distanceMeters,
      steps: steps,
    );
  }

  PositionEstimate? addImuSample(ImuSample sample) {
    final dt = clampedDtSeconds(
      _lastImuTimestamp,
      sample.timestamp,
      minDtSeconds: 0.001,
      maxDtSeconds: 0.2,
    );
    _lastImuTimestamp = sample.timestamp;

    if (dt > 0) {
      final OrientationEstimate o = _orientation.update(sample, dt);
      _headingRad = _normalizeAngle(o.yawRad);
    }

    _lastTimestamp = sample.timestamp;

    final StepEvent? step = _stepDetector.update(sample, dt);
    if (step == null) return null;

    _lastStepTime = sample.timestamp;

    _stepCount++;

    final stepLen = _manualStepLengthMeters ??
        _stepLengthEstimator.estimateMeters(
          step: step,
          sample: sample,
          dtSeconds: dt,
        );

    _distanceTraveled += stepLen;

    _x += stepLen * math.cos(_headingRad);
    _y += stepLen * math.sin(_headingRad);

    final headingDeg = (_headingRad * 180.0 / math.pi) % 360.0;
    final accuracy = baseAccuracyMeters + driftRatePerMeter * _distanceTraveled;

    final cadence = step.cadenceHz;
    final speed = (cadence != null && cadence > 0)
        ? stepLen * cadence
        : stepLen /
            (minStepInterval.inMilliseconds > 0
                ? (minStepInterval.inMilliseconds / 1000.0)
                : 0.3);

    return PositionEstimate(
      timestamp: sample.timestamp,
      source: PositionSource.pdr,
      x: _x,
      y: _y,
      z: null,
      buildingId: null,
      levelId: null,
      isIndoor: true,
      headingDeg: headingDeg,
      speedMps: speed,
      accuracyMeters: accuracy,
      isFused: false,
    );
  }

  void reset({
    double x = 0.0,
    double y = 0.0,
    double headingRad = 0.0,
  }) {
    _x = x;
    _y = y;
    _headingRad = headingRad;
    _distanceTraveled = 0.0;
    _stepCount = 0;
    _lastTimestamp = null;
    _lastStepTime = null;
    _lastImuTimestamp = null;

    _orientation.reset(yawRad: headingRad);
    _stepDetector.reset();
    _stepLengthEstimator.reset();
  }

  double _normalizeAngle(double angle) {
    while (angle <= -math.pi) {
      angle += 2 * math.pi;
    }
    while (angle > math.pi) {
      angle -= 2 * math.pi;
    }
    return angle;
  }
}
