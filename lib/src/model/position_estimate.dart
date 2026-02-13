//packages/positioning_core/lib/src/model/position_estimate.dart
import 'package:meta/meta.dart';

/// Source of a position estimate.
///
/// We keep this open to allow future WiFi/BLE/vision anchors.
enum PositionSource {
  gps,
  pdr,
  fused,
  wifi,
  ble,
  beacon,
  vision,
  manual,
}

/// High-level position estimate produced by the fusion engine.
@immutable
class PositionEstimate {
  final DateTime timestamp;

  // Global frame (WGS84).
  final double? latitude;
  final double? longitude;
  final double? altitude;

  // Local frame (e.g. campus coordinates in meters).
  final double? x;
  final double? y;
  final double? z;

  // Indoor semantics.
  final String? buildingId;
  final String? levelId;
  final bool isIndoor;

  // Motion state.
  final double? headingDeg; // [0, 360).
  final double? speedMps;

  // Uncertainty.
  final double? accuracyMeters;

  // Source and fusion metadata.
  final PositionSource source;
  final bool isFused;

  const PositionEstimate({
    required this.timestamp,
    required this.source,
    this.latitude,
    this.longitude,
    this.altitude,
    this.x,
    this.y,
    this.z,
    this.buildingId,
    this.levelId,
    this.isIndoor = false,
    this.headingDeg,
    this.speedMps,
    this.accuracyMeters,
    this.isFused = false,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'timestamp': timestamp.toIso8601String(),
      'source': source.name,
      'isFused': isFused,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'x': x,
      'y': y,
      'z': z,
      'buildingId': buildingId,
      'levelId': levelId,
      'isIndoor': isIndoor,
      'headingDeg': headingDeg,
      'speedMps': speedMps,
      'accuracyMeters': accuracyMeters,
    };
  }

  factory PositionEstimate.fromJson(Map<String, dynamic> json) {
    final sourceStr = (json['source'] as String?) ?? 'gps';
    final source = PositionSource.values.firstWhere(
      (s) => s.name == sourceStr,
      orElse: () => PositionSource.gps,
    );

    return PositionEstimate(
      timestamp: DateTime.parse(json['timestamp'] as String),
      source: source,
      isFused: (json['isFused'] as bool?) ?? false,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      x: (json['x'] as num?)?.toDouble(),
      y: (json['y'] as num?)?.toDouble(),
      z: (json['z'] as num?)?.toDouble(),
      buildingId: json['buildingId'] as String?,
      levelId: json['levelId'] as String?,
      isIndoor: (json['isIndoor'] as bool?) ?? false,
      headingDeg: (json['headingDeg'] as num?)?.toDouble(),
      speedMps: (json['speedMps'] as num?)?.toDouble(),
      accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
    );
  }

  PositionEstimate copyWith({
    DateTime? timestamp,
    double? latitude,
    double? longitude,
    double? altitude,
    double? x,
    double? y,
    double? z,
    String? buildingId,
    String? levelId,
    bool? isIndoor,
    double? headingDeg,
    double? speedMps,
    double? accuracyMeters,
    PositionSource? source,
    bool? isFused,
  }) {
    return PositionEstimate(
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
      buildingId: buildingId ?? this.buildingId,
      levelId: levelId ?? this.levelId,
      isIndoor: isIndoor ?? this.isIndoor,
      headingDeg: headingDeg ?? this.headingDeg,
      speedMps: speedMps ?? this.speedMps,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      isFused: isFused ?? this.isFused,
    );
  }
}
