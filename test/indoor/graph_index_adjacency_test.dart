import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  test('IndoorGraphIndex adjacency builds correct neighbors at a junction', () {
    // IMPORTANT:
    // Our real indoor graphs are node-based: edges meet at endpoints.
    // So we model the junction by splitting the horizontal corridor at (12,0).

    final edges = <CorridorEdge>[
      const CorridorEdge(id: 'H1', ax: 0, ay: 0, bx: 12, by: 0),
      const CorridorEdge(id: 'H2', ax: 12, ay: 0, bx: 20, by: 0),
      const CorridorEdge(id: 'V', ax: 12, ay: 0, bx: 12, by: 10),
    ];

    final index = IndoorGraphIndex(edges: edges, epsMeters: 0.35);

    // All three share the junction node at (12,0), so adjacency should exist.
    expect(index.areAdjacent('H1', 'H2'), isTrue);
    expect(index.areAdjacent('H1', 'V'), isTrue);
    expect(index.areAdjacent('H2', 'V'), isTrue);
  });
}
