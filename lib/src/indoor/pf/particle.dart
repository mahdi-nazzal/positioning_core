class Particle {
  double x;
  double y;
  double headingRad;
  double w;
  String? edgeId;

  Particle({
    required this.x,
    required this.y,
    required this.headingRad,
    required this.w,
    required this.edgeId,
  });

  Particle copy() => Particle(
        x: x,
        y: y,
        headingRad: headingRad,
        w: w,
        edgeId: edgeId,
      );
}
