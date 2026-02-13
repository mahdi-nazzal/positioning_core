import 'dart:math' as math;

import '../model/position_estimate.dart';

/// Confidence-based fuser (PR-11 Level A).
///
/// We treat accuracyMeters as (rough) 1-sigma and compute weights ~ 1/variance.
/// This gives a stable blend that favors the more reliable sensor.
class ConfidenceFuser {
  const ConfidenceFuser();

  PositionEstimate fuseGpsWithPdr({
    required PositionEstimate gpsFused,
    required PositionEstimate pdrFused,
  }) {
    // Only blend same-frame coordinates.
    final canBlendXY = gpsFused.x != null &&
        gpsFused.y != null &&
        pdrFused.x != null &&
        pdrFused.y != null;

    final canBlendLatLon = gpsFused.latitude != null &&
        gpsFused.longitude != null &&
        pdrFused.latitude != null &&
        pdrFused.longitude != null;

    if (!canBlendXY && !canBlendLatLon) {
      return gpsFused;
    }

    final wGps = _weightFromAccuracy(gpsFused.accuracyMeters);
    final wPdr = _weightFromAccuracy(pdrFused.accuracyMeters);

    final wSum = wGps + wPdr;
    if (wSum <= 0) return gpsFused;

    double blend(double a, double b) => (wGps * a + wPdr * b) / wSum;

    // Combined sigma for independent Gaussians:
    // var = 1/(wGps + wPdr)  => sigma = sqrt(var)
    final fusedSigma = math.sqrt(1.0 / wSum);

    double? x = gpsFused.x;
    double? y = gpsFused.y;
    double? lat = gpsFused.latitude;
    double? lon = gpsFused.longitude;

    if (canBlendXY) {
      x = blend(gpsFused.x!, pdrFused.x!);
      y = blend(gpsFused.y!, pdrFused.y!);
    } else if (canBlendLatLon) {
      lat = blend(gpsFused.latitude!, pdrFused.latitude!);
      lon = blend(gpsFused.longitude!, pdrFused.longitude!);
    }

    // Heading: prefer GPS heading if available; otherwise fall back.
    final headingDeg = gpsFused.headingDeg ?? pdrFused.headingDeg;

    return gpsFused.copyWith(
      x: x,
      y: y,
      latitude: lat,
      longitude: lon,
      headingDeg: headingDeg,
      accuracyMeters:
          fusedSigma.isFinite ? fusedSigma : gpsFused.accuracyMeters,
    );
  }

  double _weightFromAccuracy(double? accMeters) {
    // If missing, assume weak trust.
    final a = (accMeters ?? 50.0);

    // Clamp to avoid insane weights.
    final clamped = a.clamp(1.0, 100.0);

    // weight ~ 1/variance = 1/sigma^2
    return 1.0 / (clamped * clamped);
  }
}
