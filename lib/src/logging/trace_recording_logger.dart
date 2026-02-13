import '../model/barometer_sample.dart';
import '../model/gps_sample.dart';
import '../model/imu_sample.dart';
import '../model/position_estimate.dart';
import '../model/positioning_event.dart';
import '../trace/positioning_trace_codec.dart';
import '../trace/positioning_trace_event.dart';
import 'positioning_logger.dart';

/// A logger that records a deterministic trace in memory.
///
/// - Raw inputs: GPS/IMU/barometer.
/// - Outputs: position estimates.
/// - Diagnostics: internal events (mode switches, step events...).
///
/// Use [toJsonLines] to persist to disk from an outer layer (Flutter app),
/// or attach traces to bug reports / experiments.
class TraceRecordingLogger
    implements PositioningLogger, PositioningEventLogger {
  final List<PositioningTraceEvent> _events = <PositioningTraceEvent>[];

  /// Optional metadata record (recommended as the first line in a trace).
  ///
  /// Example metadata keys:
  /// - appVersion, platform, deviceModel, sdk, config, notes...
  TraceRecordingLogger({Map<String, dynamic>? metadata}) {
    if (metadata != null) {
      _events.add(
        PositioningTraceEvent(
          type: PositioningTraceEventType.meta,
          timestamp: DateTime.now(),
          data: metadata,
        ),
      );
    }
  }

  @override
  void logGpsSample(GpsSample sample) {
    _events.add(
      PositioningTraceEvent(
        type: PositioningTraceEventType.gps,
        timestamp: sample.timestamp,
        data: sample.toJson(),
      ),
    );
  }

  @override
  void logImuSample(ImuSample sample) {
    _events.add(
      PositioningTraceEvent(
        type: PositioningTraceEventType.imu,
        timestamp: sample.timestamp,
        data: sample.toJson(),
      ),
    );
  }

  @override
  void logBarometerSample(BarometerSample sample) {
    _events.add(
      PositioningTraceEvent(
        type: PositioningTraceEventType.barometer,
        timestamp: sample.timestamp,
        data: sample.toJson(),
      ),
    );
  }

  @override
  void logEstimate(PositionEstimate estimate) {
    _events.add(
      PositioningTraceEvent(
        type: PositioningTraceEventType.estimate,
        timestamp: estimate.timestamp,
        data: estimate.toJson(),
      ),
    );
  }

  @override
  void logEvent(PositioningEvent event) {
    _events.add(
      PositioningTraceEvent(
        type: PositioningTraceEventType.event,
        timestamp: event.timestamp,
        data: event.toJson(),
      ),
    );
  }

  List<PositioningTraceEvent> get events => List.unmodifiable(_events);

  /// Export all events as JSON Lines (JSONL) for persistence.
  String toJsonLines() => PositioningTraceCodec.encodeJsonLines(_events);

  void clear() => _events.clear();
}
