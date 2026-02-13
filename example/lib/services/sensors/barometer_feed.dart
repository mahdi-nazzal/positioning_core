import 'dart:async';

import 'package:positioning_core/positioning_core.dart';

/// Barometer feed without environment_sensors.
/// For now, this is a "manual injection" feed:
/// - The app can still simulate pressure via a slider/buttons (Scenario 4).
/// - Later, we can plug in a maintained native barometer plugin if needed.
class BarometerFeed {
  final StreamController<BarometerSample> _controller =
  StreamController<BarometerSample>.broadcast();

  Stream<BarometerSample> get samples => _controller.stream;

  bool _running = false;

  /// Start the feed (no native sensor stream in this variant).
  Future<void> start() async {
    _running = true;
  }

  /// Stop the feed.
  Future<void> stop() async {
    _running = false;
  }

  /// Inject a pressure sample (hPa).
  /// Use this from your simulator UI: slider/buttons.
  void inject(double pressureHpa, {DateTime? timestamp}) {
    if (!_running) return;
    _controller.add(
      BarometerSample(
        timestamp: timestamp ?? DateTime.now(),
        pressureHpa: pressureHpa,
      ),
    );
  }

  Future<void> dispose() async {
    _running = false;
    await _controller.close();
  }
}
