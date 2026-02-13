import 'package:positioning_core/positioning_core.dart';

/// Simple on/off gate for logging (recording).
class GateLogger implements PositioningEventLogger {
  GateLogger(this._inner, {required bool enabled}) : _enabled = enabled;

  final PositioningEventLogger _inner;
  bool _enabled;

  bool get enabled => _enabled;
  set enabled(bool v) => _enabled = v;

  @override
  void logGpsSample(GpsSample sample) {
    if (_enabled) _inner.logGpsSample(sample);
  }

  @override
  void logImuSample(ImuSample sample) {
    if (_enabled) _inner.logImuSample(sample);
  }

  @override
  void logBarometerSample(BarometerSample sample) {
    if (_enabled) _inner.logBarometerSample(sample);
  }

  @override
  void logEstimate(PositionEstimate estimate) {
    if (_enabled) _inner.logEstimate(estimate);
  }

  @override
  void logEvent(PositioningEvent event) {
    if (_enabled) _inner.logEvent(event);
  }
}
