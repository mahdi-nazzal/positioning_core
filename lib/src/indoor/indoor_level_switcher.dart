/// Optional capability for indoor matchers that can switch active level graphs
/// instantly (without relying only on estimate.levelId).
abstract class IndoorLevelSwitcher {
  /// Set the active building + level context.
  /// If either is null, matcher should consider itself "inactive".
  void setActiveLevel({
    required String? buildingId,
    required String? levelId,
  });
}
