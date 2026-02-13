import 'package:meta/meta.dart';

/// Configuration for barometer-based floor detection.
@immutable
class FloorDetectionConfig {
  /// Typical floor-to-floor height in meters.
  final double floorHeightMeters;

  /// Candidate threshold as a fraction of floor height.
  final double candidateFrac;

  /// Commit threshold as a fraction of floor height.
  final double commitFrac;

  /// Minimum duration the candidate condition must hold.
  final Duration candidateMinDuration;

  /// Require "settled" (low vertical speed) for this long before committing.
  final Duration settleDuration;

  /// After a commit, ignore new commits for this long.
  final Duration cooldownDuration;

  /// EMA alpha for barometer pressure smoothing.
  final double baroEmaAlpha;

  /// EMA alpha for vertical speed smoothing.
  final double vzEmaAlpha;

  /// EMA alpha for gravity estimation (from accelerometer).
  final double gravityEmaAlpha;

  /// Baseline pressure slow adaptation alpha when stationary.
  final double baselineEmaAlphaWhenStationary;

  /// Consider vertical motion likely if |vz| exceeds this.
  final double minVzForVerticalMotion;

  /// Consider "settled" when |vz| is under this.
  final double settleVzThreshold;

  /// Consider motion likely if vertical accel RMS exceeds this.
  final double minAVertRmsForVerticalMotion;

  /// Consider stationary if vertical accel RMS below this.
  final double stationaryAVertRms;

  /// No steps for at least this long to consider stationary.
  final Duration stationaryNoStepDuration;

  /// Step window duration used for mode classification (stairs vs elevator).
  final Duration stepWindowDuration;

  /// If steps in window >= this => stairs mode.
  final int stairsMinStepsInWindow;

  /// If steps in window <= this and vz is strong => elevator mode.
  final int elevatorMaxStepsInWindow;

  /// Allow multi-floor commits in elevator mode (clamped).
  final int maxFloorsPerEvent;

  const FloorDetectionConfig({
    this.floorHeightMeters = 3.2,
    this.candidateFrac = 0.60,
    this.commitFrac = 0.90,
    this.candidateMinDuration = const Duration(milliseconds: 1500),
    this.settleDuration = const Duration(milliseconds: 1200),
    this.cooldownDuration = const Duration(milliseconds: 4500),
    this.baroEmaAlpha = 0.30,
    this.vzEmaAlpha = 0.35,
    this.gravityEmaAlpha = 0.02,
    this.baselineEmaAlphaWhenStationary = 0.005,
    this.minVzForVerticalMotion = 0.18,
    this.settleVzThreshold = 0.10,
    this.minAVertRmsForVerticalMotion = 0.25,
    this.stationaryAVertRms = 0.15,
    this.stationaryNoStepDuration = const Duration(milliseconds: 1500),
    this.stepWindowDuration = const Duration(seconds: 2),
    this.stairsMinStepsInWindow = 3,
    this.elevatorMaxStepsInWindow = 1,
    this.maxFloorsPerEvent = 3,
  });
}

/// Parses/prints levelId <-> integer floor index.
///
/// Convention:
/// - GF => 0
/// - F1 => +1, F2 => +2, ...
/// - B1 => -1, B2 => -2, ...
abstract class LevelIdCodec {
  int? tryParseIndex(String levelId);
  String formatIndex(int index);
}

/// Default codec: GF / F# / B#
class DefaultLevelIdCodec implements LevelIdCodec {
  const DefaultLevelIdCodec();

  @override
  int? tryParseIndex(String levelId) {
    final s = levelId.trim().toUpperCase();
    if (s == 'GF' || s == 'G' || s == 'GROUND') return 0;

    final b = RegExp(r'^B(\d+)$').firstMatch(s);
    if (b != null) {
      final n = int.tryParse(b.group(1)!);
      if (n == null) return null;
      return -n;
    }

    final f = RegExp(r'^F(\d+)$').firstMatch(s);
    if (f != null) {
      final n = int.tryParse(f.group(1)!);
      if (n == null) return null;
      return n;
    }

    return null;
  }

  @override
  String formatIndex(int index) {
    if (index == 0) return 'GF';
    if (index < 0) return 'B${-index}';
    return 'F$index';
  }
}
