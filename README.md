# SilentVoice

SilentVoice is an iOS SwiftUI prototype that turns silent mouth movements captured by a TrueDepth camera into spoken command words.

## Requirements

- macOS with Xcode 27 or later
- A physical TrueDepth-capable iPhone for ARKit validation
- An Apple development team selected in **Signing & Capabilities**

The simulator is useful for UI and integration work, but it cannot validate TrueDepth face tracking.

## Spoken output (Grok TTS)

Accepted command words and sentence transcripts are spoken aloud through
`SpeechOutput` when you tap **Speak**. When an xAI API key is present, the app uses **Grok Voice TTS**
(`POST https://api.x.ai/v1/tts`, voice `rex`). Without a key, or if the request
fails, it falls back to on-device `AVSpeechSynthesizer`.

1. Create a key at [console.x.ai](https://console.x.ai/).
2. Either:
   - **Scheme env var:** Xcode → Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables → `XAI_API_KEY` = your key, or
   - **Local plist:** `cp SilentVoice/Resources/Secrets.example.plist SilentVoice/Resources/Secrets.plist` and paste the key (this file is gitignored).
3. Rebuild and run. After recognition, tap **Speak** to hear the phrase with Grok (or on-device speech if no key).

Do not commit real API keys.


## Start here

1. Open `SilentVoice.xcodeproj` in Xcode.
2. Select the `SilentVoice` target and your Apple development team. Automatic signing is enabled.
3. Connect and trust a TrueDepth iPhone.
4. Select that iPhone as the run destination and run the app.

The camera usage description is already configured. The bundle identifier is `com.hackmit.SilentVoice`; change it once, on the integration branch, if your signing team requires a unique value.

## Branch ownership

| Branch | Owner | Files |
| --- | --- | --- |
| `feature/truedepth` | Person 1 | `SilentVoice/Camera/` |
| `feature/classifier` | Person 2 | `SilentVoice/Classifier/` |
| `feature/interface` | Person 3 | `SilentVoice/Views/` |
| `feature/integration` | Person 4 | `SilentVoice/App/`, `SilentVoice/Services/`, Xcode project |

Shared contracts are in `MouthSample.swift`, `Prediction.swift`, and `FaceTracker.swift`. Coordinate before changing their public interfaces. Only Person 4 should change the Xcode project, signing, targets, file locations, or dependencies.

## Integration contract

The app uses `FaceTracker`, `DTWClassifier`, and a lightweight command-word language model. Calibration and recognition capture real camera frames after a countdown. Recognition first ranks visually plausible DTW candidates, then the language layer re-ranks close candidates and surfaces word suggestions from the closed word catalog. Accepted words can still speak fuller assistive output such as "I need water." Calibration offers training, validation, and test recordings plus REST/UNKNOWN negatives; only training recordings enter the on-device classifier. Earlier mock calibration samples are excluded when loading. DTW and language-assist thresholds still need tuning on real validation data.

Each take saves timestamped RGB mouth PNGs, all face-mesh vertices, all named blendshapes, camera transforms/intrinsics, and available native depth with its own timestamp, mask, and calibration data. Archives live in the app container under `Documents/captures/<sample UUID>/`. See [TrueDepth capture format and device checks](docs/TrueDepth.md).

Run `bash Scripts/run-capture-smoke.sh` and `bash Scripts/run-classifier-smoke.sh` for offline checks. These do not measure lip-reading accuracy.

`SilentVoiceTests/` contains the first unit-test source. Person 4 should add the test target in Xcode when setting the project development team; teammates should not independently edit `project.pbxproj`.
