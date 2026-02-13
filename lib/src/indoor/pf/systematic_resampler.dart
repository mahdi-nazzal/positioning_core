import 'dart:math' as math;

import 'particle.dart';

List<Particle> systematicResample(List<Particle> particles, math.Random rng) {
  final n = particles.length;
  if (n == 0) return particles;

  // Ensure normalized weights (defensive; avoids weirdness).
  double sumW = 0.0;
  for (final p in particles) {
    sumW += p.w;
  }
  if (sumW <= 1e-15) {
    final u = 1.0 / n;
    for (final p in particles) {
      p.w = u;
    }
  } else {
    for (final p in particles) {
      p.w = p.w / sumW;
    }
  }

  final step = 1.0 / n;
  final start = rng.nextDouble() * step;

  final out = List<Particle>.filled(n, particles.first.copy(), growable: false);

  double cdf = particles[0].w;
  int i = 0;

  for (int m = 0; m < n; m++) {
    final u = start + m * step;
    while (u > cdf && i < n - 1) {
      i++;
      cdf += particles[i].w;
    }
    // CRITICAL: deep copy to avoid aliasing the same object.
    out[m] = particles[i].copy();
  }

  // Reset weights after resampling.
  final w = 1.0 / n;
  for (final p in out) {
    p.w = w;
  }

  return out;
}
