# TrueDepth module (Person 1)

`FaceTracker` owns one ARKit session. The existing `FaceCameraView()` uses
`AppViewModel.tracker`; `FaceCameraView(tracker: tracker)` also works when explicitly
passing a tracker. Only mount one preview per tracker at a time. The preview starts
tracking while visible and active, and stops it when hidden or inactive. Headless
consumers must call `start()` / `stop()` and manage app lifecycle themselves.

The existing `FaceTracking` methods/properties remain intact. The protocol is
explicitly main-actor isolated to match the tracker and SwiftUI callers.

## Classifier contract

- `FaceTracker.featureSchemaVersion` is **1**.
- Each emitted `MouthFrame` has 24 raw `Float` coefficients in `[0, 1]`.
- `FaceTracker.featureNames` is the authoritative ordered schema.
- Baseline subtraction, smoothing, and sequence resampling belong to Person 2.
- Timestamps are ARKit monotonic uptime seconds, not dates. Person 4 can subtract
  the first frame timestamp if sample-relative time is desired.
- Features are empty when no tracked face exists. No synthetic zero frames or
  repeated last-known frames are emitted during face loss, interruption, or stop.
- Native 30 Hz capture is preferred; faster input is sampled at approximately
  30 Hz. Actual throughput depends on the device. `framesPerSecond` measures
  delivered frames over roughly one-second windows and resets on face loss.
- Missing coefficients default to zero. Nonfinite values reject the frame;
  out-of-range finite values are clamped.

Exact feature order:

```text
 0 jawOpen             1 jawForward          2 jawLeft
 3 jawRight            4 mouthClose          5 mouthFunnel
 6 mouthPucker         7 mouthLeft           8 mouthRight
 9 mouthSmileLeft     10 mouthSmileRight    11 mouthFrownLeft
12 mouthFrownRight    13 mouthDimpleLeft    14 mouthDimpleRight
15 mouthStretchLeft  16 mouthStretchRight  17 mouthRollLower
18 mouthRollUpper    19 mouthShrugLower    20 mouthShrugUpper
21 mouthPressLeft    22 mouthPressRight    23 cheekPuff
```

Left/right are ARKit's anatomical labels, unaffected by the mirrored preview.
Agree with Person 2 before changing this schema or collecting calibration data.
The current shared `MouthSample` does not store a schema version; Person 4 should
version stored datasets before mixing samples from different schemas.

## Recording integration (Person 4)

Subscribe once to `tracker.frames`, retaining the Combine cancellable:

```swift
tracker.frames.sink { frame in
    // On the main actor. Append only while your recording state is active.
    recordingFrames.append(frame)
}.store(in: &cancellables)
```

Use the event stream to record: it emits even when values are unchanged. Do not
poll `currentFeatures` on a timer or deduplicate equal vectors. Observe
`isFaceDetected` / `status` to cancel or flag a recording that loses tracking.
`latestFrame` is for diagnostics, not a replay buffer. This module does not retain
recordings, camera images, or depth maps.

`status` covers stopped, requesting permission, unsupported hardware, denied
permission, looking for a face, tracking, interruption, and errors. After an error,
`start()` retries; the preview offers a retry button. Returning from Settings
rechecks camera permission on scene activation.

## Physical-device acceptance check

1. Person 4 selects signing in Xcode and runs `SilentVoice` on a TrueDepth iPhone.
2. Open Recognition and allow camera access. Confirm a live preview and “Face detected”.
3. Open/close your mouth: the Jaw value should change. After a second, confirm
   roughly 30 fps; inspect `currentFeatures.count == 24` in the debugger.
4. Mouth two phrases and inspect `tracker.frames`: timestamps must increase,
   coefficients must vary, and the vector order/length must stay fixed.
5. Turn away or cover the camera: face detection becomes false, features clear,
   and the frame stream stops. Return and confirm tracking recovers.
6. Leave Recognition, background the app, and return. Confirm the camera stops
   and restarts. Lock/unlock or interrupt the camera and check recovery.
7. Deny camera permission, then grant it in Settings and return. Confirm the
   explanatory message and recovery. A simulator should show unsupported hardware.

Device testing is required to establish accuracy, delivered frame rate, and camera
lifecycle behavior. Simulator builds and synthetic tests cannot establish these.
Person 4 owns signing/project settings and the test target; source folders are
already synchronized by the Xcode project. `MouthFeaturePipelineTests.swift` uses
Swift Testing and can be added alongside the existing shared-contract tests.

Apple references: [face tracking configuration](https://developer.apple.com/documentation/arkit/arfacetrackingconfiguration)
and [face anchors / blend shapes](https://developer.apple.com/documentation/arkit/arfaceanchor).
ARKit support alone can include devices without TrueDepth, so the tracker also
requires a front TrueDepth camera and selects its video format.
