import 'dart:math' as math;

import 'floor_detection_config.dart';

abstract class FloorHeightModel {
  double floorHeightMeters({required String? buildingId});
  void applyCalibration({
    required String buildingId,
    required String fromLevelId,
    required String toLevelId,
    required double observedDeltaAltMeters,
    required LevelIdCodec codec,
    double smoothingAlpha = 0.35,
    double minMeters = 2.4,
    double maxMeters = 4.5,
  });
}

class ConstantFloorHeightModel implements FloorHeightModel {
  final double meters;
  const ConstantFloorHeightModel(this.meters);

  @override
  double floorHeightMeters({required String? buildingId}) => meters;

  @override
  void applyCalibration({
    required String buildingId,
    required String fromLevelId,
    required String toLevelId,
    required double observedDeltaAltMeters,
    required LevelIdCodec codec,
    double smoothingAlpha = 0.35,
    double minMeters = 2.4,
    double maxMeters = 4.5,
  }) {
    // no-op
  }
}

class MapFloorHeightModel implements FloorHeightModel {
  MapFloorHeightModel({this.defaultMeters = 3.2});

  final double defaultMeters;
  final Map<String, double> _byBuilding = <String, double>{};

  void setBuildingHeight(String buildingId, double meters) {
    _byBuilding[buildingId] = meters;
  }

  @override
  double floorHeightMeters({required String? buildingId}) {
    if (buildingId == null) return defaultMeters;
    return _byBuilding[buildingId] ?? defaultMeters;
  }

  @override
  void applyCalibration({
    required String buildingId,
    required String fromLevelId,
    required String toLevelId,
    required double observedDeltaAltMeters,
    required LevelIdCodec codec,
    double smoothingAlpha = 0.35,
    double minMeters = 2.4,
    double maxMeters = 4.5,
  }) {
    final from = codec.tryParseIndex(fromLevelId);
    final to = codec.tryParseIndex(toLevelId);
    if (from == null || to == null) return;

    final floors = (to - from).abs();
    if (floors <= 0) return;

    final perFloor = (observedDeltaAltMeters.abs() / floors);
    if (!perFloor.isFinite) return;

    final clamped = perFloor.clamp(minMeters, maxMeters);

    final prev = floorHeightMeters(buildingId: buildingId);
    final a = smoothingAlpha.clamp(0.0, 1.0);
    final next = prev + a * (clamped - prev);

    _byBuilding[buildingId] = next;
  }
}
