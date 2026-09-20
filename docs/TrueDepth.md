# TrueDepth capture

`FaceTracker` owns the single ARKit face-tracking session shared by the preview,
feature stream, and explicit recordings. It requires a front TrueDepth camera,
selects that device's video format, and samples at approximately 30 Hz. The preview
starts/stops the camera with visibility and app lifecycle. No camera images or
depth maps are archived outside an explicit recording.

## App workflow

Calibration records real frames after a three-second countdown for 1.5 seconds.
Choose a phrase, REST (relaxed face), or UNKNOWN (unrelated expressions/phrases).
Choose Training, Validation, or Test. Only successful training takes are added to
the on-device classifier; validation and test takes remain in the archive for
offline evaluation. Counts in the interface refer to training examples.

Recognition records the same modalities with label UNLABELED and split unassigned,
then runs the existing DTW blendshape classifier. RGB, mesh and depth are retained
for future model comparisons; the classifier does not yet consume them.
REST/UNKNOWN samples are archived but are not templates in the existing DTW model;
use negatives to measure false triggers and tune thresholds. Scores are
similarities, not calibrated probabilities.

Tracking loss, interruptions, cancellation, failed encoding/writes, fewer than
15 frames, gaps over 200 ms, and archive backpressure invalidate a take. Missing
depth alone does not invalidate a take or discard RGB/features. Invalid takes
are retained with `valid: false` and reasons, and never train or predict. A crash
may leave a directory without final metadata; treat it as incomplete.

Re-record replaces the last training example only after the new take is saved.
Its older archive remains available for inspection; do not blindly train on all
archives, especially superseded attempts. Old mock calibration samples remain
decodable but are excluded by the app's `captureSource` filter.

## Classifier contract

### Live diagnostics

Both camera previews show cyan face-mesh lines and vertex dots, enabled by
default. The face icon in the preview's upper-right corner toggles the overlay;
VoiceOver names it **Face overlay** and announces its on/off state. The preference
persists across screens and launches. The existing countdown/recording dimming
stays visible, and the toggle remains usable beneath it.

These points visualize ARKit's estimated face geometry, not individual depth
pixels or anatomically labelled landmarks. Geometry follows live face-anchor
updates independently of the diagnostics panel, and does not require a delivered
raw depth map. A depth-only face surface hides far-side points. Tracking loss,
interruption or a stopped session hides the overlay; reacquisition restores it.
The display shares the existing AR session and never changes saved RGB, depth,
features or classifier inputs.

Both Calibration and Recognition show a Live readings panel below the preview,
including eight mouth-movement bars, colour-camera dimensions, delivered frame
rate, camera-to-face distance, and depth availability. Expand **Depth, mesh & head
movement** for depth dimensions, approximate valid-pixel coverage, median scene
depth, the age of the inspected depth sample, distinct depth samples received per
second, RGB exposure, mesh vertex count and relative yaw/pitch/roll.

The panel updates at approximately 5 Hz without recording. Depth statistics use
a grid of at most 64 × 48 pixels across the entire depth image, including the
background; they are not mouth-only measurements or confidence scores. A sample
older than 500 ms is marked stale and its coverage/distance values are hidden.
Head angles use the first tracked pose as a reference. Tracking loss, stop or
interruption clears the diagnostics and resets that reference. The feature and
archive streams keep their existing sampling behavior.

### Feature schema

The 24-value feature schema remains version 1 to preserve compatibility. Ordered
names are in `sample-data/feature_schema.json` and `MouthFeatureSchema.names`.
Each `MouthFrame` has a monotonic ARKit timestamp and raw coefficients. Smoothing,
baseline subtraction and resampling remain in the classifier. The archive also
preserves **all** available ARKit blendshapes by name, including coefficients
outside this 24-value classifier vector.

`tracker.frames` emits real sampled frames even when the mouth is still. No
synthetic zeros or repeated frames are emitted on tracking loss. Existing
feature-only subscribers need no changes. `beginRecording(label:datasetSplit:)`
and `finishRecording(cancelled:)` control multimodal recording on the main actor.

## Files

Download the app container using Xcode's Devices and Simulators window. Under
`Documents/captures/`, each UUID identifies one attempt and matches `sample.id`:

```text
<sample UUID>/
  metadata.json       # schema, label, speaker/session IDs, timing, split, validity
  sample.json         # classifier MouthSample with captureSource=TrueDepth
  000000/
    frame.json       # RGB/depth timestamps, mesh, blendshapes, transforms, calibration
    rgb.png          # 192 x 192 mouth-region image, lossless RGBA8
    depth.f32        # optional native-sized Float32 little-endian metres
    depth-mask.u8    # optional native-sized UInt8 validity mask
  000001/
    ...
```

Timestamped PNG sequences preserve video frames without lossy compression or
invented constant-rate timing. File indices pair each image with `frame.json`;
use actual timestamps when resampling. Archives are local and are not uploaded.
Full native depth can make captures large; monitor device storage and copy/delete
research archives through Xcode as needed. Never commit participant recordings.

Sample metadata includes hardware model, iOS version, creation date, measured
frame rate, frame/depth counts, feature order, coordinate conventions and validity.
The pseudonymous speaker ID persists for this app installation; it assumes one
speaker per installation. Session IDs change whenever the AR session starts.
They identify capture runs, not automatically independent experimental sessions.

## Geometry, crops and depth

- Matrices are flattened **column-major**. Face vertices use face-local metres;
  face and camera transforms map into AR world space.
- The initial mouth-region selection is conservative: first-frame vertices with
  `abs(x) < 0.055` and `-0.080 < y < -0.005` metres. Their indices remain fixed
  throughout the take. This includes the lower central face, not an anatomically
  verified list of lip vertices. All mesh vertices are saved for later refinement.
- Project these vertices into native RGB coordinates, add 25% padding per side,
  and resize to 192 x 192. `rgbCrop` stores x/y/width/height in original pixels,
  top-left origin. Images are native orientation and unmirrored, independent of
  the preview; device orientation is recorded separately.
- Inspect crops on a physical device before collecting a large dataset. Mesh
  estimates, pose and lens distortion can affect alignment. A crop outside the
  camera image invalidates the take rather than silently clipping it.
- Depth stays at original dimensions, **not cropped/resized or rectified**, to
  preserve geometry until calibrated RGB/depth alignment is verified. Never use
  RGB crop pixel coordinates directly on the depth map.
- `depthTimestamp` comes from `capturedDepthDataTimestamp`, separate from RGB time.
  Missing/zero depth timestamps result in no depth files for that frame. Repeated
  depth timestamps must not be counted as independent measurements.
- `depth.f32` is tightly packed row-major data without pixel-buffer row padding.
  Nonfinite/nonpositive depths become zero placeholders with mask 0; valid positive
  depths have mask 1. **Always apply the mask**; placeholders are not measurements.
- Calibration includes intrinsics, reference dimensions, extrinsics, pixel size,
  distortion center, and optional forward/inverse lens distortion lookup tables
  (base64 Float32 data). Filtering, accuracy and quality flags are retained.
  Calibration can be absent; do not claim metric reconstruction from uncalibrated
  data. Apple depth maps can retain lens distortion.

ARFrames and pixel buffers are consumed during the delegate callback, never held
across callbacks. Encoding/copying currently happens on the main actor; disk writes
run off the main actor, with at most four outstanding frame writes and a 300-frame
cap. Throughput needs device measurement; a slower device may require moving
encoding onto a bounded worker with copied image buffers.

## Verification

```sh
bash Scripts/run-capture-smoke.sh
bash Scripts/run-classifier-smoke.sh
xcodebuild -project SilentVoice.xcodeproj -scheme SilentVoice \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/SilentVoice-build \
  CODE_SIGNING_ALLOWED=NO build
```

Capture checks cover exact depth bytes/masks, legacy/new sample decoding,
missing-depth metadata, file round trips, sampling and schema order. Classifier
checks cover synthetic behavior, not real-world accuracy.

Physical-device acceptance:

1. Record both phrases, REST and UNKNOWN. Confirm real movement in saved features
   and RGB crops that include lips, teeth and visible tongue.
2. Inspect all orientations and modest pose/distance changes. Verify crop bounds
   and lower-face vertex selection.
3. Check increasing RGB timestamps and independent depth timestamps. Confirm depth
   byte count is width * height * 4 and mask count is width * height.
4. Confirm missing-depth frames still have RGB, mesh and features. A take with zero
   depth frames must remain usable for the blendshape baseline.
5. Turn away, background the app or cancel mid-take. Confirm invalid takes are
   excluded, errors are shown and subsequent recording recovers.
6. Check delivered frame rate, responsiveness, archive sizes and memory use.
7. Record validation/test data in later sessions; training counts must not change.
   Measure per-phrase accuracy and false triggers. Keep final test sessions
   untouched while tuning thresholds.
8. Check mesh/dot alignment in both previews and supported orientations while
   smiling, blinking, opening/puckering the mouth, moving nearer/farther and
   turning/tilting the head. Check far-side occlusion and absence of flicker.
   Toggle before and during capture, navigate between screens and relaunch to
   verify the preference. Lose/reacquire the face and interrupt/background the
   app to check for frozen or duplicate meshes. Compare delivered frame rate and
   responsiveness with the overlay on/off, especially while saving captures.

No measured recognition accuracy or depth benefit is established by this change.
Compare a blendshape baseline against RGB/mesh/depth variants on the same held-out
sessions before expanding the vocabulary.

Apple references: [depth timestamps](https://developer.apple.com/documentation/arkit/arframe/captureddepthdatatimestamp),
[captured depth](https://developer.apple.com/documentation/arkit/arframe/captureddepthdata),
[depth calibration](https://developer.apple.com/documentation/avfoundation/avdepthdata).
