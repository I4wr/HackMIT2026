import Foundation

struct Prediction: Equatable, Sendable {
    let label: String
    let score: Float
    let accepted: Bool

    static let unknown = Prediction(label: "UNKNOWN", score: 0, accepted: false)
}

protocol MouthClassifying: AnyObject {
    func train(samples: [MouthSample])
    func predict(frames: [MouthFrame]) -> Prediction
}

final class MockClassifier: MouthClassifying {
    func train(samples: [MouthSample]) {}

    func predict(frames: [MouthFrame]) -> Prediction {
        Prediction(label: "I need help", score: 0.92, accepted: true)
    }
}
