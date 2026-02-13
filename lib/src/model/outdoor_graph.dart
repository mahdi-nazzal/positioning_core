import 'package:meta/meta.dart';

/// Node in the outdoor walkway graph.
///
/// For now this is a minimal representation: each node has a unique ID
/// and a geographic position (lat/lon). Edges reference nodes by ID.
@immutable
class OutdoorGraphNode {
  final String id;
  final double latitude;
  final double longitude;

  const OutdoorGraphNode({
    required this.id,
    required this.latitude,
    required this.longitude,
  });
}

/// Directed edge in the outdoor walkway graph.
///
/// In the simplest case we can treat walkways as undirected by having
/// two edges A→B and B→A with the same length.
@immutable
class OutdoorGraphEdge {
  final String id;
  final String fromNodeId;
  final String toNodeId;
  final double lengthMeters;

  const OutdoorGraphEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.lengthMeters,
  });
}

/// Outdoor walkway graph used for map-matching.
///
/// In PR-P2 this structure is not yet used by the map-matching algorithm
/// (we still pass GPS through), but the abstraction is in place so that
/// future PRs can implement HMM/particle-based map-matching on this graph.
@immutable
class OutdoorGraph {
  final List<OutdoorGraphNode> nodes;
  final List<OutdoorGraphEdge> edges;

  const OutdoorGraph({
    required this.nodes,
    required this.edges,
  });

  OutdoorGraphNode? getNodeById(String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }
}
