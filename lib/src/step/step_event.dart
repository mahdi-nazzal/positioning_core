import 'package:meta/meta.dart';

/// A confirmed step event emitted by a [StepDetector].
@immutable
class StepEvent {
  /// Timestamp of the detected step (peak time or detection time depending on detector).
  final DateTime timestamp;

  /// Confidence score [0..1] indicating how “step-like” the peak was.
  final double confidence;

  /// Estimated cadence (steps per second / Hz). Null if not enough history.
  final double? cadenceHz;

  const StepEvent({
    required this.timestamp,
    required this.confidence,
    required this.cadenceHz,
  });
}
