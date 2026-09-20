import Foundation

/// Classifier output for Person 3 / Person 4 UI wiring.
///
/// Display contract:
/// 1. If `accepted == true`: show `label` and speak it.
/// 2. If `accepted == false`: show **UNKNOWN**. Still show `candidates`
///    and `score` as best-match confidence — never "unknown word 80%".
/// 3. `candidates` is ordered best → worst (max 3).
/// 4. `score` is similarity in 0...1 (higher is better).
struct Prediction: Equatable, Sendable {
    let label: String
    let score: Float
    let accepted: Bool
    let candidates: [Candidate]
    let suggestions: [LanguageSuggestion]

    static let unknown = Prediction(label: "UNKNOWN", score: 0, accepted: false)

    init(
        label: String,
        score: Float,
        accepted: Bool,
        candidates: [Candidate] = [],
        suggestions: [LanguageSuggestion] = []
    ) {
        self.label = label
        self.score = score
        self.accepted = accepted
        self.candidates = candidates
        self.suggestions = suggestions
    }
}

struct Candidate: Equatable, Sendable {
    let label: String
    let distance: Float
    let score: Float
    /// Which query frames this template matched. Nil under `.whole` matching from
    /// callers that predate it; populated by `DTWClassifier` for both strategies.
    let alignment: DTWAlignment?

    init(label: String, distance: Float, score: Float, alignment: DTWAlignment? = nil) {
        self.label = label
        self.distance = distance
        self.score = score
        self.alignment = alignment
    }
}

/// Combined visual + language ranking for assistive suggestions.
struct LanguageSuggestion: Equatable, Sendable {
    let label: String
    let visualScore: Float
    let languageScore: Float
    let combinedScore: Float

    init(label: String, visualScore: Float, languageScore: Float, combinedScore: Float) {
        self.label = label
        self.visualScore = visualScore
        self.languageScore = languageScore
        self.combinedScore = combinedScore
    }
}

protocol MouthClassifying: AnyObject {
    func train(samples: [MouthSample])
    func predict(frames: [MouthFrame]) -> Prediction
}

/// Drop-in stub so Person 4 can wire UI before real DTW is trained.
final class MockClassifier: MouthClassifying {
    private let canned: Prediction

    init(
        canned: Prediction = Prediction(
            label: "help",
            score: 0.92,
            accepted: true,
            candidates: [
                Candidate(label: "help", distance: 0.1, score: 0.92),
                Candidate(label: "water", distance: 0.8, score: 0.55),
            ]
        )
    ) {
        self.canned = canned
    }

    func train(samples: [MouthSample]) {}

    func predict(frames: [MouthFrame]) -> Prediction {
        _ = frames
        return canned
    }
}
