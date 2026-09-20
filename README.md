# SilentVoice

SilentVoice is an iOS SwiftUI prototype that turns silent mouth movements captured by a TrueDepth camera into spoken phrases.

## Requirements

- macOS with Xcode 27 or later
- A physical TrueDepth-capable iPhone for ARKit validation
- An Apple development team selected in **Signing & Capabilities**

The simulator is useful for UI and integration work, but it cannot validate TrueDepth face tracking.

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

The checked-in app uses `FaceTracker` and `MockClassifier`, so navigation, prediction flow, persistence, and speech can compile before the hardware tracker and real classifier land. Keep pull requests small and rebase feature branches after each merge to `main`.

`SilentVoiceTests/` contains the first unit-test source. Person 4 should add the test target in Xcode when setting the project development team; teammates should not independently edit `project.pbxproj`.
