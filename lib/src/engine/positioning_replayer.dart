//packages/positioning_core/lib/src/engine/positioning_replayer.dart
import '../model/barometer_sample.dart';
import '../model/gps_sample.dart';
import '../model/imu_sample.dart';
import '../model/position_estimate.dart';
import '../trace/positioning_trace_codec.dart';
import '../trace/positioning_trace_event.dart';
import 'positioning_controller.dart';

abstract class ReplayEvent {
  DateTime get timestamp;
  void apply(PositioningController controller);
}

class GpsReplayEvent implements ReplayEvent {
  @override
  final DateTime timestamp;
  final GpsSample sample;

  GpsReplayEvent(this.sample) : timestamp = sample.timestamp;

  @override
  void apply(PositioningController controller) =>
      controller.addGpsSample(sample);
}

class ImuReplayEvent implements ReplayEvent {
  @override
  final DateTime timestamp;
  final ImuSample sample;

  ImuReplayEvent(this.sample) : timestamp = sample.timestamp;

  @override
  void apply(PositioningController controller) =>
      controller.addImuSample(sample);
}

class BarometerReplayEvent implements ReplayEvent {
  @override
  final DateTime timestamp;
  final BarometerSample sample;

  BarometerReplayEvent(this.sample) : timestamp = sample.timestamp;

  @override
  void apply(PositioningController controller) =>
      controller.addBarometerSample(sample);
}

class PositioningReplayer {
  final PositioningController controller;

  PositioningReplayer(this.controller);

  Future<List<PositionEstimate>> replay(List<ReplayEvent> events) async {
    if (events.isEmpty) return <PositionEstimate>[];

    // Deterministic order even when timestamps are equal:
    final indexed = <_IndexedReplayEvent>[
      for (var i = 0; i < events.length; i++) _IndexedReplayEvent(i, events[i]),
    ];

    indexed.sort((a, b) {
      final cmp = a.event.timestamp.compareTo(b.event.timestamp);
      if (cmp != 0) return cmp;
      return a.index.compareTo(b.index);
    });

    final estimates = <PositionEstimate>[];

    await controller.start();
    final sub = controller.position$.listen(estimates.add);

    for (final item in indexed) {
      item.event.apply(controller);
    }

    await Future<void>.delayed(Duration.zero);

    await controller.stop();
    await sub.cancel();

    return estimates;
  }

  /// Replay a JSON Lines trace produced by [TraceRecordingLogger.toJsonLines].
  ///
  /// Only input events (GPS/IMU/barometer) are applied.
  Future<List<PositionEstimate>> replayJsonLines(String jsonl) async {
    final traceEvents = PositioningTraceCodec.decodeJsonLines(jsonl);
    return replayTraceEvents(traceEvents);
  }

  Future<List<PositionEstimate>> replayTraceEvents(
    List<PositioningTraceEvent> traceEvents,
  ) {
    final replayEvents = <ReplayEvent>[];

    for (final e in traceEvents) {
      switch (e.type) {
        case PositioningTraceEventType.meta:
        case PositioningTraceEventType.estimate:
        case PositioningTraceEventType.event:
          // Ignore metadata/outputs/diagnostics during replay.
          break;

        case PositioningTraceEventType.gps:
          replayEvents.add(GpsReplayEvent(GpsSample.fromJson(e.data)));
          break;

        case PositioningTraceEventType.imu:
          replayEvents.add(ImuReplayEvent(ImuSample.fromJson(e.data)));
          break;

        case PositioningTraceEventType.barometer:
          replayEvents.add(
            BarometerReplayEvent(BarometerSample.fromJson(e.data)),
          );
          break;
      }
    }

    return replay(replayEvents);
  }
}

class _IndexedReplayEvent {
  final int index;
  final ReplayEvent event;

  const _IndexedReplayEvent(this.index, this.event);
}
