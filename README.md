# positioning_core

Pure Dart, offline-first positioning engine for hybrid indoor/outdoor pedestrian navigation.

- **Indoor**: baseline Pedestrian Dead Reckoning (PDR) from IMU samples (step detection + heading integration).
- **Outdoor**: GPS passthrough (map matcher is currently a stub).
- **Hybrid**: a `PositioningController` that emits a unified `Stream<PositionEstimate>`.

> This package is the **core algorithm layer**. It does not read device sensors by itself.
> Your app (or an adapter package) must collect GPS/IMU/barometer samples and feed them in.

## Install (monorepo / local)

```yaml
dependencies:
  positioning_core:
    path: ../positioning_core


## Metrics (offline evaluation)

You can evaluate algorithm changes deterministically using traces + metrics:

- Record a JSONL trace with `TraceRecordingLogger`
- Replay it with `PositioningReplayer`
- Compute RMSE using `outdoorRmseVsGroundTruth` or `indoorRmse2dVsGroundTruth`
