import 'package:meta/meta.dart';

/// FusionConfig
///
/// Configuration parameters controlling:
/// - when GPS is considered "good" for outdoor mode,
/// - when GPS is considered stale,
/// - how many PDR steps are needed before we trust indoor mode,
/// - how to smoothly blend transitions indoor<->outdoor (PR-11).
@immutable
class FusionConfig {
  /// Maximum GPS horizontal accuracy (meters) considered "good".
  final double gpsGoodAccuracyThreshold;

  /// Duration after the last GPS fix after which GPS is considered stale.
  final Duration gpsStaleDuration;

  /// Minimum number of PDR steps since the last GPS fix required to switch to indoor.
  final int indoorStepCountThreshold;

  // ---------------------------------------------------------------------------
  // PR-11: Transition smoothing + confidence blending
  // ---------------------------------------------------------------------------

  /// If true, when GPS returns after indoor, we blend outputs over a short window
  /// instead of jumping.
  final bool enableTransitionBlending;

  /// Minimum blend duration (good GPS => fast convergence).
  final Duration transitionBlendMin;

  /// Maximum blend duration (poor GPS => slower convergence).
  final Duration transitionBlendMax;

  /// GPS accuracy considered "good" for fast blending.
  final double gpsAccuracyGoodForBlend;

  /// GPS accuracy considered "bad" for slow blending.
  final double gpsAccuracyBadForBlend;

  /// Ignore blending if the position jump is below this threshold (meters).
  final double transitionJumpThresholdMeters;

  /// When a GPS sample arrives and we have a recent PDR estimate, fuse x/y by
  /// confidence weights (PR-11 Level A).
  final bool enableConfidenceFusion;

  /// Only fuse GPS with PDR if PDR estimate is within this recency window.
  final Duration pdrFusionRecencyWindow;

  const FusionConfig({
    this.gpsGoodAccuracyThreshold = 15.0,
    this.gpsStaleDuration = const Duration(seconds: 5),
    this.indoorStepCountThreshold = 3,

    // PR-11 defaults (safe + effective)
    this.enableTransitionBlending = true,
    this.transitionBlendMin = const Duration(milliseconds: 500),
    this.transitionBlendMax = const Duration(seconds: 2500),
    this.gpsAccuracyGoodForBlend = 4.0,
    this.gpsAccuracyBadForBlend = 25.0,
    this.transitionJumpThresholdMeters = 3.0,
    this.enableConfidenceFusion = true,
    this.pdrFusionRecencyWindow = const Duration(seconds: 2),
  });
}
