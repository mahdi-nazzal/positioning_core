import '../model/position_estimate.dart';
import 'haversine.dart';
import 'rmse.dart';

class MetricsReport {
  final double rmseMeters;
  final int sampleCount;

  const MetricsReport({
    required this.rmseMeters,
    required this.sampleCount,
  });

  @override
  String toString() =>
      'MetricsReport(rmseMeters: $rmseMeters, n: $sampleCount)';
}

/// Outdoor RMSE vs ground truth GPS points (same index alignment).
MetricsReport outdoorRmseVsGroundTruth({
  required List<PositionEstimate> estimates,
  required List<double> gtLatDeg,
  required List<double> gtLonDeg,
}) {
  final errors = <double>[];

  final n = estimates.length;
  if (n == 0 || gtLatDeg.length != n || gtLonDeg.length != n) {
    return const MetricsReport(rmseMeters: 0.0, sampleCount: 0);
  }

  for (var i = 0; i < n; i++) {
    final e = estimates[i];
    final lat = e.latitude;
    final lon = e.longitude;
    if (lat == null || lon == null) continue;

    final d = haversineMeters(
      lat1Deg: lat,
      lon1Deg: lon,
      lat2Deg: gtLatDeg[i],
      lon2Deg: gtLonDeg[i],
    );
    errors.add(d);
  }

  return MetricsReport(rmseMeters: rmse1d(errors), sampleCount: errors.length);
}

/// Indoor 2D RMSE vs ground truth local points (same index alignment).
MetricsReport indoorRmse2dVsGroundTruth({
  required List<PositionEstimate> estimates,
  required List<double> gtX,
  required List<double> gtY,
}) {
  final xs = <double>[];
  final ys = <double>[];
  final gx = <double>[];
  final gy = <double>[];

  final n = estimates.length;
  if (n == 0 || gtX.length != n || gtY.length != n) {
    return const MetricsReport(rmseMeters: 0.0, sampleCount: 0);
  }

  for (var i = 0; i < n; i++) {
    final e = estimates[i];
    final x = e.x;
    final y = e.y;
    if (x == null || y == null) continue;

    xs.add(x);
    ys.add(y);
    gx.add(gtX[i]);
    gy.add(gtY[i]);
  }

  return MetricsReport(
    rmseMeters: rmse2d(xs: xs, ys: ys, gtXs: gx, gtYs: gy),
    sampleCount: xs.length,
  );
}
