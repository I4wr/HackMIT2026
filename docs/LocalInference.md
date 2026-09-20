# Local sentence transcription

SilentVoice can send a short silent sentence from a TrueDepth iPhone to a nearby
Mac running the full Auto-AVSR visual speech decoder. It returns editable English
text. Tap **Speak** to read the edited text aloud. **Commands** remains the existing
offline five-word DTW mode and still uses its own calibration samples.

This is an experimental pretrained lip-reading demo. Models trained on audible
speech do not establish accuracy on silently mouthed sentences. No microphone is
used. Calibration trains only the command classifier; it does not train this model.

## Running the app

1. Start the local model in Terminal:

    cd /Users/brianhuang/repos4/hackmitproject
    SILENTVOICE_DEVICE=cpu bash Scripts/run-local-inference.sh

    CPU mode avoids the GPU fallback issue recorded for this setup. Leave this terminal running.

2. Check readiness in another terminal:

    curl http://localhost:8000/health

    Wait until it returns "ready": true.

3. Run the iPhone app:
    - Open SilentVoice.xcodeproj in Xcode.
    - Connect and trust your TrueDepth-capable iPhone.
    - Select your team under Signing & Capabilities.
    - Select your iPhone as the run destination and press ⌘R.

    The simulator cannot capture TrueDepth face tracking.

4. Connect the app to the model:
    - Connect your Mac and iPhone to the same Wi-Fi.
    - Open Start silent speech → Sentences → Mac connection.
    - Hostname: Brians-MacBook-Air.local
    - Port: 8000
    - Tap Test Connection and allow Local Network access.

Then tap Record sentence, mouth your sentence, tap Stop recording, review the transcript, and tap Speak.

## Mac setup

Use an Apple Silicon Mac with macOS 14 or later, Python 3.12, and roughly 5 GB free disk space. The locked
environment is for macOS arm64. Run these commands from the app repository:

```bash
python3.12 -m venv training/.venv
training/.venv/bin/python -m pip install -r training/requirements-macos-arm64.lock
training/.venv/bin/python -m pip install --no-deps -e training

git clone https://github.com/mpc001/auto_avsr.git ../auto_avsr
git -C ../auto_avsr checkout 182b62837773ab01052d4ac21ef1d2203ea7d267

curl -fL 'https://drive.usercontent.google.com/download?id=1r1kx7l9sWnDOCnaFHIGvOtzuhFyFA88_&export=download&confirm=t' \
  -o ../vsr_trlrs2lrs3vox2avsp_base.pth
md5 ../vsr_trlrs2lrs3vox2avsp_base.pth
```

The expected checkpoint MD5 is `49f770f2c0d8b8d769347ee47ed1648f` (download integrity,
not authentication). This is the download linked by the upstream
[model zoo](https://github.com/mpc001/auto_avsr#model-zoo). The older Imperial-hosted
model and demo-video URLs in the original guide currently return 404.

```bash
bash Scripts/run-local-inference.sh
```

The server loads and warms the model before accepting connections. It uses one
worker on port 8000. Set `SILENTVOICE_DEVICE=cpu` to force CPU; `auto` prefers MPS
and falls back to CPU if warm-up or decoding encounters an unsupported operation.
Per-operation MPS fallback is enabled before importing PyTorch, since the pinned
release lacks a native Metal implementation of the frontend's 3D max pooling.
`SILENTVOICE_AUTO_AVSR` and `SILENTVOICE_CHECKPOINT` override the sibling paths.
Keep the Mac awake during the demo. Stop the server with Ctrl-C.

## Connect the phone

1. Find the Mac's local hostname in System Settings → General → Sharing, or run
   `scutil --get LocalHostName` and append `.local`.
2. Put the Mac and iPhone on the same trusted Wi-Fi with client-to-client traffic
   allowed. This setup does not automatically route HTTP over an Xcode USB cable.
3. In SilentVoice, open **Start silent speech → Sentences → Mac connection**.
   Enter the hostname and port 8000, then tap **Test Connection**. Allow Local
   Network access when prompted; allow the Mac server through its firewall.
4. Tap **Record sentence**, wait for the countdown, mouth a sentence, and tap
   **Stop recording**. Recording automatically stops at ten seconds.
5. Review/correct the result and tap **Speak**. A failed request offers Retry and
   **Use offline Commands**. Switching modes does not classify the sentence as a
   command; record a new command take.

Only `.local` hostnames and `localhost` are accepted, matching the app's local ATS
exception. `localhost` is for simulator testing. Denied local-network permission
can be changed in iPhone Settings → Privacy & Security → Local Network. Test
Connection times out after three seconds; transcription after 60 seconds.

The server uses local HTTP, without authentication or encryption; use it only on
a trusted demo network. It receives face PNGs and timing metadata, never native
depth or mesh files, and deletes temporary uploads after processing. Existing
phone archives remain in the app container. No transcript or image is uploaded to
a cloud service or saved by the HTTP server. The app retains the raw result
separately from the editable transcript for the current session.

## Capture and preprocessing

New recordings use archive schema v2. Each frame still contains the original
mouth RGB, blendshapes, mesh, and optional native depth. It additionally contains
`face.png` when a padded full-face crop is available. Face crops are square,
256×256, upright, and unmirrored; `frame.json` records native-pixel `faceCrop`,
`faceWidth`, `faceHeight`, and the EXIF `faceOrientation` already applied to PNG.
The manifest includes `faceFrameCount` and `faceFormat`. Sentence takes require
all face crops. Commands can still succeed if these optional crops fail.

Schema-v1 archives retain their command-classifier compatibility but cannot be
used for sentence inference. Re-record them. Archives with `valid: false` or no
final manifest are not usable. Missing depth is acceptable.

The server uses timestamps to choose frames on a 25 Hz timeline. Upstream
MediaPipe keypoints and the model's reference face produce aligned 96×96 mouth
patches; upstream test transforms center-crop to 88×88, convert to grayscale, and
normalize with mean 0.421 and standard deviation 0.165. Mostly missing landmarks
produce an alignment error. Inference uses the full frozen encoder and text
decoder, with upstream beam-search defaults; decoder scores are not displayed as
confidence percentages.

## Inspect a recording and evaluate accuracy

Download the app container through Xcode → Devices and Simulators → Installed
Apps → Download Container. Captures are under `AppData/Documents/captures`.

```bash
training/.venv/bin/silentvoice-local \
  --auto-avsr ../auto_avsr --checkpoint ../vsr_trlrs2lrs3vox2avsp_base.pth \
  transcribe /path/to/captures/SAMPLE-UUID --preview training/artifacts/aligned
```

Inspect the exported 88×88 patches for upright, centered, stable mouths before
interpreting recognition errors. They are previews before numerical normalization.

For demo evaluation, record 30 sentences across two sessions plus ten relaxed-face
clips. Make a JSONL file with one entry per archive; paths are relative to that file:

```json
{"capture":"captures/SAMPLE-UUID","reference":"I would like some water","session":"session-1"}
{"capture":"captures/REST-UUID","reference":"","session":"session-2"}
```

```bash
training/.venv/bin/silentvoice-local \
  --auto-avsr ../auto_avsr --checkpoint ../vsr_trlrs2lrs3vox2avsp_base.pth \
  evaluate /path/to/evaluation.jsonl --output training/artifacts/evaluation.json
```

Reports include raw transcripts, errors, word error rate, sentence exact match,
false transcripts on rest clips, session counts, and median/p95 processing time.
Failed sentence clips count as deletions rather than disappearing from accuracy.
Offline timings exclude phone capture and networking; measure Stop-to-result time
on the phone separately. Keep human corrections separate from reference labels.

## API and checks

- `GET /health`: `ready`, `modelVersion`, `device`, and optional startup `error`.
- `POST /v1/transcribe`: multipart text field `manifest` and ordered repeated
  `frames` PNG parts named `000000.png`, `000001.png`, etc. The manifest contains
  `sampleID` (UUID), `schemaVersion: 2`, `frameCount`, and monotonic `timestamps`.
- Response: `sampleID`, `transcript`, `modelVersion`, `processingSeconds`.
- Errors: JSON `code` and `message`; 422 for invalid/alignment/empty results,
  413 for oversized bodies, 503 for unavailable or busy model, 500 for unexpected
  inference failures. Malformed multipart data returns 400.
- Limits: 15–300 frames, approximately 0.5–10 seconds, 100 MB body, 1 MB per PNG,
  256×256 PNG images, no timestamp gaps over 200 ms. One inference at a time;
  busy requests are rejected for manual retry rather than queued indefinitely.

```bash
training/.venv/bin/python -m pytest training/tests -q
bash Scripts/run-capture-smoke.sh
bash Scripts/run-classifier-smoke.sh
bash Scripts/run-segmentation-smoke.sh
bash Scripts/run-transcription-smoke.sh
xcodebuild -quiet -project SilentVoice.xcodeproj -scheme SilentVoice \
  -sdk iphonesimulator -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

The tests use fake inference for HTTP/state behavior and do not establish
lip-reading accuracy. Physical-device checks must cover both portrait and landscape
crops, face loss, app backgrounding, Stop/automatic completion, denied local-network
permission, Mac disconnection, retry, transcript edits, and offline command mode.

An opt-in integration test loads the real weights and runs alignment and decoding
on a repeated public-domain face image. It checks model plumbing, not accuracy:

```bash
SILENTVOICE_RUN_MODEL_TEST=1 SILENTVOICE_AUTO_AVSR=../auto_avsr \
SILENTVOICE_CHECKPOINT=../vsr_trlrs2lrs3vox2avsp_base.pth \
  training/.venv/bin/python -m pytest training/tests/test_model_integration.py -s
```

MediaPipe needs access to macOS desktop graphics services even when the decoder
uses CPU. Run the server from a normal Terminal session. Version 0.10.21's
universal2 wheel carries an x86_64-only internal metadata tag; `pip check` reports
that platform tag on arm64 even though its native library imports and runs there.

See [the implementation validation record](LocalInferenceValidation.md) for checks
run on this Mac and the remaining physical-device and accuracy work.

## Provenance

Auto-AVSR code is Apache-2.0; model terms also derive from its training datasets.
See the upstream license and checkpoint provenance before broader distribution.
This implementation is based on the supplied `LocalInference.md`, but uses the
full sentence decoder rather than the guide's linear command probe. The notebook
and `silentvoice.train` mentioned in that guide were not present in this checkout
and are not prerequisites for this implementation.
