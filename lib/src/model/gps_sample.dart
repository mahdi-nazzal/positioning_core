//packages/positioning_core/lib/src/model/gps_sample.dart
import 'package:meta/meta.dart';

/// Raw GNSS/GPS observation as reported by the platform.
///
/// This is a low-level sample: no map-matching, no fusion, just the
/// device-reported position and accuracy.
@immutable
class GpsSample {
  final DateTime timestamp;

  /// Latitude in WGS84 degrees.
  final double latitude;

  /// Longitude in WGS84 degrees.
  final double longitude;

  /// Altitude in meters (optional, may be null on some platforms).
  final double? altitude;

  /// Horizontal accuracy in meters (1-sigma, if provided by platform).
  final double? horizontalAccuracy;

  /// Vertical accuracy in meters (1-sigma, if provided by platform).
  final double? verticalAccuracy;

  /// Instantaneous speed in m/s (optional).
  final double? speed;

  /// Bearing / course in degrees [0, 360), if available.
  final double? bearing;

  const GpsSample({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.horizontalAccuracy,
    this.verticalAccuracy,
    this.speed,
    this.bearing,
  });

  /// Serialize to a JSON-safe map (for deterministic trace logging).
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'horizontalAccuracy': horizontalAccuracy,
      'verticalAccuracy': verticalAccuracy,
      'speed': speed,
      'bearing': bearing,
    };
  }

  /// Deserialize from a JSON map created by [toJson].
  factory GpsSample.fromJson(Map<String, dynamic> json) {
    return GpsSample(
      timestamp: DateTime.parse(json['timestamp'] as String),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      horizontalAccuracy: (json['horizontalAccuracy'] as num?)?.toDouble(),
      verticalAccuracy: (json['verticalAccuracy'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      bearing: (json['bearing'] as num?)?.toDouble(),
    );
  }
}
