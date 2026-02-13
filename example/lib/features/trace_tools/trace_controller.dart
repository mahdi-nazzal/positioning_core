//packages/positioning_core/example/lib/features/trace_tools/trace_controller.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:positioning_core/positioning_core.dart';

import '../../services/storage/file_exporter.dart';
import '../../services/storage/trace_store.dart';

class TraceController extends ChangeNotifier {
  TraceController({
    required TraceStore traceStore,
    required FileExporter fileExporter,
  })  : _traceStore = traceStore,
        _fileExporter = fileExporter;

  final TraceStore _traceStore;
  final FileExporter _fileExporter;

  String? lastReplaySummary;

  Future<void> replayLastRecording() async {
    final jsonl = _traceStore.currentJsonl;
    if (jsonl == null || jsonl.trim().isEmpty) {
      lastReplaySummary = 'No recording available.';
      notifyListeners();
      return;
    }

    final estimates = await _replayJsonl(jsonl);
    lastReplaySummary =
    'Replayed ${estimates.length} estimates from last recording.';
    notifyListeners();
  }

  Future<void> replayAssetTrace(String assetPath) async {
    final jsonl = await rootBundle.loadString(assetPath);
    final estimates = await _replayJsonl(jsonl);
    lastReplaySummary =
    'Replayed ${estimates.length} estimates from asset trace.';
    notifyListeners();
  }

  Future<String?> exportLastRecording() async {
    final jsonl = _traceStore.currentJsonl;
    if (jsonl == null || jsonl.trim().isEmpty) return null;
    return _fileExporter.writeJsonl(jsonl);
  }

  Future<List<PositionEstimate>> _replayJsonl(String jsonl) async {
    // Extract indoor anchor from recorded diagnostics events if present.
    final traceEvents = PositioningTraceCodec.decodeJsonLines(jsonl);

    Map<String, dynamic>? anchorData;
    for (final te in traceEvents) {
      if (te.type != PositioningTraceEventType.event) continue;
      final pe = PositioningEvent.fromJson(te.data);
      if (pe.name == 'indoor_anchor_set') {
        anchorData = pe.data;
        break;
      }
    }

    final pdr = IndoorPdrEngine();
    final matcher = OutdoorMapMatcher(graph: null);

    final controller = PositioningController(
      pdrEngine: pdr,
      mapMatcher: matcher,
    );

    // Apply anchor before replay (so IMU steps become meaningful indoor).
    if (anchorData != null) {
      final x = (anchorData['x'] as num?)?.toDouble();
      final y = (anchorData['y'] as num?)?.toDouble();
      if (x != null && y != null) {
        controller.setIndoorAnchor(
          x: x,
          y: y,
          buildingId: anchorData['buildingId'] as String?,
          levelId: anchorData['levelId'] as String?,
          headingDeg: (anchorData['headingDeg'] as num?)?.toDouble(),
          forceIndoorMode: true,
          emitInitial: false,
        );
      }
    }

    final replayer = PositioningReplayer(controller);
    final out = await replayer.replayTraceEvents(traceEvents);

    await controller.dispose();
    return out;
  }
}
