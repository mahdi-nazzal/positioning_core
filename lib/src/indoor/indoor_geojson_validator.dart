import 'dart:convert';
import 'dart:math' as math;

import 'corridor_edge.dart';
import 'geojson_indoor_graph_loader.dart';

class IndoorGeojsonValidationReport {
  final bool ok;

  // Nodes
  final int nodeFeatures;
  final int matchedAnchorNodes;

  // Edges
  final int edgeFeatures;
  final Map<String, int> edgeTypeCounts;

  // Geometry/parse issues
  final int invalidFeatures;
  final int invalidGeometries;
  final int nonNumericCoordinates;
  final int emptyLineStrings;
  final int zeroLengthSegments;

  // Output segments
  final int corridorSegments;

  // Local bbox sanity check
  final double? minX;
  final double? minY;
  final double? maxX;
  final double? maxY;

  // Notes (for logs)
  final List<String> warnings;

  const IndoorGeojsonValidationReport({
    required this.ok,
    required this.nodeFeatures,
    required this.matchedAnchorNodes,
    required this.edgeFeatures,
    required this.edgeTypeCounts,
    required this.invalidFeatures,
    required this.invalidGeometries,
    required this.nonNumericCoordinates,
    required this.emptyLineStrings,
    required this.zeroLengthSegments,
    required this.corridorSegments,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.warnings,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ok': ok,
        'nodeFeatures': nodeFeatures,
        'matchedAnchorNodes': matchedAnchorNodes,
        'edgeFeatures': edgeFeatures,
        'edgeTypeCounts': edgeTypeCounts,
        'invalidFeatures': invalidFeatures,
        'invalidGeometries': invalidGeometries,
        'nonNumericCoordinates': nonNumericCoordinates,
        'emptyLineStrings': emptyLineStrings,
        'zeroLengthSegments': zeroLengthSegments,
        'corridorSegments': corridorSegments,
        'bboxLocal':
            (minX != null && minY != null && maxX != null && maxY != null)
                ? <String, double>{
                    'minX': minX!,
                    'minY': minY!,
                    'maxX': maxX!,
                    'maxY': maxY!
                  }
                : null,
        'warnings': warnings,
      };
}

/// Validate nodes + edges GeoJSON and (optionally) produce corridor segments in local coords.
///
/// This is intentionally lightweight: no external deps, pure Dart.
/// Useful for:
/// - pre-publish checks in tooling
/// - debugging “why snap doesn’t work”
/// - CI sanity checks on datasets
IndoorGeojsonValidationReport validateIndoorGeojson({
  required String nodesGeojsonText,
  required String edgesGeojsonText,
  required String anchorNodeUid,
  String edgeTypeFilter = 'corridor',
}) {
  int nodeFeatures = 0;
  int matchedAnchorNodes = 0;

  int edgeFeatures = 0;
  final edgeTypeCounts = <String, int>{};

  int invalidFeatures = 0;
  int invalidGeometries = 0;
  int nonNumericCoordinates = 0;
  int emptyLineStrings = 0;
  int zeroLengthSegments = 0;

  final warnings = <String>[];

  // ---- Parse nodes ----
  IndoorOrigin? origin;
  try {
    final root = jsonDecode(nodesGeojsonText);
    if (root is Map<String, dynamic>) {
      final feats = root['features'];
      if (feats is List) {
        nodeFeatures = feats.length;
        for (final f in feats) {
          if (f is! Map<String, dynamic>) continue;
          final props = f['properties'];
          if (props is! Map<String, dynamic>) continue;
          final uid = props['uid']?.toString();
          if (uid == anchorNodeUid) {
            matchedAnchorNodes++;
          }
        }
      }
    }
    origin = findOriginFromNodesGeojson(
      nodesGeojsonText: nodesGeojsonText,
      nodeUid: anchorNodeUid,
    );
  } catch (_) {
    invalidFeatures++;
  }

  if (origin == null) {
    warnings.add('anchor_uid_not_found_or_invalid: $anchorNodeUid');
  }

  // ---- Parse edges (counts + basic geometry validation) ----
  dynamic edgesRoot;
  try {
    edgesRoot = jsonDecode(edgesGeojsonText);
  } catch (_) {
    invalidFeatures++;
  }

  if (edgesRoot is Map<String, dynamic>) {
    final feats = edgesRoot['features'];
    if (feats is List) {
      edgeFeatures = feats.length;

      for (final f in feats) {
        if (f is! Map<String, dynamic>) {
          invalidFeatures++;
          continue;
        }

        final props = f['properties'];
        if (props is Map<String, dynamic>) {
          final t = props['edge_type']?.toString() ?? 'unknown';
          edgeTypeCounts[t] = (edgeTypeCounts[t] ?? 0) + 1;
        }

        final geom = f['geometry'];
        if (geom is! Map<String, dynamic>) {
          invalidGeometries++;
          continue;
        }

        final type = geom['type']?.toString();
        final coords = geom['coordinates'];

        if (type == 'MultiLineString') {
          if (coords is! List || coords.isEmpty) {
            emptyLineStrings++;
            continue;
          }

          for (final part in coords) {
            if (part is! List || part.length < 2) {
              emptyLineStrings++;
              continue;
            }
            // Validate numeric pairs
            for (final p in part) {
              if (p is! List || p.length < 2) {
                nonNumericCoordinates++;
                continue;
              }
              final x = p[0];
              final y = p[1];
              if (x is! num && double.tryParse(x.toString()) == null)
                nonNumericCoordinates++;
              if (y is! num && double.tryParse(y.toString()) == null)
                nonNumericCoordinates++;
            }
          }
        } else if (type == 'LineString') {
          if (coords is! List || coords.length < 2) {
            emptyLineStrings++;
            continue;
          }
          for (final p in coords) {
            if (p is! List || p.length < 2) {
              nonNumericCoordinates++;
              continue;
            }
            final x = p[0];
            final y = p[1];
            if (x is! num && double.tryParse(x.toString()) == null)
              nonNumericCoordinates++;
            if (y is! num && double.tryParse(y.toString()) == null)
              nonNumericCoordinates++;
          }
        } else {
          // unsupported geometry
          invalidGeometries++;
        }
      }
    }
  }

  // ---- Build corridor segments in local coords (if origin exists) ----
  List<CorridorEdge> segments = const <CorridorEdge>[];
  double? minX, minY, maxX, maxY;

  if (origin != null) {
    segments = corridorEdgesFromEdgesGeojson(
      edgesGeojsonText: edgesGeojsonText,
      origin: origin,
      edgeTypeFilter: edgeTypeFilter,
    );

    // bbox + zero-length segments
    for (final e in segments) {
      final len = e.length;
      if (len <= 1e-9) {
        zeroLengthSegments++;
        continue;
      }

      minX = _min4(minX, e.ax, e.bx);
      minY = _min4(minY, e.ay, e.by);
      maxX = _max4(maxX, e.ax, e.bx);
      maxY = _max4(maxY, e.ay, e.by);
    }

    // sanity: bbox should not be “astronomically large” if origin correct
    if (minX != null && maxX != null && minY != null && maxY != null) {
      final w = (maxX! - minX!).abs();
      final h = (maxY! - minY!).abs();
      final diag = math.sqrt(w * w + h * h);

      if (diag > 2000) {
        warnings.add(
            'bbox_too_large_local_frame(diag≈${diag.toStringAsFixed(1)}m): check origin node or CRS');
      }
      if (diag < 1.0) {
        warnings.add(
            'bbox_too_small(diag≈${diag.toStringAsFixed(3)}m): dataset may be degenerate or wrong units');
      }
    }

    if (segments.isEmpty) {
      warnings.add('no_corridor_segments_loaded(edge_type="$edgeTypeFilter")');
    }
  }

  final ok = origin != null &&
      invalidGeometries == 0 &&
      nonNumericCoordinates == 0 &&
      segments.isNotEmpty;

  return IndoorGeojsonValidationReport(
    ok: ok,
    nodeFeatures: nodeFeatures,
    matchedAnchorNodes: matchedAnchorNodes,
    edgeFeatures: edgeFeatures,
    edgeTypeCounts: edgeTypeCounts,
    invalidFeatures: invalidFeatures,
    invalidGeometries: invalidGeometries,
    nonNumericCoordinates: nonNumericCoordinates,
    emptyLineStrings: emptyLineStrings,
    zeroLengthSegments: zeroLengthSegments,
    corridorSegments: segments.length,
    minX: minX,
    minY: minY,
    maxX: maxX,
    maxY: maxY,
    warnings: warnings,
  );
}

double? _min4(double? cur, double a, double b) {
  final m = math.min(a, b);
  if (cur == null) return m;
  return math.min(cur, m);
}

double? _max4(double? cur, double a, double b) {
  final m = math.max(a, b);
  if (cur == null) return m;
  return math.max(cur, m);
}
