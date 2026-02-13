import 'dart:async';

import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

// Fake PDR engine that emits one step per IMU sample (deterministic).
class _FakePdrEngine extends IndoorPdrEngine {
  _FakePdrEngine() : super();

  double _x = 0;

  @override
  PositionEstimate? addImuSample(ImuSample sample) {
    _x += 1.0;
    return PositionEstimate(
      timestamp: sample.timestamp,
      source: PositionSource.pdr,
      x: _x,
      y: 0.0,
      isIndoor: true,
      headingDeg: 0.0,
      speedMps: 1.0,
      accuracyMeters: 8.0,
      isFused: false,
    );
  }
}

// Fake outdoor matcher that maps lon->x (meters-ish) lat->y.
class _FakeOutdoorMatcher extends OutdoorMapMatcher {
  @override
  PositionEstimate addGpsSample(GpsSample sample) {
    return PositionEstimate(
      timestamp: sample.timestamp,
      source: PositionSource.gps,
      latitude: sample.latitude,
      longitude: sample.longitude,
      x: sample.longitude * 100000.0,
      y: sample.latitude * 100000.0,
      accuracyMeters: sample.horizontalAccuracy,
      speedMps: sample.speed,
      headingDeg: sample.bearing,
      isIndoor: false,
      isFused: false,
    );
  }
}

void main() {
  test('PR-11: GPS return after indoor blends instead of jumping', () async {
    final controller = PositioningController(
      pdrEngine: _FakePdrEngine(),
      mapMatcher: _FakeOutdoorMatcher(),
      config: const FusionConfig(
        enableTransitionBlending: true,
        enableConfidenceFusion: true,
        transitionBlendMin: Duration(milliseconds: 800),
        transitionBlendMax: Duration(milliseconds: 800),
        transitionJumpThresholdMeters: 1.0,
      ),
    );

    final out = <PositionEstimate>[];
    final sub = controller.position$.listen(out.add);

    await controller.start();

    // Start indoor.
    controller.setIndoorAnchor(x: 0, y: 0, forceIndoorMode: true);

    // Emit one indoor fused (via IMU).
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    controller.addImuSample(ImuSample(
      timestamp: t0,
      ax: 0,
      ay: 0,
      az: 9.81,
      gx: 0,
      gy: 0,
      gz: 0,
      mx: null,
      my: null,
      mz: null,
    ));

    // Now GPS returns far away (big jump).
    final t1 = t0.add(const Duration(milliseconds: 200));
    controller.addGpsSample(GpsSample(
      timestamp: t1,
      latitude: 0.0,
      longitude: 0.002, // x=200
      horizontalAccuracy: 3.0,
      speed: 1.0,
      bearing: 0.0,
      altitude: null,
    ));

    // Next GPS (same target) within blend window.
    final t2 = t1.add(const Duration(milliseconds: 200));
    controller.addGpsSample(GpsSample(
      timestamp: t2,
      latitude: 0.0,
      longitude: 0.002,
      horizontalAccuracy: 3.0,
      speed: 1.0,
      bearing: 0.0,
      altitude: null,
    ));

    // After blend duration passed, should converge.
    final t3 = t1.add(const Duration(milliseconds: 900));
    controller.addGpsSample(GpsSample(
      timestamp: t3,
      latitude: 0.0,
      longitude: 0.002,
      horizontalAccuracy: 3.0,
      speed: 1.0,
      bearing: 0.0,
      altitude: null,
    ));

    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Find last indoor-ish estimate and first outdoor estimate.
    final indoor = out.where((e) => e.isIndoor).last;
    final gps1 = out.where((e) => !e.isIndoor).first;
    final gpsFinal = out.where((e) => !e.isIndoor).last;

    // Full jump would be ~200m; first outdoor must be closer than the full jump.
    final fullJump = (0.002 * 100000.0 - indoor.x!).abs(); // 200 - ~1
    final firstJump = (gps1.x! - indoor.x!).abs();

    expect(firstJump, lessThan(fullJump)); // blended, not instant snap

    // Converges to target.
    expect((gpsFinal.x! - 200.0).abs(), lessThan(1.0));

    await controller.stop();
    await controller.dispose();
    await sub.cancel();
  });
}
