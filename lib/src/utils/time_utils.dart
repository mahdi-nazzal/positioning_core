double _clampDouble(double v, double min, double max) {
  if (v < min) return min;
  if (v > max) return max;
  return v;
}

/// Compute dt (seconds) between two timestamps and clamp it to a safe range.
///
/// - Returns 0.0 if [prev] is null or dt is invalid.
/// - Clamps dt to avoid spikes when timestamps jump (OS scheduling, sensor stalls).
double clampedDtSeconds(
  DateTime? prev,
  DateTime current, {
  double minDtSeconds = 0.001, // 1ms
  double maxDtSeconds = 0.2, // 200ms
}) {
  if (prev == null) return 0.0;

  final us = current.difference(prev).inMicroseconds;
  final dt = us / 1e6;

  if (dt.isNaN || dt.isInfinite) return 0.0;
  if (dt <= 0) return 0.0;

  return _clampDouble(dt, minDtSeconds, maxDtSeconds);
}
