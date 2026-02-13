import 'package:test/test.dart';

import 'package:positioning_core/src/indoor/indoor_level_switcher.dart';
import 'package:positioning_core/src/indoor/indoor_map_matcher.dart';
import 'package:positioning_core/src/indoor/level_switching_indoor_map_matcher.dart';
import 'package:positioning_core/src/model/position_estimate.dart';

class _FakeMatcher implements IndoorMapMatcher {
  _FakeMatcher(this.tag);

  final String tag;

  @override
  IndoorMapMatchResult match(PositionEstimate raw) {
    final x = raw.x ?? 0.0;
    final y = raw.y ?? 0.0;

    return IndoorMapMatchResult(
      estimate: raw,
      diagnostics: IndoorSnapDiagnostics(
        snapped: false,
        rawX: x,
        rawY: y,
        outX: x,
        outY: y,
        snapDistanceMeters: 0.0,
        activeEdgeId: null,
        decision: 'none',
        switchReason: null,
        extra: <String, dynamic>{'matcherTag': tag},
      ),
    );
  }

  @override
  void reset() {}
}

void main() {
  test('identity fallback returns no-op result when inactive', () {
    final m = LevelSwitchingIndoorMapMatcher(
      builder: (b, l) => _FakeMatcher('$b/$l'),
    );

    final est = PositionEstimate(
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      source: PositionSource.fused,
      x: 10,
      y: 20,
      buildingId: null,
      levelId: null,
      isIndoor: true,
      isFused: true,
    );

    final res = m.match(est);

    expect(res.estimate.x, 10);
    expect(res.estimate.y, 20);
    expect(res.diagnostics.snapped, false);
    expect(res.diagnostics.decision, 'none');
  });

  test('auto-activates by estimate buildingId/levelId on first match', () {
    final m = LevelSwitchingIndoorMapMatcher(
      builder: (b, l) => _FakeMatcher('$b/$l'),
    );

    final est = PositionEstimate(
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      source: PositionSource.fused,
      x: 1,
      y: 2,
      buildingId: 'ENG_11',
      levelId: 'GF',
      isIndoor: true,
      isFused: true,
    );

    final res = m.match(est);
    expect(res.diagnostics.extra['matcherTag'], 'ENG_11/GF');
  });

  test('setActiveLevel switches matcher immediately (PR-10 behavior)', () {
    final m = LevelSwitchingIndoorMapMatcher(
      builder: (b, l) => _FakeMatcher('$b/$l'),
    );

    (m as IndoorLevelSwitcher).setActiveLevel(
      buildingId: 'ENG_11',
      levelId: 'F1',
    );

    final est = PositionEstimate(
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      source: PositionSource.fused,
      x: 5,
      y: 6,
      buildingId: 'ENG_11',
      levelId: 'GF',
      isIndoor: true,
      isFused: true,
    );

    final res = m.match(est);
    expect(res.diagnostics.extra['matcherTag'], 'ENG_11/F1');
  });
}
