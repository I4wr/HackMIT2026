# DepthSpeech

DepthSpeech is an experimental iPhone app that converts visible mouth movements into text and spoken audio without recording microphone input. It uses the TrueDepth camera to capture facial motion, supports local sentence transcription through a nearby Mac, and can read an approved or edited result aloud with ElevenLabs or the device's built-in speech synthesizer.

The Xcode project, target, source directory, bundle identifier, and some internal settings still use the original `SilentVoice` name. Use those names in paths and commands until the project itself is renamed.

## Current capabilities

- Records synchronized TrueDepth face data and full-face RGB crops on a physical iPhone.
- Sends short sentence recordings to a Mac running the local Auto-AVSR service and returns an editable English transcript.
- Includes an offline, user-calibrated DTW classifier for the command words `help`, `water`, `stop`, `yes`, and `no`, plus `REST` and `UNKNOWN` negative examples.
- Speaks accepted command phrases or edited sentence transcripts using ElevenLabs. If no key is available or the request fails, it falls back to `AVSpeechSynthesizer`.
- Saves capture archives on the device for debugging and evaluation.

This is a research prototype, not an accessibility or medical device. Silent-speech accuracy has not been established, and the pretrained sentence model was trained on visible speech with audio rather than deliberately mouthed silent speech.

## Requirements

### iPhone app

- macOS with Xcode 27 or later.
- An iPhone running iOS 17 or later with a TrueDepth front camera.
- An Apple development team selected under **Signing & Capabilities**.

The simulator can compile and exercise non-camera UI, but it cannot validate TrueDepth tracking or real capture behavior.

### Local sentence transcription

- An Apple Silicon Mac running macOS 14 or later.
- Python 3.12.
- Approximately 5 GB of free space for the environment, Auto-AVSR checkout, and model checkpoint.
- The Mac and iPhone on the same trusted Wi-Fi network.

## Run the iPhone app

1. Open `SilentVoice.xcodeproj` in Xcode.
2. Select the `SilentVoice` target and choose your development team under **Signing & Capabilities**.
3. Connect and trust a TrueDepth-capable iPhone.
4. Select the iPhone as the run destination and press **Run**.
5. Allow camera and local-network access when prompted.

The current bundle identifier is `com.hackmit.SilentVoice`. Change it if your signing team requires a unique identifier. The camera and local-network usage descriptions are already configured.

## Run local sentence transcription

The app's primary **Start silent speech** flow records up to ten seconds of face crops and sends them to the local Mac service. It does not send depth maps, face meshes, or microphone audio to the server.

Follow [the local inference setup guide](docs/LocalInference.md) to install the pinned Python environment, Auto-AVSR source, and checkpoint. Once setup is complete, start the server from the repository root:

```bash
SILENTVOICE_DEVICE=cpu bash Scripts/run-local-inference.sh
```

Check readiness in another terminal:

```bash
curl http://localhost:8000/health
```

Wait for a response containing `"ready": true`. On the iPhone, open **Start silent speech**, enter the Mac's `.local` hostname and port `8000`, then tap **Test Connection**. Record a sentence, review or correct the transcript, and tap **Speak**.

CPU mode is the most predictable configuration for the pinned model. The server also accepts `SILENTVOICE_DEVICE=auto`, which prefers MPS and falls back to CPU when necessary. See [LocalInference.md](docs/LocalInference.md) for setup, network, archive, evaluation, and troubleshooting details.

## Configure spoken output

DepthSpeech uses the ElevenLabs text-to-speech endpoint with the Adam voice (`pNInz6obpgDQGcFmaJgB`) and the `eleven_multilingual_v2` model. ElevenLabs calls require network access and consume account credits.

Create an API key in [ElevenLabs developer settings](https://elevenlabs.io/app/developers/api-keys), then configure it using one of these methods:

1. In Xcode, open **Product → Scheme → Edit Scheme → Run → Arguments** and add the environment variable `ELEVENLABS_API_KEY`.
2. Or create the ignored local plist:

   ```bash
   cp SilentVoice/Resources/Secrets.example.plist SilentVoice/Resources/Secrets.plist
   ```

   Replace `paste-key-here` in `Secrets.plist` with the key.

Clean and rebuild the app after changing the plist. If ElevenLabs is unavailable, the key lacks text-to-speech permission, or playback fails, the app logs the error and uses the on-device English voice.

Never commit `Secrets.plist` or a real API key. Bundling a provider key in an iOS app is suitable only for a controlled prototype; a production app should call ElevenLabs through an authenticated backend.

## Offline command classifier

The repository also contains an on-device command pipeline based on ordered mouth features, preprocessing, subsequence DTW, rejection thresholds, and a small language-assist layer. Calibration targets 20 training recordings for each command and negative label. Validation and test recordings are archived separately and do not train the classifier.

Only TrueDepth calibration samples are loaded for live training; older mock samples are ignored. Accepted command labels map to spoken phrases such as `water` → “I need water.” The thresholds still require tuning with real multi-session device data.

The current home screen opens the sentence-transcription flow directly. The command calibration and recognition views remain in the codebase but are not currently exposed by the top-level navigation.

## Capture data and privacy

Capture archives are stored inside the app container at:

```text
Documents/captures/<sample UUID>/
```

Depending on capture validity and device support, an archive can contain timestamps, mouth and face PNGs, face-mesh vertices, blendshapes, camera transforms and intrinsics, native depth, masks, and calibration metadata. Invalid or incomplete frames are retained with validity information instead of being silently treated as usable training data.

The local transcription request sends only finalized 256×256 face PNGs and timing metadata to the configured Mac. The local HTTP service has no authentication or encryption, so use it only on a trusted network. ElevenLabs receives only the text passed to **Speak**; capture images and geometry are not sent to ElevenLabs.

Do not commit participant recordings or biometric face data. See [TrueDepth.md](docs/TrueDepth.md) for the archive schema and device checks.

## Validation

Run the lightweight Swift checks from the repository root:

```bash
bash Scripts/run-capture-smoke.sh
bash Scripts/run-classifier-smoke.sh
bash Scripts/run-segmentation-smoke.sh
bash Scripts/run-transcription-smoke.sh
```

Run the local-service tests after creating `training/.venv`:

```bash
training/.venv/bin/python -m pytest training/tests -q
```

Build the iOS app without signing:

```bash
xcodebuild -quiet \
  -project SilentVoice.xcodeproj \
  -scheme SilentVoice \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

These checks validate data plumbing and behavior, not lip-reading accuracy. Physical-device testing is still required for TrueDepth capture, orientation, face loss, app lifecycle behavior, networking, transcript correction, audio playback, and multi-session accuracy.

`SilentVoiceTests/` contains Swift test sources, but the Xcode project currently has no unit-test target. The shell smoke tests and Python tests are the runnable automated checks in this checkout.

## Repository layout

| Path | Purpose |
| --- | --- |
| `SilentVoice/App/` | App entry point and shared view model |
| `SilentVoice/Camera/` | TrueDepth tracking, feature extraction, rendering, and capture archives |
| `SilentVoice/Classifier/` | Preprocessing, DTW classification, evaluation, and language assistance |
| `SilentVoice/Services/` | Local transcription, sample persistence, ElevenLabs TTS, and speech playback |
| `SilentVoice/Views/` | SwiftUI capture, calibration, recognition, and transcript screens |
| `training/` | FastAPI server, Auto-AVSR integration, CLI, and Python tests |
| `Scripts/` | Local server launcher and Swift smoke checks |
| `docs/` | TrueDepth, local inference, and validation documentation |
| `sample-data/` | Schema fixtures only; recordings are intentionally excluded |

## Known limitations

- Sentence transcription requires a separately configured Mac and network connection.
- The local server only accepts `localhost` or `.local` hostnames and handles one inference at a time.
- The command vocabulary is fixed and requires per-user calibration.
- Missing or unreliable face crops prevent sentence transcription; missing depth alone does not.
- The app silently falls back to device speech in the UI, though the ElevenLabs error is printed to the Xcode console.
- Internal project names still say `SilentVoice`; only the product documentation currently uses `DepthSpeech`.

## Model provenance

The sentence pipeline integrates the upstream [Auto-AVSR](https://github.com/mpc001/auto_avsr) project and its published checkpoint. Auto-AVSR is Apache-2.0, while model use is also subject to the provenance and terms of its training datasets. Review those terms before distributing the model or deploying beyond a prototype.
