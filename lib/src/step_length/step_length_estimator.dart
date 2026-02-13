import '../model/imu_sample.dart';
import '../step/step_event.dart';

/// StepLengthEstimator interface.
///
/// Provides dynamic per-step step length estimation.
/// Implementations may use accelerometer peak-to-peak, cadence, user profile, etc.
abstract class StepLengthEstimator {
  /// Returns step length (meters) for a step event at this moment.
  ///
  /// [step] is the detected step event.
  /// [sample] is the current IMU sample (or a representative sample near the step).
  /// [dtSeconds] is the clamped time delta.
  double estimateMeters({
    required StepEvent step,
    required ImuSample sample,
    required double dtSeconds,
  });

  /// Optional calibration: use a known walked distance and number of steps.
  ///
  /// Implementations should update internal parameters to reduce bias.
  void calibrateWithKnownDistance({
    required double distanceMeters,
    required int steps,
  });

  /// Reset to defaults.
  void reset();
}
