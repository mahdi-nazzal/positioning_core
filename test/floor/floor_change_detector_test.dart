import 'dart:math' as math;

import 'package:test/test.dart';

import 'package:positioning_core/src/floor/floor_change_detector.dart';
import 'package:positioning_core/src/floor/floor_detection_config.dart';
import 'package:positioning_core/src/model/barometer_sample.dart';
import 'package:positioning_core/src/model/imu_sample.dart';

double pressureForAlt(double altM, double p0Hpa) {
  const k = 0.190294957;
  final base = (1.0 - (altM / 44330.0)).clamp(1e-9, 1.0);
  return p0Hpa * math.pow(base, 1.0 / k).toDouble();
}

ImuSample imuAt(DateTime t, {double ax = 0, double ay = 0, double az = 9.81}) {
  return ImuSample(
    timestamp: t,
    ax: ax,
    ay: ay,
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
  test('Stairs up: commits GF -> F1 once without oscillation', () {
    final cfg = FloorDetectionConfig(
      floorHeightMeters: 3.2,
      candidateMinDuration: const Duration(milliseconds: 1200),
      settleDuration: const Duration(milliseconds: 900),
      cooldownDuration: const Duration(milliseconds: 3000),
    );

    final det = FloorChangeDetector(config: cfg);
    det.setContext(buildingId: 'ENG_11', levelId: 'GF');

    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    const p0 = 1013.25;

    FloorChangeEvent? event;

    // Phase A: ascend to ~1 floor (3.3m) over 14s
    for (var ms = 0; ms <= 14000; ms += 100) {
      final t = t0.add(Duration(milliseconds: ms));

      // IMU: mild vertical dynamics to keep aVertRms non-zero
      final pulse = (ms % 650) < 80 ? 1.2 : 0.0;
      det.addImuSample(imuAt(t, az: 9.81 + pulse));

      // Steps ~ every 650ms
      if (ms % 650 == 0 && ms > 0) {
        det.notifyStep(t);
      }

      // Baro at 5Hz
      if (ms % 200 == 0) {
        final alt = 3.3 * (ms / 14000.0);
        final p = pressureForAlt(alt, p0);
        event ??= det.addBarometerSample(
          BarometerSample(timestamp: t, pressureHpa: p),
        );
      }
    }

    // Phase B: settle plateau for 3s (constant altitude) so vz -> 0
    for (var ms = 14200; ms <= 17200; ms += 100) {
      final t = t0.add(Duration(milliseconds: ms));

      // Stationary IMU
      det.addImuSample(imuAt(t, az: 9.81));

      if (ms % 200 == 0) {
        final p = pressureForAlt(3.3, p0);
        event ??= det.addBarometerSample(
          BarometerSample(timestamp: t, pressureHpa: p),
        );
      }
    }

    expect(event, isNotNull);
    expect(event!.newLevelId, 'F1');
    expect(event!.deltaFloors, 1);
  });

  test('Elevator up 2 floors: commits GF -> F2', () {
    final cfg = FloorDetectionConfig(
      baroEmaAlpha: 0.30,
      vzEmaAlpha: 0.35,
      floorHeightMeters: 3.2,
      candidateMinDuration: const Duration(milliseconds: 1200),
      settleDuration: const Duration(milliseconds: 900),
      cooldownDuration: const Duration(milliseconds: 3000),
    );

    final det = FloorChangeDetector(config: cfg);
    det.setContext(buildingId: 'ENG_11', levelId: 'GF');

    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    const p0 = 1013.25;

    FloorChangeEvent? event;

    // Phase A: elevator ride to +6.4m over 9s
    for (var ms = 0; ms <= 9000; ms += 100) {
      final t = t0.add(Duration(milliseconds: ms));

      // IMU: start impulse + stop impulse
      double impulse = 0.0;
      if (ms < 300) impulse = 1.8;
      if (ms > 8200) impulse = -1.6;
      det.addImuSample(imuAt(t, az: 9.81 + impulse));

      if (ms % 200 == 0) {
        final alt = 6.4 * (ms / 9000.0);
        final p = pressureForAlt(alt, p0);
        event ??= det.addBarometerSample(
          BarometerSample(timestamp: t, pressureHpa: p),
        );
      }
    }

    // Phase B: settle plateau 3s at final altitude (vz -> 0)
    for (var ms = 9200; ms <= 12200; ms += 100) {
      final t = t0.add(Duration(milliseconds: ms));
      det.addImuSample(imuAt(t, az: 9.81));

      if (ms % 200 == 0) {
        final p = pressureForAlt(6.4, p0);
        event ??= det.addBarometerSample(
          BarometerSample(timestamp: t, pressureHpa: p),
        );
      }
    }

    expect(event, isNotNull);
    expect(event!.newLevelId, 'F2');
    expect(event!.deltaFloors, 2);
  });

  test('Drift only: no steps + low motion => no floor change', () {
    final det = FloorChangeDetector();
    det.setContext(buildingId: 'ENG_11', levelId: 'GF');

    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    const p0 = 1013.25;

    FloorChangeEvent? event;

    // 90s drift by 1.2m without motion.
    for (var ms = 0; ms <= 90000; ms += 200) {
      final t = t0.add(Duration(milliseconds: ms));

      det.addImuSample(imuAt(t, az: 9.81)); // stationary

      final alt = 1.2 * (ms / 90000.0);
      final p = pressureForAlt(alt, p0);
      event ??= det.addBarometerSample(
        BarometerSample(timestamp: t, pressureHpa: p),
      );
    }

    expect(event, isNull);
  });
}
