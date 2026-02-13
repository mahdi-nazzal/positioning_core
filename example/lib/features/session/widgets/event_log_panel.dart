import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:positioning_core/positioning_core.dart';
import '../../../services/storage/trace_store.dart';

class EventLogPanel extends StatelessWidget {
  const EventLogPanel({super.key, this.maxItems = 25});
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TraceStore>();
    final events = store.events;

    final tail = events.length <= maxItems
        ? events
        : events.sublist(events.length - maxItems);

    return _Card(
      title: 'Event Log (last ${tail.length})',
      child: tail.isEmpty
          ? const Text('No events yet. (Try setting anchor / switching modes / floor sim.)')
          : Column(
        children: [
          for (final e in tail.reversed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                e.timestamp.toIso8601String(),
                style: const TextStyle(fontSize: 12),
              ),
              subtitle: Text(
                '${e.name}  •  ${e.data}',
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
