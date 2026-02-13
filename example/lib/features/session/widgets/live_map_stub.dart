// packages/positioning_core/example/lib/features/session/widgets/live_map_stub.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:positioning_core/positioning_core.dart';

class LiveMapStub extends StatelessWidget {
  const LiveMapStub({super.key, required this.points});
  final List<PositionEstimate> points;

  @override
  Widget build(BuildContext context) {
    final indoor = points.where((e) => e.x != null && e.y != null).toList();

    final last = indoor.isEmpty ? null : indoor.last;
    final label = (last == null)
        ? '-'
        : '${last.buildingId ?? '-'} / ${last.levelId ?? '-'}';

    return _Card(
      title: 'Live Map (levels + transitions)',
      child: SizedBox(
        height: 220,
        child: indoor.length < 2
            ? const Center(
          child: Text('Walk with IMU + anchor to see x/y trail.'),
        )
            : Stack(
          children: [
            CustomPaint(
              painter: _TrailPainter(indoor),
              child: const SizedBox.expand(),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: _LegendChip(text: label),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withOpacity(0.88),
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _TrailPainter extends CustomPainter {
  _TrailPainter(this.points);
  final List<PositionEstimate> points;

  @override
  void paint(Canvas canvas, Size size) {
    // --- map to view ---
    final xs = points.map((e) => e.x!).toList();
    final ys = points.map((e) => e.y!).toList();

    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);

    final dx = (maxX - minX).abs();
    final dy = (maxY - minY).abs();
    final span = math.max(dx, dy).clamp(1.0, 300.0);

    const pad = 16.0;
    final scale = (math.min(size.width, size.height) - pad * 2) / span;

    Offset map(double x, double y) {
      final cx = (minX + maxX) / 2.0;
      final cy = (minY + maxY) / 2.0;
      final px = (x - cx) * scale + size.width / 2.0;
      final py = (y - cy) * scale + size.height / 2.0;
      return Offset(px, py);
    }

    // --- background ---
    final bg = Paint()
      ..color = const Color(0x22000000)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(14),
      ),
      bg,
    );

    // --- helper: level key ---
    String keyOf(PositionEstimate e) => '${e.buildingId ?? '-'}|${e.levelId ?? '-'}';

    // --- draw colored segments + collect transitions ---
    const strokeWidth = 2.6;
    final transitionPoints = <_TransitionMarker>[];

    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];

      final aKey = keyOf(a);
      final bKey = keyOf(b);

      final aColor = _colorForKey(aKey);
      final bColor = _colorForKey(bKey);

      final p1 = map(a.x!, a.y!);
      final p2 = map(b.x!, b.y!);

      // Segment is colored by "to" level (b)
      final seg = Paint()
        ..color = bColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(p1, p2, seg);

      // Transition marker when level changes
      if (aKey != bKey) {
        transitionPoints.add(
          _TransitionMarker(
            at: p2, // mark at the first point of the new level
            fromColor: aColor,
            toColor: bColor,
          ),
        );
      }
    }

    // --- draw transition markers (split half/half) ---
    for (final m in transitionPoints) {
      _drawSplitMarker(canvas, m.at, m.fromColor, m.toColor);
    }

    // --- draw last dot in last level color ---
    final last = points.last;
    final lastColor = _colorForKey(keyOf(last));
    final lp = map(last.x!, last.y!);

    final dotFill = Paint()..color = lastColor;
    canvas.drawCircle(lp, 6.5, dotFill);

    final outline = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(lp, 6.5, outline);
  }

  void _drawSplitMarker(Canvas canvas, Offset c, Color from, Color to) {
    const r = 6.5;
    final rect = Rect.fromCircle(center: c, radius: r);

    // subtle base fill (keeps marker readable on bright lines)
    canvas.drawCircle(
      c,
      r,
      Paint()..color = const Color(0xCC111111),
    );

    // left half = from
    final pFrom = Paint()
      ..color = from
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // right half = to
    final pTo = Paint()
      ..color = to
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // draw two semi-circles
    canvas.drawArc(rect, math.pi / 2, math.pi, false, pFrom);     // left
    canvas.drawArc(rect, -math.pi / 2, math.pi, false, pTo);      // right

    // thin white ring to pop
    final ring = Paint()
      ..color = const Color(0xE6FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    canvas.drawCircle(c, r + 0.8, ring);
  }

  @override
  bool shouldRepaint(covariant _TrailPainter oldDelegate) => true;

  // Deterministic color from key (stable across rebuilds).
  Color _colorForKey(String key) {
    final h = _fnv1a32(key);
    final hue = (h % 360).toDouble();
    return HSVColor.fromAHSV(1.0, hue, 0.85, 0.95).toColor();
  }

  int _fnv1a32(String s) {
    const int fnvOffset = 0x811c9dc5;
    const int fnvPrime = 0x01000193;
    var hash = fnvOffset;
    for (final codeUnit in s.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash;
  }
}

class _TransitionMarker {
  final Offset at;
  final Color fromColor;
  final Color toColor;

  const _TransitionMarker({
    required this.at,
    required this.fromColor,
    required this.toColor,
  });
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
