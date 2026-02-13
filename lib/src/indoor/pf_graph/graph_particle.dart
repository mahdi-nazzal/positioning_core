class GraphParticle {
  String edgeId;
  double t; // [0..1]
  int dir; // +1 or -1
  double w;

  GraphParticle({
    required this.edgeId,
    required this.t,
    required this.dir,
    required this.w,
  });

  GraphParticle copy() => GraphParticle(
        edgeId: edgeId,
        t: t,
        dir: dir,
        w: w,
      );
}
