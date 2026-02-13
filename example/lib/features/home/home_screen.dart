// packages/positioning_core/example/lib/features/home/home_screen.dart
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // SystemNavigator.pop

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<bool> _showExitDialog(BuildContext context) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Material(
              color: cs.surface,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.exit_to_app,
                            color: cs.onErrorContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Exit application?',
                                style: Theme.of(ctx)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'You can open the app again normally.',
                                style: Theme.of(ctx)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(ctx).pop(false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.exit_to_app),
                            label: const Text('Exit'),
                            onPressed: () => Navigator.of(ctx).pop(true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ) ??
        false;

    if (!ok) return false;

    if (Platform.isAndroid) {
      SystemNavigator.pop();
    } else {
      // iOS: do not force-close; just dismiss if possible
      Navigator.of(context).maybePop();
    }

    // We handled it.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () => _showExitDialog(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('positioning_core • Example'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Card(
              title: 'Live Session',
              subtitle:
              'GPS + IMU → PositioningController (outdoor/indoor handoff)',
              icon: Icons.navigation_outlined,
              onTap: () => Navigator.pushNamed(context, '/session'),
            ),
            const SizedBox(height: 12),
            _Card(
              title: 'Trace Tools',
              subtitle: 'Record JSONL + replay (deterministic)',
              icon: Icons.replay_outlined,
              onTap: () => Navigator.pushNamed(context, '/trace'),
            ),
            const SizedBox(height: 20),
            const Text(
              'Test Scenarios',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const _ScenarioHint(
              title: '1) Outdoor only',
              body:
              'Start session → enable GPS → walk outside. Observe environment=outdoor and WGS84 updates.',
            ),
            const _ScenarioHint(
              title: '2) Outdoor → Indoor handoff',
              body:
              'Walk outside with GPS. At entrance: Stop GPS → Set Indoor Anchor → enable IMU → walk indoor.',
            ),
            const _ScenarioHint(
              title: '3) Indoor start',
              body:
              'Open session → Set Indoor Anchor immediately → enable IMU only → walk and watch x/y PDR.',
            ),
            const _ScenarioHint(
              title: '4) Floor transitions',
              body:
              'Use Barometer Simulator buttons to inject pressure deltas. (Later we can wire real barometer plugin.)',
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScenarioHint extends StatelessWidget {
  const _ScenarioHint({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(body),
            ],
          ),
        ),
      ),
    );
  }
}
