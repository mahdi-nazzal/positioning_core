import 'package:test/test.dart';

import 'package:positioning_core/src/indoor/transitions/transition_node.dart';
import 'package:positioning_core/src/indoor/transitions/transition_snapper.dart';

void main() {
  test('TransitionSnapper snaps by transitionId across floors', () {
    final nodes = <TransitionNode>[
      // Same stair shaft across GF and F1
      TransitionNode(
        buildingId: 'ENG_11',
        levelId: 'GF',
        transitionId: 'STAIR_A',
        type: TransitionType.stairs,
        x: 100.0,
        y: 200.0,
      ),
      TransitionNode(
        buildingId: 'ENG_11',
        levelId: 'F1',
        transitionId: 'STAIR_A',
        type: TransitionType.stairs,
        x: 102.0,
        y: 198.0,
      ),

      // Another transition (should not be chosen)
      TransitionNode(
        buildingId: 'ENG_11',
        levelId: 'GF',
        transitionId: 'ELEV_B',
        type: TransitionType.elevator,
        x: 300.0,
        y: 400.0,
      ),
      TransitionNode(
        buildingId: 'ENG_11',
        levelId: 'F1',
        transitionId: 'ELEV_B',
        type: TransitionType.elevator,
        x: 301.0,
        y: 401.0,
      ),
    ];

    final snapper = InMemoryTransitionSnapper(
      nodes: nodes,
      searchRadiusMeters: 6.0,
    );

    // User is near STAIR_A on GF.
    final res = snapper.snapOnLevelChange(
      buildingId: 'ENG_11',
      fromLevelId: 'GF',
      toLevelId: 'F1',
      x: 101.0,
      y: 201.0,
    );

    expect(res, isNotNull);
    expect(res!.transitionId, 'STAIR_A');
    expect(res.type, TransitionType.stairs);

    // Must snap to the target floor node coordinates.
    expect(res.x, 102.0);
    expect(res.y, 198.0);
  });

  test('TransitionSnapper returns null if no near connector on from-level', () {
    final nodes = <TransitionNode>[
      TransitionNode(
        buildingId: 'ENG_11',
        levelId: 'GF',
        transitionId: 'STAIR_A',
        type: TransitionType.stairs,
        x: 100.0,
        y: 200.0,
      ),
      TransitionNode(
        buildingId: 'ENG_11',
        levelId: 'F1',
        transitionId: 'STAIR_A',
        type: TransitionType.stairs,
        x: 102.0,
        y: 198.0,
      ),
    ];

    final snapper = InMemoryTransitionSnapper(
      nodes: nodes,
      searchRadiusMeters: 6.0,
    );

    // Far away from any connector on GF.
    final res = snapper.snapOnLevelChange(
      buildingId: 'ENG_11',
      fromLevelId: 'GF',
      toLevelId: 'F1',
      x: 500.0,
      y: 500.0,
    );

    expect(res, isNull);
  });
}
