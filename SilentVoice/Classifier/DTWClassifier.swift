import Foundation

/// Placeholder owned by Person 2. `MockClassifier` keeps integration working meanwhile.
final class DTWClassifier: MouthClassifying {
    func train(samples: [MouthSample]) {}

    func predict(frames: [MouthFrame]) -> Prediction {
        .unknown
    }
}
