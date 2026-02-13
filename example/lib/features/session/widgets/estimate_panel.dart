import 'package:flutter/material.dart';
import 'package:positioning_core/positioning_core.dart';

class EstimatePanel extends StatelessWidget {
  const EstimatePanel({super.key, required this.last});
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
          Text(
            'lat/lon: ${last!.latitude?.toStringAsFixed(6)} , ${last!.longitude?.toStringAsFixed(6)}',
          ),
          Text(
            'x/y: ${last!.x?.toStringAsFixed(2)} , ${last!.y?.toStringAsFixed(2)}',
          ),
          Text('level: ${last!.buildingId ?? '-'} / ${last!.levelId ?? '-'}'),
          Text('heading: ${last!.headingDeg?.toStringAsFixed(1)}°'),
          Text('speed: ${last!.speedMps?.toStringAsFixed(2)} m/s'),
          Text('acc: ${last!.accuracyMeters?.toStringAsFixed(2)} m'),
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
