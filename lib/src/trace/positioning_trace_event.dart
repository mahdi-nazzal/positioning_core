import 'package:meta/meta.dart';

/// Trace event type.
///
/// - [meta] is session metadata (device/app/config).
/// - [gps], [imu], [barometer] are raw inputs.
/// - [estimate] is a fused/output position estimate.
/// - [event] is an internal diagnostic event (mode switches, step detections...).
enum PositioningTraceEventType {
  meta,
  gps,
  imu,
  barometer,
  estimate,
  event,
}

/// One record in a deterministic positioning trace.
///
/// Canonical JSON shape (one per line in JSONL):
/// `{ "v": 1, "t": "gps", "ts": "...", "d": { ... } }`
@immutable
class PositioningTraceEvent {
  static const int schemaVersion = 1;

  final int v;
  final PositioningTraceEventType type;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  const PositioningTraceEvent({
    required this.type,
    required this.timestamp,
    required this.data,
    this.v = schemaVersion,
  });

  Map<String, dynamic> toJson() {
    // Keep insertion order stable for deterministic encoding.
    return <String, dynamic>{
      'v': v,
      't': type.name,
      'ts': timestamp.toIso8601String(),
      'd': data,
    };
  }

  factory PositioningTraceEvent.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['t'] as String?) ?? 'event';
    final type = PositioningTraceEventType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => PositioningTraceEventType.event,
    );

    return PositioningTraceEvent(
      v: (json['v'] as num?)?.toInt() ?? schemaVersion,
      type: type,
      timestamp: DateTime.parse(json['ts'] as String),
      data: (json['d'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }
}
