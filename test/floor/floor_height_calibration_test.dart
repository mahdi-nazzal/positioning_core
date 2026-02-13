import 'dart:math' as math;

import 'package:test/test.dart';

import 'package:positioning_core/src/floor/floor_change_detector.dart';
import 'package:positioning_core/src/floor/floor_detection_config.dart';
import 'package:positioning_core/src/floor/floor_height_model.dart';
import 'package:positioning_core/src/model/barometer_sample.dart';
import 'package:positioning_core/src/model/imu_sample.dart';

double pressureForAlt(double altM, double p0Hpa) {
  // Same helper used in your other floor tests.
  const k = 0.190294957;
  final base = (1.0 - (altM / 44330.0)).clamp(1e-9, 1.0);
  return p0Hpa * math.pow(base, 1.0 / k).toDouble();
}

ImuSample imuAt(DateTime t, {double az = 9.81}) {
  return ImuSample(
    timestamp: t,
    ax: 0,
    ay: 0,
    az: az,
    gx: 0,
    gy: 0,
    gz: 0,
    mx: null,
    my: null,
    mz: null,
  );
}

void main() {
  test(
      'Floor height calibration updates per-building model and affects floor rounding',
      () {
    // We start with default 3.2m, then calibrate to 3.8m for ENG_11.
    final model = MapFloorHeightModel(defaultMeters: 3.2);

    final cfg = FloorDetectionConfig(
      floorHeightMeters: 3.2,
      candidateMinDuration: const Duration(milliseconds: 1200),
      settleDuration: const Duration(milliseconds: 900),
      cooldownDuration: const Duration(milliseconds: 3000),
      // keep tests stable (same values used in PR-9 tests)
      baroEmaAlpha: 0.30,
      vzEmaAlpha: 0.35,
    );

    final det = FloorChangeDetector(
      config: cfg,
      floorHeightModel: model,
    );

    det.setContext(buildingId: 'ENG_11', levelId: 'GF');

    // Calibrate: GF -> F2 observed delta altitude 7.6m => 3.8m per floor.
    det.calibrateFloorHeightWithKnownLevels(
      buildingId: 'ENG_11',
      fromLevelId: 'GF',
      toLevelId: 'F2',
      observedDeltaAltMeters: 7.6,
      smoothingAlpha: 1.0, // apply instantly for test determinism
    );

    final h = model.floorHeightMeters(buildingId: 'ENG_11');
    expect((h - 3.8).abs() < 1e-9, true);

    // Now simulate an elevator-like move of +4.9m.
    // With calibrated 3.8m/floor => 4.9/3.8 = 1.29 => should commit 1 floor (F1).
    // With old 3.2m/floor => 4.9/3.2 = 1.53 => would wrongly round to 2 floors.
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    const p0 = 1013.25;

    dynamic
        event; // FloorChangeEvent (kept dynamic so test compiles even if you renamed class)

    // Phase A: ride up to 4.9m over 9s.
    for (var ms = 0; ms <= 9000; ms += 100) {
      final t = t0.add(Duration(milliseconds: ms));

      // Elevator impulses: start and stop.
      double impulse = 0.0;
      if (ms < 300) impulse = 1.8;
      if (ms > 8200) impulse = -1.6;

      det.addImuSample(imuAt(t, az: 9.81 + impulse));

      if (ms % 200 == 0) {
        final alt = 4.9 * (ms / 9000.0);
        final p = pressureForAlt(alt, p0);
        event ??= det.addBarometerSample(
          BarometerSample(timestamp: t, pressureHpa: p),
        );
      }
    }

    // Phase B: settle plateau 3s at final altitude.
    for (var ms = 9200; ms <= 12200; ms += 100) {
      final t = t0.add(Duration(milliseconds: ms));
      det.addImuSample(imuAt(t, az: 9.81));

      if (ms % 200 == 0) {
        final p = pressureForAlt(4.9, p0);
        event ??= det.addBarometerSample(
          BarometerSample(timestamp: t, pressureHpa: p),
        );
      }
    }

    expect(event, isNotNull);
    expect(event.newLevelId, 'F1'); // calibrated result
    expect(event.deltaFloors, 1);
  });
}
