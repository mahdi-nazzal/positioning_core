import 'dart:math' as math;

/// Earth radius in meters.
const double _earthRadiusM = 6371000.0;

/// Great-circle distance between two GPS points using the Haversine formula.
double haversineMeters({
  required double lat1Deg,
  required double lon1Deg,
  required double lat2Deg,
  required double lon2Deg,
}) {
  final lat1 = lat1Deg * math.pi / 180.0;
  final lon1 = lon1Deg * math.pi / 180.0;
  final lat2 = lat2Deg * math.pi / 180.0;
  final lon2 = lon2Deg * math.pi / 180.0;

  final dLat = lat2 - lat1;
  final dLon = lon2 - lon1;

  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);

  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return _earthRadiusM * c;
}
