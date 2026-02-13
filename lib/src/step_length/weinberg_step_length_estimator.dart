import 'dart:math' as math;

import '../model/imu_sample.dart';
import '../step/step_event.dart';
import '../utils/num_safety.dart';
import 'step_length_estimator.dart';

class WeinbergStepLengthEstimator implements StepLengthEstimator {
  /// Base coefficient (meters). Will be tuned by calibration.
  double _k;

  /// Smoothed dynamic intensity (unitless-ish).
  double _intensityEma = 0.0;

  /// EMA speed for intensity tracking.
  final double intensityTauSeconds;

  /// Output smoothing (EMA) on meters.
  final double outputTauSeconds;

  /// Bounds (meters).
  final double minMeters;
  final double maxMeters;

  /// Fallback if intensity is too small/invalid.
  final double fallbackMeters;

  /// Current smoothed output.
  double _metersEma;

  WeinbergStepLengthEstimator({
    double k = 0.55,
    this.intensityTauSeconds = 0.25,
    this.outputTauSeconds = 0.35,
    this.minMeters = 0.35,
    this.maxMeters = 1.40,
    this.fallbackMeters = 0.70,
  })  : _k = k,
        _metersEma = fallbackMeters;

  @override
  double estimateMeters({
    required StepEvent step,
    required ImuSample sample,
    required double dtSeconds,
  }) {
    final dt = dtSeconds > 0 ? dtSeconds : 0.0;

    // Compute dynamic magnitude: ||a|| - g|
    final ax = safeDouble(sample.ax, fallback: 0.0);
    final ay = safeDouble(sample.ay, fallback: 0.0);
    final az = safeDouble(sample.az, fallback: 0.0);
    final mag = math.sqrt(ax * ax + ay * ay + az * az);
    if (mag.isNaN || mag.isInfinite) {
      return _metersEma.clamp(minMeters, maxMeters);
    }

    final dyn = (mag - 9.81).abs();

    // Update intensity EMA
    final aI = _alpha(dt, intensityTauSeconds);
    _intensityEma = _ema(_intensityEma, dyn, aI);

    // Weinberg: L = k * (intensity)^(1/4)
    // Use intensityEma for stability.
    final intensity = _intensityEma;
    double meters;
    if (intensity <= 1e-6 || intensity.isNaN || intensity.isInfinite) {
      meters = fallbackMeters;
    } else {
      meters = _k * math.pow(intensity, 0.25).toDouble();
    }

    // Optional confidence coupling:
    // low confidence -> pull toward fallback
    final c = step.confidence.clamp(0.0, 1.0);
    meters = (c * meters) + ((1.0 - c) * fallbackMeters);

    // Smooth output
    final aO = _alpha(dt, outputTauSeconds);
    _metersEma = _ema(_metersEma, meters, aO);

    return _metersEma.clamp(minMeters, maxMeters);
  }

  @override
  void calibrateWithKnownDistance({
    required double distanceMeters,
    required int steps,
  }) {
    if (distanceMeters.isNaN || distanceMeters.isInfinite) return;
    if (steps <= 0) return;

    final targetPerStep = distanceMeters / steps;
    if (targetPerStep.isNaN || targetPerStep.isInfinite) return;

    // Clamp to plausible bounds
    final clampedTarget = targetPerStep.clamp(minMeters, maxMeters);

    // If intensity is near zero, calibration can't infer k.
    final intensity = _intensityEma;
    if (intensity <= 1e-6 || intensity.isNaN || intensity.isInfinite) {
      // Fall back: set k so that the model tends toward the target (using fallback intensity=1).
      _k = clampedTarget;
      _metersEma = clampedTarget;
      return;
    }

    // Solve k from: target = k * intensity^(1/4)
    final denom = math.pow(intensity, 0.25).toDouble();
    if (denom <= 1e-9) return;

    final newK = clampedTarget / denom;

    // Smoothly move k to avoid shocks.
    _k = 0.7 * _k + 0.3 * newK;

    // Update output baseline too.
    _metersEma = 0.7 * _metersEma + 0.3 * clampedTarget;
  }

  @override
  void reset() {
    _intensityEma = 0.0;
    _metersEma = fallbackMeters;
  }

  // ---------------------------
  // Helpers
  // ---------------------------

  double _ema(double prev, double x, double alpha) {
    if (alpha <= 0) return prev;
    if (alpha >= 1) return x;
    return prev + alpha * (x - prev);
  }

  double _alpha(double dt, double tau) {
    if (dt <= 0) return 0.0;
    if (tau <= 1e-9) return 1.0;
    return 1.0 - math.exp(-dt / tau);
  }
}
