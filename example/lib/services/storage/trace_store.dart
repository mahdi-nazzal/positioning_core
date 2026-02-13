import 'package:flutter/foundation.dart';
import 'package:positioning_core/positioning_core.dart';

class TraceStore extends ChangeNotifier {
  TraceRecordingLogger? _logger;
  GateLogger? _gate;

  final List<PositioningEvent> _events = <PositioningEvent>[];
  List<PositioningEvent> get events => List.unmodifiable(_events);
  int get eventCount => _events.length;

  void attach(TraceRecordingLogger logger) {
    _logger = logger;
    _gate = GateLogger(
      logger,
      enabled: true,
      onEvent: (evt) {
        _events.add(evt);
        if (_events.length > 200) {
          _events.removeRange(0, _events.length - 200);
        }
        notifyListeners(); // ✅ safe here (runtime), not during build
      },
    );

    // ❌ DO NOT notify here (it happens during provider creation/build).
    // notifyListeners();
  }

  void setGateEnabled(bool enabled) {
    _gate?.enabled = enabled;
    notifyListeners();
  }

  GateLogger? get gate => _gate;

  String? get currentJsonl => _logger?.toJsonLines();
}

class GateLogger implements PositioningLogger, PositioningEventLogger {
  GateLogger(this._inner, {required this.enabled, this.onEvent});

  final TraceRecordingLogger _inner;
  bool enabled;
  final ValueChanged<PositioningEvent>? onEvent;

  @override
  void logGpsSample(GpsSample sample) {
    if (!enabled) return;
    _inner.logGpsSample(sample);
  }

  @override
  void logImuSample(ImuSample sample) {
    if (!enabled) return;
    _inner.logImuSample(sample);
  }

  @override
  void logBarometerSample(BarometerSample sample) {
    if (!enabled) return;
    _inner.logBarometerSample(sample);
  }

  @override
  void logEstimate(PositionEstimate estimate) {
    if (!enabled) return;
    _inner.logEstimate(estimate);
  }

  @override
  void logEvent(PositioningEvent event) {
    if (!enabled) return;
    _inner.logEvent(event);
    onEvent?.call(event);
  }
}
