import 'package:positioning_core/positioning_core.dart';
import 'package:test/test.dart';

void main() {
  test('Golden: outdoor replay RMSE stays near zero on synthetic trace',
      () async {
    final logger = TraceRecordingLogger(metadata: {'test': 'golden_outdoor'});
    final controller = PositioningController(
      pdrEngine: IndoorPdrEngine(),
      mapMatcher: OutdoorMapMatcher(graph: null),
      logger: logger,
    );

    await controller.start();

    // Synthetic "ground truth" == injected GPS samples
    final gtLat = <double>[];
    final gtLon = <double>[];

    final t0 = DateTime.utc(2025, 1, 1, 0, 0, 0);
    for (var i = 0; i < 20; i++) {
      final lat = 32.0 + i * 1e-6;
      final lon = 35.0 + i * 1e-6;
      gtLat.add(lat);
      gtLon.add(lon);

      controller.addGpsSample(
        GpsSample(
          timestamp: t0.add(Duration(seconds: i)),
          latitude: lat,
          longitude: lon,
          horizontalAccuracy: 3.0,
          speed: 1.0,
          bearing: 90.0,
        ),
      );
    }

    await controller.stop();

    final jsonl = logger.toJsonLines();

    final replayController = PositioningController(
      pdrEngine: IndoorPdrEngine(),
      mapMatcher: OutdoorMapMatcher(graph: null),
    );
    final replayer = PositioningReplayer(replayController);
    final estimates = await replayer.replayJsonLines(jsonl);

    final report = outdoorRmseVsGroundTruth(
      estimates: estimates.where((e) => e.isFused).toList(),
      gtLatDeg: gtLat,
      gtLonDeg: gtLon,
    );

    // Conservative golden threshold: synthetic trace should be extremely close.
    expect(report.sampleCount, greaterThan(0));
    expect(report.rmseMeters, lessThan(0.5));
  });
}
