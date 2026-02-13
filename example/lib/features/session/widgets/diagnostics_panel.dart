import 'package:flutter/material.dart';
import 'package:positioning_core/positioning_core.dart';
import '../../session/session_controller.dart';

class DiagnosticsPanel extends StatelessWidget {
  const DiagnosticsPanel({super.key, required this.ctrl});
  final SessionController ctrl;

  @override
  Widget build(BuildContext context) {
    final mode = ctrl.engine.environmentMode.name;

    return _Card(
      title: 'Engine Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('running: ${ctrl.sessionRunning}'),
          Text('environmentMode: $mode'),
          Text('gpsEnabled: ${ctrl.gpsEnabled} • imuEnabled: ${ctrl.imuEnabled}'),
          const SizedBox(height: 8),
          SegmentedButton(
            segments: const [
              ButtonSegment(value: null, label: Text('Auto')),
              ButtonSegment(value: EnvironmentMode.outdoor, label: Text('Outdoor')),
              ButtonSegment(value: EnvironmentMode.indoor, label: Text('Indoor')),
            ],

            selected: {ctrl.overrideMode},
            onSelectionChanged: (s) => ctrl.setOverride(s.first),
          ),
          const SizedBox(height: 8),
          Text('debug steps: ${ctrl.engine.debugPdrStepCountTotal}'),
          Text('step length: ${ctrl.manualStepLength.toStringAsFixed(2)} m'),
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
