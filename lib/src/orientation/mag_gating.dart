import 'dart:math' as math;

import '../utils/num_safety.dart';

class MagGating {
  /// Expected magnetic field magnitude on Earth ~25–65 µT (varies by location).
  /// We'll use a safe wide range + relative deviation gating.
  final double minNormUt;
  final double maxNormUt;

  /// If norm deviates more than this ratio from baseline, treat as disturbed.
  /// Example: 0.35 => ±35% deviation.
  final double maxRelativeDeviation;

  /// EMA smoothing for baseline magnitude.
  final double emaAlpha;

  double? _baselineNormUt;

  MagGating({
    this.minNormUt = 15.0,
    this.maxNormUt = 80.0,
    this.maxRelativeDeviation = 0.35,
    this.emaAlpha = 0.05,
  });

  bool isMagValid(double? mx, double? my, double? mz) {
    final x = safeDouble(mx, fallback: double.nan);
    final y = safeDouble(my, fallback: double.nan);
    final z = safeDouble(mz, fallback: double.nan);

    if (x.isNaN || y.isNaN || z.isNaN) return false;

    final norm = math.sqrt(x * x + y * y + z * z);
    if (norm.isNaN || norm.isInfinite) return false;

    if (norm < minNormUt || norm > maxNormUt) return false;

    final base = _baselineNormUt;
    if (base == null) {
      _baselineNormUt = norm;
      return true;
    }

    final relDev = ((norm - base).abs()) / base;
    if (relDev > maxRelativeDeviation) {
      // Do not update baseline when disturbed.
      return false;
    }

    // Update baseline when valid.
    _baselineNormUt = (1.0 - emaAlpha) * base + emaAlpha * norm;
    return true;
  }

  void reset() {
    _baselineNormUt = null;
  }
}
