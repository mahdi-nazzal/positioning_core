import 'package:meta/meta.dart';

/// A structured internal event for diagnostics and traceability.
///
/// These events are optional and are only emitted when the provided logger
/// also supports event logging (see `PositioningEventLogger`).
@immutable
class PositioningEvent {
  final DateTime timestamp;
  final String name;
  final Map<String, dynamic> data;

  const PositioningEvent({
    required this.timestamp,
    required this.name,
    this.data = const <String, dynamic>{},
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'timestamp': timestamp.toIso8601String(),
      'name': name,
      'data': data,
    };
  }

  factory PositioningEvent.fromJson(Map<String, dynamic> json) {
    return PositioningEvent(
      timestamp: DateTime.parse(json['timestamp'] as String),
      name: (json['name'] as String?) ?? 'event',
      data: (json['data'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }
}
