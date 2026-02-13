import 'dart:convert';

import 'corridor_edge.dart';

/// IndoorOrigin: global planar origin used to convert geo coords -> local meters.
///
/// localX = geoX - originGeoX
/// localY = geoY - originGeoY
class IndoorOrigin {
  final String buildingId;
  final String floor;
  final double originGeoX;
  final double originGeoY;

  const IndoorOrigin({
    required this.buildingId,
    required this.floor,
    required this.originGeoX,
    required this.originGeoY,
  });
}

/// Finds origin from a nodes GeoJSON FeatureCollection using a node UID.
/// Supports your nodes schema:
/// - properties.uid
/// - properties.buildingId, properties.floor
/// - geometry Point coordinates [x,y]
/// - or properties.x / properties.y (as fallback)
IndoorOrigin? findOriginFromNodesGeojson({
  required String nodesGeojsonText,
  required String nodeUid,
}) {
  final root = jsonDecode(nodesGeojsonText);
  if (root is! Map<String, dynamic>) return null;

  final features = root['features'];
  if (features is! List) return null;

  for (final f in features) {
    if (f is! Map<String, dynamic>) continue;
    final props = f['properties'];
    if (props is! Map<String, dynamic>) continue;

    final uid = props['uid']?.toString();
    if (uid != nodeUid) continue;

    final buildingId = props['buildingId']?.toString() ?? '';
    final floor = props['floor']?.toString() ?? '';

    final geom = f['geometry'];
    double? x;
    double? y;

    // Preferred: geometry.coordinates
    if (geom is Map<String, dynamic> &&
        geom['type']?.toString() == 'Point' &&
        geom['coordinates'] is List) {
      final c = geom['coordinates'] as List;
      x = _readNum(c, 0);
      y = _readNum(c, 1);
    }

    // Fallback: properties.x/y
    x ??= _readNumFromAny(props['x']);
    y ??= _readNumFromAny(props['y']);

    if (x == null || y == null) return null;

    return IndoorOrigin(
      buildingId: buildingId,
      floor: floor,
      originGeoX: x,
      originGeoY: y,
    );
  }

  return null;
}

/// Loads corridor edges from an edges GeoJSON FeatureCollection and converts them
/// into local CorridorEdge segments using [origin].
///
/// Supports:
/// - geometry: MultiLineString or LineString
/// - filters by properties.edge_type == [edgeTypeFilter]
/// - splits polylines into segments between consecutive points
List<CorridorEdge> corridorEdgesFromEdgesGeojson({
  required String edgesGeojsonText,
  required IndoorOrigin origin,
  String edgeTypeFilter = 'corridor',
}) {
  final root = jsonDecode(edgesGeojsonText);
  if (root is! Map<String, dynamic>) return const <CorridorEdge>[];

  final features = root['features'];
  if (features is! List) return const <CorridorEdge>[];

  final out = <CorridorEdge>[];

  for (final f in features) {
    if (f is! Map<String, dynamic>) continue;

    final props = f['properties'];
    if (props is! Map<String, dynamic>) continue;

    final edgeType = props['edge_type']?.toString();
    if (edgeTypeFilter.isNotEmpty && edgeType != edgeTypeFilter) continue;

    final edgeUid = props['edge_uid']?.toString() ?? 'edge';
    final buildingId = props['buildingId']?.toString();
    final floor = props['floor']?.toString();

    // If your dataset includes multiple floors in one file, you can keep only matches:
    if (buildingId != null && buildingId.isNotEmpty) {
      if (buildingId != origin.buildingId) continue;
    }
    if (floor != null && floor.isNotEmpty) {
      if (floor != origin.floor) continue;
    }

    final geom = f['geometry'];
    if (geom is! Map<String, dynamic>) continue;

    final geomType = geom['type']?.toString();
    final coords = geom['coordinates'];

    if (geomType == 'MultiLineString') {
      if (coords is! List) continue;
      for (var partIndex = 0; partIndex < coords.length; partIndex++) {
        final part = coords[partIndex];
        if (part is! List) continue;

        _appendSegments(
          out: out,
          edgeUid: edgeUid,
          buildingId: buildingId ?? origin.buildingId,
          floor: floor ?? origin.floor,
          partIndex: partIndex,
          points: part,
          originGeoX: origin.originGeoX,
          originGeoY: origin.originGeoY,
        );
      }
    } else if (geomType == 'LineString') {
      if (coords is! List) continue;
      _appendSegments(
        out: out,
        edgeUid: edgeUid,
        buildingId: buildingId ?? origin.buildingId,
        floor: floor ?? origin.floor,
        partIndex: 0,
        points: coords,
        originGeoX: origin.originGeoX,
        originGeoY: origin.originGeoY,
      );
    }
  }

  return out;
}

/// Convenience: given nodes + edges geojson, produce matcher-ready edges by anchor UID.
List<CorridorEdge> corridorEdgesFromGeojsonWithAnchorUid({
  required String nodesGeojsonText,
  required String edgesGeojsonText,
  required String anchorNodeUid,
  String edgeTypeFilter = 'corridor',
}) {
  final origin = findOriginFromNodesGeojson(
    nodesGeojsonText: nodesGeojsonText,
    nodeUid: anchorNodeUid,
  );

  if (origin == null) return const <CorridorEdge>[];

  return corridorEdgesFromEdgesGeojson(
    edgesGeojsonText: edgesGeojsonText,
    origin: origin,
    edgeTypeFilter: edgeTypeFilter,
  );
}

// ---------------------------
// Internal helpers
// ---------------------------

void _appendSegments({
  required List<CorridorEdge> out,
  required String edgeUid,
  required String buildingId,
  required String floor,
  required int partIndex,
  required List points,
  required double originGeoX,
  required double originGeoY,
}) {
  if (points.length < 2) return;

  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];

    final ax = _readNum(a, 0);
    final ay = _readNum(a, 1);
    final bx = _readNum(b, 0);
    final by = _readNum(b, 1);

    if (ax == null || ay == null || bx == null || by == null) continue;

    // Convert geo -> local
    final lax = ax - originGeoX;
    final lay = ay - originGeoY;
    final lbx = bx - originGeoX;
    final lby = by - originGeoY;

    final id = '${edgeUid}_p${partIndex}_s$i';

    out.add(
      CorridorEdge(
        id: id,
        ax: lax,
        ay: lay,
        bx: lbx,
        by: lby,
        buildingId: buildingId,
        levelId: floor,
      ),
    );
  }
}

double? _readNum(dynamic coordPair, int index) {
  if (coordPair is! List) return null;
  if (index < 0 || index >= coordPair.length) return null;

  final v = coordPair[index];
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

double? _readNumFromAny(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '');
}
