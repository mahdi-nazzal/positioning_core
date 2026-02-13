import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:positioning_core/positioning_core.dart';
import 'widgets/diagnostics_panel.dart';
import 'widgets/estimate_panel.dart';
import 'widgets/event_log_panel.dart';
import 'widgets/live_map_stub.dart';

import 'session_controller.dart';
import 'dart:io' show Platform;
//import 'package:flutter/services.dart'; // SystemNavigator.pop

class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SessionController>();
    final last = ctrl.lastEstimate;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Session'),
        actions: [
          IconButton(
            tooltip: 'Export / Share Trace',
            icon: const Icon(Icons.save_alt),
            onPressed: () async {
              final ctrl = context.read<SessionController>();

              await showModalBottomSheet(
                context: context,
                showDragHandle: true,
                builder: (_) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.folder_open),
                        title: const Text('Save to device (choose location)'),
                        onTap: () async {
                          Navigator.pop(context);
                          final p = await ctrl.saveTraceAs();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(p == null ? 'No trace yet.' : 'Saved: $p')),
                            );
                          }
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.share),
                        title: const Text('Share trace'),
                        onTap: () async {
                          Navigator.pop(context);
                          await ctrl.shareTrace();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: const Text('Save to app storage (sandbox)'),
                        subtitle: const Text('Good for debugging; may be hidden from file managers'),
                        onTap: () async {
                          Navigator.pop(context);
                          final p = await ctrl.saveTraceToAppStorage();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(p == null ? 'No trace yet.' : 'Saved: $p')),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'New Recording (rebuild)',
            icon: const Icon(Icons.fiber_new),
            onPressed: () async {
              await ctrl.rebuildForNewRecording();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('New recording session ready.')),
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LiveMapStub(points: ctrl.recent),
          const SizedBox(height: 12),
          DiagnosticsPanel(ctrl: ctrl),
          const SizedBox(height: 12),
          EstimatePanel(last: last),
          const SizedBox(height: 12),
          const EventLogPanel(),

          _TopStatus(ctrl: ctrl),
          const SizedBox(height: 12),
          _Toggles(ctrl: ctrl),
          const SizedBox(height: 12),
          _AnchorPanel(ctrl: ctrl),
          const SizedBox(height: 12),
          _PdrPanel(ctrl: ctrl),
          const SizedBox(height: 12),
          _BarometerSim(ctrl: ctrl),
          const SizedBox(height: 12),
          _FloorSimPanel(ctrl: ctrl),
          const SizedBox(height: 12),
          _LastEstimate(last: last),
          const SizedBox(height: 12),
          _RecentList(ctrl: ctrl),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          icon: Icon(ctrl.sessionRunning ? Icons.stop : Icons.play_arrow),
          label: Text(ctrl.sessionRunning ? 'Stop Session' : 'Start Session'),
          onPressed: () async {
            if (ctrl.sessionRunning) {
              await ctrl.stopSession();
            } else {
              await ctrl.startSession();
            }
          },
        ),
      ),
    );
  }
}

class _TopStatus extends StatelessWidget {
  const _TopStatus({required this.ctrl});
  final SessionController ctrl;

  @override
  Widget build(BuildContext context) {
    final mode = ctrl.engine.environmentMode.name;
    return _Card(
      title: 'Engine Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('traceEvents: ${ctrl.traceEventCount}'),

          Text('running: ${ctrl.sessionRunning}'),
          Text('environmentMode: $mode'),
          Text('gpsEnabled: ${ctrl.gpsEnabled} • imuEnabled: ${ctrl.imuEnabled}'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<EnvironmentMode?>(
                  segments: const [
                    ButtonSegment(value: null, label: Text('Auto')),
                    ButtonSegment(
                        value: EnvironmentMode.outdoor, label: Text('Outdoor')),
                    ButtonSegment(
                        value: EnvironmentMode.indoor, label: Text('Indoor')),
                  ],
                  selected: {ctrl.overrideMode},
                  onSelectionChanged: (s) => ctrl.setOverride(s.first),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Toggles extends StatelessWidget {
  const _Toggles({required this.ctrl});
  final SessionController ctrl;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Inputs + Recording',
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('GPS (Geolocator)'),
            value: ctrl.gpsEnabled,
            onChanged: (v) => ctrl.setGpsEnabled(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('IMU (sensors_plus)'),
            value: ctrl.imuEnabled,
            onChanged: (v) => ctrl.setImuEnabled(v),
          ),

          // ✅ ADD THIS
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Barometer (device sensor)'),
            subtitle: Text(
              ctrl.barometerEnabled
                  ? 'Using real device barometer'
                  : 'OFF (simulator below is active)',
            ),
            value: ctrl.barometerEnabled,
            onChanged: (v) => ctrl.setBarometerEnabled(v),
          ),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Record trace (JSONL)'),
            subtitle: const Text('Uses TraceRecordingLogger'),
            value: ctrl.recordingEnabled,
            onChanged: ctrl.setRecordingEnabled,
          ),
        ],
      ),
    );
  }
}

class _AnchorPanel extends StatelessWidget {
  const _AnchorPanel({required this.ctrl});
  final SessionController ctrl;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Indoor Anchor',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Use this for Indoor Start or Outdoor→Indoor handoff at entrance.',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in ctrl.presets)
                OutlinedButton(
                  onPressed: () => ctrl.setIndoorAnchorPreset(p),

                  child: Text(p.label),
                ),
            ],
          ),

          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: ctrl.clearIndoorAnchor,
            icon: const Icon(Icons.clear),
            label: const Text('Clear anchor'),
          ),
        ],
      ),
    );
  }
}

class _PdrPanel extends StatelessWidget {
  const _PdrPanel({required this.ctrl});
  final SessionController ctrl;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'PDR Tuning',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Manual step length: ${ctrl.manualStepLength.toStringAsFixed(2)} m'),
          Slider(
            value: ctrl.manualStepLength.clamp(0.35, 1.4),
            min: 0.35,
            max: 1.40,
            divisions: 105,
            onChanged: ctrl.setManualStepLength,
          ),
          const SizedBox(height: 6),
          Text('debug steps: ${ctrl.engine.debugPdrStepCountTotal}'),
        ],
      ),
    );
  }
}
class _FloorSimPanel extends StatelessWidget {
  const _FloorSimPanel({required this.ctrl});
  final SessionController ctrl;

  @override
  Widget build(BuildContext context) {
    final last = ctrl.lastEstimate;

    return _Card(
      title: 'Floor Test أدوات',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('current: ${last?.buildingId ?? '-'} / ${last?.levelId ?? '-'}'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_upward),
                  label: const Text('Sim +1 floor'),
                  onPressed: () => ctrl.simulateFloorChange(deltaFloors: 1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_downward),
                  label: const Text('Sim -1 floor'),
                  onPressed: () => ctrl.simulateFloorChange(deltaFloors: -1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BarometerSim extends StatelessWidget {
  const _BarometerSim({required this.ctrl});
  final SessionController ctrl;

  @override
  Widget build(BuildContext context) {
    final simEnabled = !ctrl.barometerEnabled;

    return _Card(
      title: 'Barometer Simulator',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            simEnabled
                ? 'pressure: ${ctrl.simulatedPressureHpa.toStringAsFixed(2)} hPa'
                : 'Simulator disabled (real barometer is ON)',
          ),
          Slider(
            value: ctrl.simulatedPressureHpa.clamp(980, 1040),
            min: 980,
            max: 1040,
            divisions: 600,
            onChanged: simEnabled ? (v) => ctrl.injectBarometer(v) : null,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_upward),
                  label: const Text('Up (1 floor)'),
                  onPressed: simEnabled
                      ? () => ctrl.simulateFloorChange(deltaFloors: 1)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_downward),
                  label: const Text('Down (1 floor)'),
                  onPressed: simEnabled
                      ? () => ctrl.simulateFloorChange(deltaFloors: -1)
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LastEstimate extends StatelessWidget {
  const _LastEstimate({required this.last});
  final PositionEstimate? last;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Last Estimate',
      child: last == null
          ? const Text('No estimate yet.')
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('isIndoor: ${last!.isIndoor} • source: ${last!.source.name}'),
          const SizedBox(height: 6),
          Text('lat/lon: ${last!.latitude?.toStringAsFixed(6)} , ${last!.longitude?.toStringAsFixed(6)}'),
          Text('x/y: ${last!.x?.toStringAsFixed(2)} , ${last!.y?.toStringAsFixed(2)}'),
          Text('level: ${last!.buildingId ?? '-'} / ${last!.levelId ?? '-'}'),
          Text('heading: ${last!.headingDeg?.toStringAsFixed(1)}°'),
          Text('speed: ${last!.speedMps?.toStringAsFixed(2)} m/s'),
          Text('acc: ${last!.accuracyMeters?.toStringAsFixed(2)} m'),
        ],
      ),
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.ctrl});
  final SessionController ctrl;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Recent Estimates (last 20)',
      child: Column(
        children: [
          for (final e in ctrl.recent.reversed.take(20))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${e.timestamp.toIso8601String()}  •  ${e.source.name}  •  indoor=${e.isIndoor}',
                style: const TextStyle(fontSize: 12),
              ),
              subtitle: Text(
                'lat=${e.latitude?.toStringAsFixed(6)} lon=${e.longitude?.toStringAsFixed(6)} | x=${e.x?.toStringAsFixed(2)} y=${e.y?.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
