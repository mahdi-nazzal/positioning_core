import 'dart:math' as math;

import 'graph_particle.dart';

List<GraphParticle> systematicResample(
    List<GraphParticle> particles, math.Random rng) {
  final n = particles.length;
  if (n == 0) return particles;

  final step = 1.0 / n;
  final start = rng.nextDouble() * step;

  final out =
      List<GraphParticle>.filled(n, particles.first.copy(), growable: false);

  double cdf = particles[0].w;
  int i = 0;

  for (int m = 0; m < n; m++) {
    final u = start + m * step;
    while (u > cdf && i < n - 1) {
      i++;
      cdf += particles[i].w;
    }
    out[m] = particles[i].copy()..w = step;
  }

  return out;
}
