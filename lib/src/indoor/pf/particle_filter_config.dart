enum ParticleFilterMode { lowPower, balanced, highAccuracy }

class ParticleFilterConfig {
  final ParticleFilterMode mode;

  /// Number of particles.
  final int numParticles;

  /// Motion noise (meters) applied to propagation each update.
  final double stepNoiseSigmaMeters;

  /// Heading noise (degrees) applied when we use observed heading.
  final double headingNoiseSigmaDeg;

  /// Weighting: corridor distance likelihood sigma (meters).
  final double corridorSigmaMeters;

  /// If ESS < (essThresholdFraction * N) => resample.
  final double essThresholdFraction;

  /// Snap output to nearest corridor after best-estimate extraction.
  final bool snapOutputToCorridor;

  /// Hysteresis-like behavior for switching edges:
  /// edges considered adjacent if endpoints within eps.
  final double adjacencyEpsMeters;

  /// Penalties (multipliers) when transitions look impossible.
  final double nonAdjacentPenalty; // e.g. 0.05
  final double turnPenalty; // e.g. 0.15
  final double jumpPenalty; // e.g. 0.20

  /// Maximum allowed "snap jump" (meters) used to penalize switching.
  final double maxSnapJumpMeters;

  /// Turn gate uses motion direction vs candidate edge direction.
  final double maxTurnDegrees;
  final double minMoveForTurnCheckMeters;

  /// Confidence threshold to raise ambiguity flag.
  final double ambiguityThreshold; // e.g. 0.35

  const ParticleFilterConfig({
    required this.mode,
    required this.numParticles,
    required this.stepNoiseSigmaMeters,
    required this.headingNoiseSigmaDeg,
    required this.corridorSigmaMeters,
    required this.essThresholdFraction,
    required this.snapOutputToCorridor,
    required this.adjacencyEpsMeters,
    required this.nonAdjacentPenalty,
    required this.turnPenalty,
    required this.jumpPenalty,
    required this.maxSnapJumpMeters,
    required this.maxTurnDegrees,
    required this.minMoveForTurnCheckMeters,
    required this.ambiguityThreshold,
  });

  factory ParticleFilterConfig.forMode(ParticleFilterMode mode) {
    switch (mode) {
      case ParticleFilterMode.lowPower:
        return const ParticleFilterConfig(
          mode: ParticleFilterMode.lowPower,
          numParticles: 140,
          stepNoiseSigmaMeters: 0.22,
          headingNoiseSigmaDeg: 6.0,
          corridorSigmaMeters: 0.40,
          essThresholdFraction: 0.55,
          snapOutputToCorridor: true,
          adjacencyEpsMeters: 0.35,
          nonAdjacentPenalty: 0.05,
          turnPenalty: 0.18,
          jumpPenalty: 0.25,
          maxSnapJumpMeters: 2.6,
          maxTurnDegrees: 120.0,
          minMoveForTurnCheckMeters: 0.6,
          ambiguityThreshold: 0.33,
        );

      case ParticleFilterMode.highAccuracy:
        return const ParticleFilterConfig(
          mode: ParticleFilterMode.highAccuracy,
          numParticles: 900,
          stepNoiseSigmaMeters: 0.16,
          headingNoiseSigmaDeg: 4.0,
          corridorSigmaMeters: 0.28,
          essThresholdFraction: 0.60,
          snapOutputToCorridor: true,
          adjacencyEpsMeters: 0.35,
          nonAdjacentPenalty: 0.03,
          turnPenalty: 0.12,
          jumpPenalty: 0.18,
          maxSnapJumpMeters: 2.4,
          maxTurnDegrees: 125.0,
          minMoveForTurnCheckMeters: 0.55,
          ambiguityThreshold: 0.40,
        );

      case ParticleFilterMode.balanced:
      default:
        return const ParticleFilterConfig(
          mode: ParticleFilterMode.balanced,
          numParticles: 320,
          stepNoiseSigmaMeters: 0.20,
          headingNoiseSigmaDeg: 5.0,
          corridorSigmaMeters: 0.34,
          essThresholdFraction: 0.58,
          snapOutputToCorridor: true,
          adjacencyEpsMeters: 0.35,
          nonAdjacentPenalty: 0.04,
          turnPenalty: 0.15,
          jumpPenalty: 0.22,
          maxSnapJumpMeters: 2.5,
          maxTurnDegrees: 120.0,
          minMoveForTurnCheckMeters: 0.6,
          ambiguityThreshold: 0.35,
        );
    }
  }
}
