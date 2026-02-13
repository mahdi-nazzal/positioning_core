/// Utilities for safely handling numeric sensor values.
///
/// Keeps NaN/Infinity from leaking into the pipeline.
double safeDouble(
  num? value, {
  double fallback = 0.0,
  double? min,
  double? max,
}) {
  if (value == null) return fallback;

  final v = value.toDouble();
  if (v.isNaN || v.isInfinite) return fallback;

  if (min != null && v < min) return min;
  if (max != null && v > max) return max;

  return v;
}
