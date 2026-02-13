enum GraphParticleFilterMode { lowPower, balanced, highAccuracy }

class GraphParticleFilterConfig {
  final GraphParticleFilterMode mode;

  final int numParticles;

  /// Motion noise on step distance (meters)
  final double stepSigmaMeters;

  /// Heading noise (degrees) when branching at junctions / direction selection.
  final double headingSigmaDeg;

  /// Observation sigma (meters): likelihood uses distance(rawXY, particleXY).
  final double obsSigmaMeters;

  /// Resample when ESS/N < threshold.
  final double essThresholdFraction;

  /// If best edge probability below this, consider ambiguous.
  final double edgeDominanceThreshold;

  /// Confidence threshold to set ambiguity flag.
  final double confidenceThreshold;

  /// Junction handling:
  final bool allowUTurn;
  final double uTurnPenalty; // multiplier (e.g., 0.15)

  /// If ds is too small, avoid pointless transitions.
  final double minMoveMeters;

  /// Maximum hops per update (prevents infinite loops with leftover distance).
  final int maxHopsPerUpdate;

  /// Index epsilon used for endpoint clustering.
  final double epsMeters;

  const GraphParticleFilterConfig({
    required this.mode,
    required this.numParticles,
    required this.stepSigmaMeters,
    required this.headingSigmaDeg,
    required this.obsSigmaMeters,
    required this.essThresholdFraction,
    required this.edgeDominanceThreshold,
    required this.confidenceThreshold,
    required this.allowUTurn,
    required this.uTurnPenalty,
    required this.minMoveMeters,
    required this.maxHopsPerUpdate,
    required this.epsMeters,
  });

  factory GraphParticleFilterConfig.forMode(GraphParticleFilterMode mode) {
    switch (mode) {
      case GraphParticleFilterMode.lowPower:
        return const GraphParticleFilterConfig(
          mode: GraphParticleFilterMode.lowPower,
          numParticles: 160,
          stepSigmaMeters: 0.18,
          headingSigmaDeg: 8.0,
          obsSigmaMeters: 0.55,
          essThresholdFraction: 0.55,
          edgeDominanceThreshold: 0.55,
          confidenceThreshold: 0.32,
          allowUTurn: true,
          uTurnPenalty: 0.18,
          minMoveMeters: 0.15,
          maxHopsPerUpdate: 5,
          epsMeters: 0.35,
        );

      case GraphParticleFilterMode.highAccuracy:
        return const GraphParticleFilterConfig(
          mode: GraphParticleFilterMode.highAccuracy,
          numParticles: 900,
          stepSigmaMeters: 0.12,
          headingSigmaDeg: 5.0,
          obsSigmaMeters: 0.40,
          essThresholdFraction: 0.60,
          edgeDominanceThreshold: 0.62,
          confidenceThreshold: 0.40,
          allowUTurn: true,
          uTurnPenalty: 0.14,
          minMoveMeters: 0.12,
          maxHopsPerUpdate: 7,
          epsMeters: 0.35,
        );

      case GraphParticleFilterMode.balanced:
      default:
        return const GraphParticleFilterConfig(
          mode: GraphParticleFilterMode.balanced,
          numParticles: 360,
          stepSigmaMeters: 0.15,
          headingSigmaDeg: 6.0,
          obsSigmaMeters: 0.48,
          essThresholdFraction: 0.58,
          edgeDominanceThreshold: 0.58,
          confidenceThreshold: 0.35,
          allowUTurn: true,
          uTurnPenalty: 0.16,
          minMoveMeters: 0.14,
          maxHopsPerUpdate: 6,
          epsMeters: 0.35,
        );
    }
  }
}
