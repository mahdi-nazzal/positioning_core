import 'dart:math' as math;

import '../model/barometer_sample.dart';
import 'floor_detection_config.dart';

class BaroAltimeterState {
  final double pressureSmoothedHpa;
  final double altitudeMeters; // relative
  final double verticalSpeedMps; // smoothed
  final double baselineHpa;

  const BaroAltimeterState({
    required this.pressureSmoothedHpa,
    required this.altitudeMeters,
    required this.verticalSpeedMps,
    required this.baselineHpa,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'pressureSmoothedHpa': pressureSmoothedHpa,
        'altitudeMeters': altitudeMeters,
        'verticalSpeedMps': verticalSpeedMps,
        'baselineHpa': baselineHpa,
      };
}

/// Production-safe baro altimeter:
/// - smooth pressure
/// - keep baseline (p0) and allow slow adaptation ONLY when stationary
/// - output relative altitude and vertical speed (vz)
class BaroAltimeter {
  final FloorDetectionConfig config;

  double? _p0Hpa;
  double? _pSmoothHpa;

  double _altBiasMeters = 0.0;

  double? _altMeters;
  double? _vzMps;
  DateTime? _lastTs;

  BaroAltimeter({required this.config});

  void reset() {
    _p0Hpa = null;
    _pSmoothHpa = null;
    _altBiasMeters = 0.0;
    _altMeters = null;
    _vzMps = null;
    _lastTs = null;
  }

  BaroAltimeterState update(
    BarometerSample sample, {
    required bool stationary,
  }) {
    final p = sample.pressureHpa;

    _p0Hpa ??= p;
    _pSmoothHpa ??= p;

    // Smooth pressure.
    final ps = _ema(_pSmoothHpa!, p, config.baroEmaAlpha);
    _pSmoothHpa = ps;

    // Convert to altitude relative to baseline.
    final p0 = _p0Hpa!;
    final rawAlt = _pressureToRelativeAltitudeMeters(ps, p0) + _altBiasMeters;

    // Vertical speed.
    double vz = _vzMps ?? 0.0;
    if (_altMeters != null && _lastTs != null) {
      final dt = sample.timestamp.difference(_lastTs!).inMicroseconds / 1e6;
      if (dt > 1e-6) {
        final instVz = (rawAlt - _altMeters!) / dt;
        vz = _ema(vz, instVz, config.vzEmaAlpha);
      }
    }

    _altMeters = rawAlt;
    _vzMps = vz;
    _lastTs = sample.timestamp;

    // Baseline adaptation only when stationary.
    if (stationary) {
      final newP0 = _ema(p0, ps, config.baselineEmaAlphaWhenStationary);

      // Preserve altitude continuity when baseline changes.
      final oldAltNoBias = _pressureToRelativeAltitudeMeters(ps, p0);
      final newAltNoBias = _pressureToRelativeAltitudeMeters(ps, newP0);
      _altBiasMeters += oldAltNoBias - newAltNoBias;

      _p0Hpa = newP0;
    }

    return BaroAltimeterState(
      pressureSmoothedHpa: _pSmoothHpa!,
      altitudeMeters: _altMeters ?? 0.0,
      verticalSpeedMps: _vzMps ?? 0.0,
      baselineHpa: _p0Hpa!,
    );
  }

  static double _ema(double prev, double x, double alpha) {
    final a = alpha.clamp(0.0, 1.0);
    return prev + a * (x - prev);
  }

  static double _pressureToRelativeAltitudeMeters(double pHpa, double p0Hpa) {
    // Standard atmosphere approximation.
    // Works well for relative differences over small altitude ranges.
    const k = 0.190294957;
    final ratio = (pHpa / p0Hpa).clamp(1e-9, 1e9);
    final powv = math.pow(ratio, k).toDouble();
    return 44330.0 * (1.0 - powv);
  }
}
