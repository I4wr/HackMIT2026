import Foundation

/// Nearest-neighbor DTW classifier.
///
/// Threshold guidance:
/// - Synthetic / smoke: acceptance ≈ 0.40, gap ≈ 0.02, motion ≈ 0.01
/// - Real TrueDepth: start near acceptance 0.75, gap 0.05, motion 0.02
final class DTWClassifier: MouthClassifying {
    var preprocessor: Preprocessor
    var acceptanceThreshold: Float
    var minimumScoreGap: Float
    var minimumMotionEnergy: Float

    private var templates: [(label: String, frames: [[Float]])] = []

    init(
        preprocessor: Preprocessor = Preprocessor(),
        acceptanceThreshold: Float = 0.75,
        minimumScoreGap: Float = 0.05,
        minimumMotionEnergy: Float = 0.02
    ) {
        self.preprocessor = preprocessor
        self.acceptanceThreshold = acceptanceThreshold
        self.minimumScoreGap = minimumScoreGap
        self.minimumMotionEnergy = minimumMotionEnergy
    }

    func train(samples: [MouthSample]) {
        templates = samples.compactMap { sample in
            let label = sample.label.uppercased()
            if label == "REST" || label == "UNKNOWN" { return nil }
            let processed = preprocessor.process(sample)
            guard !processed.isEmpty else { return nil }
            return (sample.label, processed.frames)
        }
    }

    func predict(frames: [MouthFrame]) -> Prediction {
        let processed = preprocessor.process(frames)
        guard !processed.isEmpty else {
            return rejected(score: 0, candidates: [])
        }

        if processed.motionEnergy < minimumMotionEnergy {
            return rejected(score: 0, candidates: [
                Candidate(label: "REST", distance: 0, score: 0)
            ])
        }

        guard !templates.isEmpty else {
            return rejected(score: 0, candidates: [])
        }

        var byLabel: [String: Float] = [:]
        for template in templates {
            let distance = Self.dtwDistance(processed.frames, template.frames)
            if let existing = byLabel[template.label] {
                byLabel[template.label] = min(existing, distance)
            } else {
                byLabel[template.label] = distance
            }
        }

        let ranked = byLabel
            .map { label, distance in
                Candidate(
                    label: label,
                    distance: distance,
                    score: Self.similarity(from: distance)
                )
            }
            .sorted { $0.distance < $1.distance }

        guard let best = ranked.first else {
            return rejected(score: 0, candidates: [])
        }

        let secondScore = ranked.dropFirst().first?.score ?? 0
        let gapOK = ranked.count < 2 || (best.score - secondScore) >= minimumScoreGap
        let accepted = best.score >= acceptanceThreshold && gapOK

        return Prediction(
            label: accepted ? best.label : "UNKNOWN",
            score: best.score,
            accepted: accepted,
            candidates: Array(ranked.prefix(3))
        )
    }

    private func rejected(score: Float, candidates: [Candidate]) -> Prediction {
        Prediction(label: "UNKNOWN", score: score, accepted: false, candidates: candidates)
    }

    static func dtwDistance(_ a: [[Float]], _ b: [[Float]]) -> Float {
        let n = a.count
        let m = b.count
        guard n > 0, m > 0 else { return .greatestFiniteMagnitude }

        var previous = [Float](repeating: .greatestFiniteMagnitude, count: m + 1)
        var current = [Float](repeating: .greatestFiniteMagnitude, count: m + 1)
        previous[0] = 0

        for i in 1...n {
            current[0] = .greatestFiniteMagnitude
            for j in 1...m {
                let cost = euclidean(a[i - 1], b[j - 1])
                let insertion = current[j - 1]
                let deletion = previous[j]
                let match = previous[j - 1]
                current[j] = cost + min(insertion, deletion, match)
            }
            swap(&previous, &current)
        }

        return previous[m]
    }

    static func similarity(from distance: Float) -> Float {
        1 / (1 + max(0, distance))
    }

    private static func euclidean(_ a: [Float], _ b: [Float]) -> Float {
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            let d = a[i] - b[i]
            sum += d * d
        }
        if a.count > count {
            for i in count..<a.count { sum += a[i] * a[i] }
        }
        if b.count > count {
            for i in count..<b.count { sum += b[i] * b[i] }
        }
        return sqrt(sum)
    }
}
