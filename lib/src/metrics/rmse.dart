import 'dart:math' as math;

/// Root mean squared error for a list of scalar errors (already in meters).
double rmse1d(List<double> errorsMeters) {
  if (errorsMeters.isEmpty) return 0.0;
  var sumSq = 0.0;
  for (final e in errorsMeters) {
    sumSq += e * e;
  }
  return math.sqrt(sumSq / errorsMeters.length);
}

/// Root mean squared error for paired 2D points in meters.
double rmse2d({
  required List<double> xs,
  required List<double> ys,
  required List<double> gtXs,
  required List<double> gtYs,
}) {
  final n = xs.length;
  if (n == 0 || gtXs.length != n || gtYs.length != n || ys.length != n) {
    return 0.0;
  }

  var sumSq = 0.0;
  for (var i = 0; i < n; i++) {
    final dx = xs[i] - gtXs[i];
    final dy = ys[i] - gtYs[i];
    sumSq += dx * dx + dy * dy;
  }
  return math.sqrt(sumSq / n);
}
