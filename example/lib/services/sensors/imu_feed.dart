import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:positioning_core/positioning_core.dart';

class ImuFeed {
  final StreamController<ImuSample> _controller =
  StreamController<ImuSample>.broadcast();

  Stream<ImuSample> get samples => _controller.stream;

  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  double _ax = 0, _ay = 0, _az = 0;
  double _gx = 0, _gy = 0, _gz = 0;

  Timer? _tick;

  Future<void> start({Duration period = const Duration(milliseconds: 20)}) async {
    await stop();

    _accSub = accelerometerEvents.listen((e) {
      _ax = e.x;
      _ay = e.y;
      _az = e.z;
    });

    _gyroSub = gyroscopeEvents.listen((e) {
      _gx = e.x;
      _gy = e.y;
      _gz = e.z;
    });

    _tick = Timer.periodic(period, (_) {
      _controller.add(
        ImuSample(
          timestamp: DateTime.now(),
          ax: _ax,
          ay: _ay,
          az: _az,
          gx: _gx,
          gy: _gy,
          gz: _gz,
        ),
      );
    });
  }

  Future<void> stop() async {
    _tick?.cancel();
    _tick = null;
    await _accSub?.cancel();
    await _gyroSub?.cancel();
    _accSub = null;
    _gyroSub = null;
  }
}
