import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:positioning_core/positioning_core.dart';

import '../../services/sensors/imu_feed.dart';
import '../../services/sensors/location_feed.dart';
import '../../services/storage/file_exporter.dart';
import '../../services/storage/trace_store.dart';
import '../../services/sensors/barometer_feed.dart';
import '../../core/campus_level_id_codec.dart'; // adjust path


class IndoorAnchorPreset {
  final String label;
  final double x;
  final double y;
  final String? buildingId;
  final String? levelId;
  final double? headingDeg;

  const IndoorAnchorPreset({
    required this.label,
    required this.x,
    required this.y,
    this.buildingId,
    this.levelId,
    this.headingDeg,
  });
}

class SessionController extends ChangeNotifier {
  SessionController({
    required LocationFeed locationFeed,
    required ImuFeed imuFeed,
    required BarometerFeed barometerFeed,
    required TraceStore traceStore,
    required FileExporter fileExporter,
  })  : _locationFeed = locationFeed,
        _imuFeed = imuFeed,
        _barometerFeed = barometerFeed,
        _traceStore = traceStore,
        _fileExporter = fileExporter {
    _buildEngine();
  }


  final LocationFeed _locationFeed;
  final ImuFeed _imuFeed;
  final TraceStore _traceStore;
  final FileExporter _fileExporter;
  final BarometerFeed _barometerFeed; // ✅

  StreamSubscription<BarometerSample>? _baroSub; // ✅
  bool barometerEnabled = false; // optional toggle later
  late PositioningController _engine;
  StreamSubscription<PositionEstimate>? _engineSub;

  StreamSubscription<GpsSample>? _gpsSub;
  StreamSubscription<ImuSample>? _imuSub;

  FloorChangeEvent? lastFloorEvent;

  bool _sessionRunning = false;
  bool get sessionRunning => _sessionRunning;

  bool _gpsEnabled = true;
  bool get gpsEnabled => _gpsEnabled;

  bool _imuEnabled = true;
  bool get imuEnabled => _imuEnabled;

  bool _recordingEnabled = true;
  bool get recordingEnabled => _recordingEnabled;

  EnvironmentMode? overrideMode; // null = auto
  double manualStepLength = 0.70;

  PositionEstimate? lastEstimate;
  final List<PositionEstimate> recent = <PositionEstimate>[];

  // Barometer simulator
  double simulatedPressureHpa = 1013.25;

  // For “Test E” verification
  int traceEventCount = 0;

  // Simple async queue so toggles don’t race each other
  Future<void> _toggleQueue = Future<void>.value();

  List<IndoorAnchorPreset> get presets => const [
    IndoorAnchorPreset(
      label: 'ENG Entrance (placeholder) • GF',
      x: 0,
      y: 0,
      buildingId: 'ENG_11',
      levelId: 'GF',
      headingDeg: 0,
    ),
    IndoorAnchorPreset(
      label: 'Room 11G0110 (placeholder)',
      x: 18,
      y: 6,
      buildingId: 'ENG_11',
      levelId: 'GF',
      headingDeg: 90,
    ),
    IndoorAnchorPreset(
      label: 'Room 11G0060 (placeholder)',
      x: 8,
      y: 22,
      buildingId: 'ENG_11',
      levelId: 'GF',
      headingDeg: 180,
    ),
  ];

  PositioningController get engine => _engine;


  void _buildEngine() {
    final floorDetector = FloorChangeDetector(
      levelIdCodec: const CampusLevelIdCodec(),
    );
    debugPrint('[FloorDetector] initial levelIndex=${floorDetector.currentLevelIndex} '
        'levelId=${floorDetector.currentLevelId}');
    final traceLogger = TraceRecordingLogger(
      metadata: <String, dynamic>{
        'app': 'positioning_core_example',
        'ts': DateTime.now().toIso8601String(),
      },
    );

    _traceStore.attach(traceLogger);
    _traceStore.setGateEnabled(_recordingEnabled);

    final pdr = IndoorPdrEngine(
      useDynamicStepLength: false,
      stepLengthMeters: manualStepLength,
    );

    final matcher = OutdoorMapMatcher(
      graph: null,
      config: const OutdoorMapMatcherConfig(
        enableSmoothing: false,
        enableGraphSnap: true,
      ),
    );

    _engine = PositioningController(
      pdrEngine: pdr,
      mapMatcher: matcher,
      logger:_traceStore.gate,
      config: const FusionConfig(),
      floorDetector: floorDetector,
      onFloorChanged: (e) {
        lastFloorEvent = e;
        debugPrint('[FloorChanged] newLevelId=${e.newLevelId} '
            'deltaFloors=${e.deltaFloors} confidence=${e.confidence.toStringAsFixed(2)} '
            'mode=${e.mode.name}');
        notifyListeners();
      },
      // transitionSnapper: <later when you add transition nodes>,
    );


    _engineSub?.cancel();
    _engineSub = _engine.position$.listen((e) {
      // Minimal dedupe: skip exact duplicates (same ts + source + indoor)
      final prev = lastEstimate;
      final isDup = prev != null &&
          prev.timestamp == e.timestamp &&
          prev.source == e.source &&
          prev.isIndoor == e.isIndoor;

      if (!isDup) {
        lastEstimate = e;
        recent.add(e);
        if (recent.length > 80) {
          recent.removeRange(0, recent.length - 80);
        }
      }

      traceEventCount = _traceStore.eventCount;
      notifyListeners();
    });
  }

  Future<void> startSession() async {
    if (_sessionRunning) return;

    _sessionRunning = true;
    notifyListeners();

    await _engine.start();

    if (_gpsEnabled) {
      await _startGps();
    }
    if (_imuEnabled) {
      await _startImu();
    }
    if (barometerEnabled) {
      await _barometerFeed.start();
      _baroSub = _barometerFeed.samples.listen(_engine.addBarometerSample);
    }

  }

  Future<void> stopSession() async {
    if (!_sessionRunning) return;

    _sessionRunning = false;
    notifyListeners();

    await _stopGps();
    await _stopImu();
    await _baroSub?.cancel();
    _baroSub = null;
    await _barometerFeed.stop();

    await _engine.stop();
  }

  Future<void> _startGps() async {
    if (_gpsSub != null) return;
    await _locationFeed.start();
    _gpsSub = _locationFeed.samples.listen(_engine.addGpsSample);
  }

  Future<void> _stopGps() async {
    await _gpsSub?.cancel();
    _gpsSub = null;
    await _locationFeed.stop();
  }

  Future<void> _startImu() async {
    if (_imuSub != null) return;
    await _imuFeed.start();
    _imuSub = _imuFeed.samples.listen(_engine.addImuSample);
  }

  Future<void> _stopImu() async {
    await _imuSub?.cancel();
    _imuSub = null;
    await _imuFeed.stop();
  }

  Future<void> rebuildForNewRecording() async {
    final wasRunning = _sessionRunning;
    await stopSession();

    _buildEngine();

    if (wasRunning) {
      await startSession();
    }
  }

  // ✅ Real-time toggle: starts/stops streams immediately if session is running.
  Future<void> setGpsEnabled(bool v) {
    return _toggleQueue = _toggleQueue.then((_) async {
      if (_gpsEnabled == v) return;
      _gpsEnabled = v;
      notifyListeners();

      if (!_sessionRunning) return;
      if (v) {
        await _startGps();
      } else {
        await _stopGps();
      }
    });
  }

  Future<void> setImuEnabled(bool v) {
    return _toggleQueue = _toggleQueue.then((_) async {
      if (_imuEnabled == v) return;
      _imuEnabled = v;
      notifyListeners();

      if (!_sessionRunning) return;
      if (v) {
        await _startImu();
      } else {
        await _stopImu();
      }
    });
  }
  Timer? _baroSimTimer;


  void simulateFloorChange({required int deltaFloors}) {
    final a = _lastAnchor;
    if (a == null || a.buildingId == null || a.levelId == null) {
      debugPrint('[FloorSim] No anchor yet.');
      return;
    }

    const codec = CampusLevelIdCodec();
    final idx = codec.tryParseIndex(a.levelId!) ?? 0;
    final newId = codec.formatIndex(idx + deltaFloors);

    debugPrint('[FloorSim] ${a.levelId} -> $newId (delta=$deltaFloors)');

    _engine.setIndoorAnchor(
      x: a.x,
      y: a.y,
      buildingId: a.buildingId,
      levelId: newId,
      headingDeg: a.headingDeg,
      forceIndoorMode: true,
      emitInitial: true,
    );

    // keep anchor updated
    _lastAnchor = IndoorAnchorPreset(
      label: a.label,
      x: a.x,
      y: a.y,
      buildingId: a.buildingId,
      levelId: newId,
      headingDeg: a.headingDeg,
    );

    notifyListeners();
  }

  Future<void> setBarometerEnabled(bool v) async {
    barometerEnabled = v;
    notifyListeners();

    if (!sessionRunning) return;

    if (v) {
      await _barometerFeed.start();
      _baroSub?.cancel();
      _baroSub = _barometerFeed.samples.listen(_engine.addBarometerSample);
    } else {
      await _baroSub?.cancel();
      _baroSub = null;
      await _barometerFeed.stop();
    }
  }
  void setRecordingEnabled(bool v) {
    _recordingEnabled = v;
    _traceStore.setGateEnabled(v); // ✅ now controls the engine logger
    notifyListeners();
  }

  void setOverride(EnvironmentMode? mode) {
    overrideMode = mode;
    _engine.setEnvironmentOverride(mode);
    notifyListeners();
  }

  void setManualStepLength(double meters) {
    manualStepLength = meters;
    _engine.setPdrStepLengthMeters(meters);
    notifyListeners();
  }

  IndoorAnchorPreset? _lastAnchor;
  void setIndoorAnchorPreset(IndoorAnchorPreset p) {
    _lastAnchor = p;

    _engine.setIndoorAnchor(
      x: p.x,
      y: p.y,
      buildingId: p.buildingId,
      levelId: p.levelId,
      headingDeg: p.headingDeg,
      forceIndoorMode: true,
      emitInitial: true,
    );

    debugPrint('[Anchor] building=${p.buildingId} level=${p.levelId}');
    notifyListeners();
  }

  void clearIndoorAnchor() {
    _engine.clearIndoorAnchor();
    notifyListeners();
  }

  void injectBarometer(double pressureHpa) {
    simulatedPressureHpa = pressureHpa;
    // _engine.addBarometerSample(
    //   BarometerSample(
    //     timestamp: DateTime.now(),
    //     pressureHpa: simulatedPressureHpa,
    //   ),
    // );
    // Push into BarometerFeed:
    _barometerFeed.inject(simulatedPressureHpa);

    notifyListeners();
  }

  Future<String?> exportTraceToFile() async {
    final jsonl = _traceStore.currentJsonl;
    if (jsonl == null || jsonl.trim().isEmpty) return null;
    return _fileExporter.writeJsonl(jsonl);
  }
  Future<String?> saveTraceToAppStorage() async {
    final jsonl = _traceStore.currentJsonl;
    if (jsonl == null || jsonl.trim().isEmpty) return null;
    return _fileExporter.writeJsonl(jsonl);
  }

  Future<String?> saveTraceAs() async {
    final jsonl = _traceStore.currentJsonl;
    if (jsonl == null || jsonl.trim().isEmpty) return null;
    return _fileExporter.saveJsonlAs(jsonl);
  }

  Future<void> shareTrace() async {
    final jsonl = _traceStore.currentJsonl;
    if (jsonl == null || jsonl.trim().isEmpty) return;
    await _fileExporter.shareJsonl(jsonl);
  }
  @override
  void dispose() {
    // avoid async dispose; stop what we can safely
    unawaited(_engineSub?.cancel());
    unawaited(_gpsSub?.cancel());
    unawaited(_imuSub?.cancel());
    unawaited(_locationFeed.stop());
    unawaited(_imuFeed.stop());
    unawaited(_engine.dispose());
    super.dispose();
  }
}
