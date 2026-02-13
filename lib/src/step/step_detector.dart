import '../model/imu_sample.dart';
import 'step_event.dart';

/// StepDetector interface.
/// Implementations analyze IMU signals and emit step events.
abstract class StepDetector {
  /// Update detector state and optionally emit a [StepEvent].
  ///
  /// [dtSeconds] should be clamped upstream (see PR-3 clampedDtSeconds).
  StepEvent? update(ImuSample sample, double dtSeconds);

  /// Reset internal state.
  void reset();
}
