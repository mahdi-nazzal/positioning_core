import '../model/barometer_sample.dart';
import '../model/gps_sample.dart';
import '../model/imu_sample.dart';
import '../model/position_estimate.dart';
import '../model/positioning_event.dart';

/// PositioningLogger
///
/// Abstract interface for logging raw sensor samples and fused estimates.
abstract class PositioningLogger {
  void logGpsSample(GpsSample sample);
  void logImuSample(ImuSample sample);
  void logBarometerSample(BarometerSample sample);
  void logEstimate(PositionEstimate estimate);
}

/// Optional extension interface for structured internal events.
///
/// Implement this to collect diagnostics such as:
/// - environment mode transitions,
/// - step detections,
abstract class PositioningEventLogger extends PositioningLogger {
  void logEvent(PositioningEvent event);
}

/// Simple in-memory logger used for tests and experiments.
///
/// Stores everything in RAM (good for tests / small research traces).
class InMemoryPositioningLogger
    implements PositioningLogger, PositioningEventLogger {
  final List<GpsSample> _gpsSamples = <GpsSample>[];
  final List<ImuSample> _imuSamples = <ImuSample>[];
  final List<BarometerSample> _barometerSamples = <BarometerSample>[];
  final List<PositionEstimate> _estimates = <PositionEstimate>[];
  final List<PositioningEvent> _events = <PositioningEvent>[];

  @override
  void logGpsSample(GpsSample sample) => _gpsSamples.add(sample);

  @override
  void logImuSample(ImuSample sample) => _imuSamples.add(sample);

  @override
  void logBarometerSample(BarometerSample sample) =>
      _barometerSamples.add(sample);

  @override
  void logEstimate(PositionEstimate estimate) => _estimates.add(estimate);

  @override
  void logEvent(PositioningEvent event) => _events.add(event);

  List<GpsSample> get gpsSamples => List.unmodifiable(_gpsSamples);
  List<ImuSample> get imuSamples => List.unmodifiable(_imuSamples);
  List<BarometerSample> get barometerSamples =>
      List.unmodifiable(_barometerSamples);
  List<PositionEstimate> get estimates => List.unmodifiable(_estimates);
  List<PositioningEvent> get events => List.unmodifiable(_events);
}
