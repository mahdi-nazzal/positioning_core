import 'dart:math' as math;

import '../model/imu_sample.dart';
import '../utils/num_safety.dart';
import 'step_detector.dart';
import 'step_event.dart';

/// Which signal the detector uses.
enum StepSignalSource {
  /// Uses abs(ay) (legacy-compatible). Detection is refractory-only above threshold.
  verticalAy,

  /// Uses | |a| - g |. Detection is peak-based on filtered signal.
  magnitudeNoGravity,
}

/// StepDetector v2:
/// - adaptive threshold via EMA noise floor
/// - stationary suppression
/// - confidence + cadence estimation
///
/// Compatibility guarantees:
/// - For [verticalAy], we intentionally keep behavior compatible with legacy
///   `abs(ay) > threshold` + `minStepInterval`, because many tests/traces may
///   not include below-threshold samples between pulses.
/// - For [verticalAy], noise floor EMA is updated ONLY from samples below
///   [minPeak], so peaks do not inflate the threshold and “kill” step detection.
/// - For [magnitudeNoGravity], we use filtered peak detection with full adaptive
///   noise tracking.
class FilteredPeakStepDetectorV2 implements StepDetector {
  final StepSignalSource signalSource;

  /// Refractory interval (suppresses double-counting).
  final Duration minStepInterval;

  /// Absolute minimum threshold (units depend on signalSource).
  final double minPeak;

  /// Adaptive threshold multiplier on noise floor.
  final double thresholdMultiplier;

  /// Filter time constants (seconds).
  final double filterTauSeconds;
  final double noiseTauSeconds;
  final double gravityTauSeconds;

  /// Stationary gating.
  final double stationaryAccelEmaThreshold;
  final double stationaryGyroRadPerSecThreshold;
  final double stationaryHoldSeconds;

  // State
  double _gravityEma = 9.81; // only used in magnitudeNoGravity

  // Filtered value used for noise tracking (stable).
  double _filtered = 0.0;

  // Noise floor EMA (of filtered magnitude).
  double _noiseEma = 0.0;

  // Faster motion EMA for stationary detection.
  double _motionEma = 0.0;

  // Peak detection history (used for magnitudeNoGravity only).
  double _prev2 = 0.0;
  double _prev1 = 0.0;
  DateTime? _prev2Ts;
  DateTime? _prev1Ts;

  DateTime? _lastStepTs;

  // Stationary accumulator in seconds.
  double _stationarySeconds = 0.0;

  FilteredPeakStepDetectorV2({
    this.signalSource = StepSignalSource.verticalAy,
    this.minStepInterval = const Duration(milliseconds: 300),
    this.minPeak = 3.0,
    this.thresholdMultiplier = 1.6,
    this.filterTauSeconds = 0.06,
    this.noiseTauSeconds = 0.8,
    this.gravityTauSeconds = 1.2,
    this.stationaryAccelEmaThreshold = 0.25,
    this.stationaryGyroRadPerSecThreshold = 0.20,
    this.stationaryHoldSeconds = 0.8,
  });

  @override
  StepEvent? update(ImuSample sample, double dtSeconds) {
    final dt = dtSeconds > 0 ? dtSeconds : 0.0;

    // Raw signal (device-dependent units).
    final raw = _computeRawSignal(sample, dt);

    // Filtered signal (for noise tracking).
    _filtered = _ema(_filtered, raw, _alpha(dt, filterTauSeconds));

    // Motion EMA for stationary detection should react quickly (use raw).
    _motionEma = _ema(_motionEma, raw.abs(), _alpha(dt, 0.25));

    final gyroNorm = _gyroNorm(sample);

    final stationaryNow = _motionEma < stationaryAccelEmaThreshold &&
        gyroNorm < stationaryGyroRadPerSecThreshold;

    if (dt > 0) {
      if (stationaryNow) {
        _stationarySeconds += dt;
      } else {
        _stationarySeconds = math.max(0.0, _stationarySeconds - 3.0 * dt);
      }
    }

    final isStationary = _stationarySeconds >= stationaryHoldSeconds;

    // --- Noise floor update ---
    // For verticalAy: update noise only when below minPeak (noise-only region).
    // This prevents peaks from inflating the adaptive threshold and causing 0 steps.
    final absFiltered = _filtered.abs();
    final aNoise = _alpha(dt, noiseTauSeconds);

    if (signalSource == StepSignalSource.verticalAy) {
      if (absFiltered < minPeak) {
        _noiseEma = _ema(_noiseEma, absFiltered, aNoise);
      }
      // else: hold noiseEma (do not learn from peaks)
    } else {
      // magnitude mode: noise tracking can include the full filtered magnitude.
      _noiseEma = _ema(_noiseEma, absFiltered, aNoise);
    }

    // Adaptive threshold
    final threshold = math.max(minPeak, _noiseEma * thresholdMultiplier);

    // Allow very strong events even if "stationary" (first-step unlock).
    final allowWhileStationary = raw >= (threshold * 1.5);

    if (signalSource == StepSignalSource.verticalAy) {
      // --------
      // VerticalAy: legacy-compatible refractory-only detection above threshold
      // --------
      if (raw >= threshold &&
          (!isStationary || allowWhileStationary) &&
          _passesRefractory(sample.timestamp)) {
        final cadence = _cadenceHz(sample.timestamp);
        final conf = _confidence(raw, threshold);

        _lastStepTs = sample.timestamp;

        return StepEvent(
          timestamp: sample.timestamp,
          confidence: conf,
          cadenceHz: cadence,
        );
      }

      return null;
    }

    // --------
    // MagnitudeNoGravity: filtered peak detection
    // --------
    final peakSignal = _filtered;
    final current = peakSignal;
    final currentTs = sample.timestamp;

    StepEvent? out;

    if (_prev2Ts != null && _prev1Ts != null) {
      final isPeak = (_prev1 > _prev2) && (_prev1 > current);

      if (isPeak) {
        if ((!isStationary || allowWhileStationary) &&
            _prev1 >= threshold &&
            _passesRefractory(_prev1Ts!)) {
          final cadence = _cadenceHz(_prev1Ts!);
          final conf = _confidence(_prev1, threshold);

          _lastStepTs = _prev1Ts;

          out = StepEvent(
            timestamp: _prev1Ts!,
            confidence: conf,
            cadenceHz: cadence,
          );
        }
      }
    }

    // Shift history
    _prev2 = _prev1;
    _prev2Ts = _prev1Ts;

    _prev1 = current;
    _prev1Ts = currentTs;

    return out;
  }

  @override
  void reset() {
    _gravityEma = 9.81;

    _filtered = 0.0;
    _noiseEma = 0.0;
    _motionEma = 0.0;

    _prev2 = 0.0;
    _prev1 = 0.0;
    _prev2Ts = null;
    _prev1Ts = null;

    _lastStepTs = null;
    _stationarySeconds = 0.0;
  }

  // ---------------------------
  // Internals
  // ---------------------------

  double _computeRawSignal(ImuSample s, double dt) {
    switch (signalSource) {
      case StepSignalSource.verticalAy:
        return safeDouble(s.ay, fallback: 0.0).abs();

      case StepSignalSource.magnitudeNoGravity:
        final ax = safeDouble(s.ax, fallback: 0.0);
        final ay = safeDouble(s.ay, fallback: 0.0);
        final az = safeDouble(s.az, fallback: 0.0);

        final mag = math.sqrt(ax * ax + ay * ay + az * az);
        if (mag.isNaN || mag.isInfinite) return 0.0;

        final aG = _alpha(dt, gravityTauSeconds);
        _gravityEma = _ema(_gravityEma, mag, aG);

        return (mag - _gravityEma).abs();
    }
  }

  bool _passesRefractory(DateTime ts) {
    final last = _lastStepTs;
    if (last == null) return true;
    return ts.difference(last) >= minStepInterval;
  }

  double? _cadenceHz(DateTime stepTs) {
    final last = _lastStepTs;
    if (last == null) return null;

    final dt = stepTs.difference(last).inMicroseconds / 1e6;
    if (dt <= 0) return null;

    final hz = 1.0 / dt;
    if (hz < 0.5 || hz > 4.0) return null;
    return hz;
  }

  double _confidence(double value, double threshold) {
    if (value.isNaN || value.isInfinite) return 0.0;
    if (threshold <= 0) return 0.0;
    if (value <= threshold) return 0.0;

    final x = (value - threshold) / threshold;
    return x.clamp(0.0, 1.0);
  }

  double _gyroNorm(ImuSample s) {
    final gx = safeDouble(s.gx, fallback: 0.0);
    final gy = safeDouble(s.gy, fallback: 0.0);
    final gz = safeDouble(s.gz, fallback: 0.0);
    return math.sqrt(gx * gx + gy * gy + gz * gz);
  }

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
