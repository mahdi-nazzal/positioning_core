import 'dart:convert';

import 'positioning_trace_event.dart';

/// Codec for deterministic JSONL (JSON Lines) traces.
///
/// Each line is a JSON object representing one [PositioningTraceEvent].
class PositioningTraceCodec {
  /// Encode [events] into JSON Lines format (one JSON object per line).
  static String encodeJsonLines(List<PositioningTraceEvent> events) {
    return events.map((e) => jsonEncode(e.toJson())).join('\n');
  }

  /// Decode JSON Lines into a list of [PositioningTraceEvent].
  static List<PositioningTraceEvent> decodeJsonLines(String jsonl) {
    final lines = const LineSplitter().convert(jsonl);
    final out = <PositioningTraceEvent>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final map = jsonDecode(trimmed) as Map<String, dynamic>;
      out.add(PositioningTraceEvent.fromJson(map));
    }
    return out;
  }
}
