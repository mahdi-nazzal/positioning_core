//packages/positioning_core/example/lib/features/trace_tools/trace_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'trace_controller.dart';

class TraceScreen extends StatelessWidget {
  const TraceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<TraceController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Trace Tools')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            title: 'Replay',
            child: Column(
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.replay),
                  label: const Text('Replay last recording'),
                  onPressed: ctrl.replayLastRecording,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Replay sample asset trace'),
                  onPressed: () =>
                      ctrl.replayAssetTrace('assets/traces/sample.jsonl'),
                ),
                const SizedBox(height: 10),
                if (ctrl.lastReplaySummary != null)
                  Text(ctrl.lastReplaySummary!),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            title: 'Export',
            child: Column(
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Export last recording to file'),
                  onPressed: () async {
                    final path = await ctrl.exportLastRecording();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              path == null ? 'No data.' : 'Saved: $path'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _Card(
            title: 'Notes',
            child: Text(
              'Put a JSONL file at assets/traces/sample.jsonl for demo replay.\n'
                  'Recording happens from the Live Session screen.',
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
