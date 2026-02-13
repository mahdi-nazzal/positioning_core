//packages/positioning_core/lib/src/model/barometer_sample.dart
import 'package:meta/meta.dart';

/// Barometer reading from the device.
///
/// Used to infer relative elevation / floor changes and detect
/// stair/elevator transitions when combined with other sensors.
@immutable
class BarometerSample {
  final DateTime timestamp;

  /// Atmospheric pressure in hectopascals (hPa).
  final double pressureHpa;

  /// Optional temperature in °C if provided by the device.
  final double? temperatureC;

  const BarometerSample({
    required this.timestamp,
    required this.pressureHpa,
    this.temperatureC,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'timestamp': timestamp.toIso8601String(),
      'pressureHpa': pressureHpa,
      'temperatureC': temperatureC,
    };
  }

  factory BarometerSample.fromJson(Map<String, dynamic> json) {
    return BarometerSample(
      timestamp: DateTime.parse(json['timestamp'] as String),
      pressureHpa: (json['pressureHpa'] as num).toDouble(),
      temperatureC: (json['temperatureC'] as num?)?.toDouble(),
    );
  }
}
