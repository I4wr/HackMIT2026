import Foundation

/// Simple evaluation helpers for Person 2 / Person 4 integration.
struct ClassifierEvaluator {
    struct Result: Sendable {
        let total: Int
        let correct: Int
        let unknowns: Int
        let confusion: [String: [String: Int]]

        var accuracy: Float {
            guard total > 0 else { return 0 }
            return Float(correct) / Float(total)
        }
    }

    static func evaluate(
        classifier: DTWClassifier,
        labeledFrames: [(label: String, frames: [MouthFrame])]
    ) -> Result {
        var confusion: [String: [String: Int]] = [:]
        var correct = 0
        var unknowns = 0

        for item in labeledFrames {
            let prediction = classifier.predict(frames: item.frames)
            let predicted = prediction.accepted ? prediction.label : "UNKNOWN"
            if !prediction.accepted { unknowns += 1 }
            if predicted == item.label { correct += 1 }

            var row = confusion[item.label, default: [:]]
            row[predicted, default: 0] += 1
            confusion[item.label] = row
        }

        return Result(
            total: labeledFrames.count,
            correct: correct,
            unknowns: unknowns,
            confusion: confusion
        )
    }
}
