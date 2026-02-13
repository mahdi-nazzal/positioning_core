import '../model/position_estimate.dart';
import 'indoor_level_switcher.dart';
import 'indoor_map_matcher.dart';

class LevelSwitchingIndoorMapMatcher
    implements IndoorMapMatcher, IndoorLevelSwitcher {
  LevelSwitchingIndoorMapMatcher({
    required IndoorMapMatcher Function(String buildingId, String levelId)
        builder,
  }) : _builder = builder;

  final IndoorMapMatcher Function(String buildingId, String levelId) _builder;

  final Map<_LevelKey, IndoorMapMatcher> _cache =
      <_LevelKey, IndoorMapMatcher>{};

  IndoorMapMatcher? _active;
  String? _activeBuildingId;
  String? _activeLevelId;

  @override
  void setActiveLevel({
    required String? buildingId,
    required String? levelId,
  }) {
    _activeBuildingId = buildingId;
    _activeLevelId = levelId;

    if (buildingId == null || levelId == null) {
      _active = null;
      return;
    }

    final key = _LevelKey(buildingId, levelId);
    final matcher =
        _cache.putIfAbsent(key, () => _builder(buildingId, levelId));

    // Reset when switching to ensure "immediate respect" of new floor.
    matcher.reset();
    _active = matcher;
  }

  @override
  void reset() {
    _active?.reset();
  }

  @override
  IndoorMapMatchResult match(PositionEstimate estimate) {
    // Auto-activate from estimate if controller didn’t set it.
    final b = estimate.buildingId;
    final l = estimate.levelId;

    if (_active == null && b != null && l != null) {
      setActiveLevel(buildingId: b, levelId: l);
    }

    final a = _active;
    if (a == null) {
      // If no active matcher, return estimate unchanged by delegating to a "no-op"
      // result from your indoor matcher layer.
      // Most projects already have a helper like IndoorMapMatchResult.identity(...)
      // If you don’t, implement it in your indoor_map_matcher.dart (see note below).
      return IndoorMapMatchResult.identity(estimate);
    }

    return a.match(estimate);
  }
}

class _LevelKey {
  final String buildingId;
  final String levelId;

  const _LevelKey(this.buildingId, this.levelId);

  @override
  bool operator ==(Object other) =>
      other is _LevelKey &&
      other.buildingId == buildingId &&
      other.levelId == levelId;

  @override
  int get hashCode => Object.hash(buildingId, levelId);
}
