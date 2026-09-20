import Foundation

/// How a query sequence is aligned against a stored template.
enum DTWMatchStrategy: String, Sendable {
    /// Classic fixed-endpoint DTW. The query's first and last frames must align with
    /// the template's first and last, so leading and trailing rest frames have to be
    /// warped against the template's own rest frames instead of being skipped.
    case whole
    /// Open-begin / open-end DTW. The template is matched against the best-fitting
    /// *subsequence* of the query, so rest frames before and after the articulation
    /// cost nothing, and the alignment reports the span it actually used.
    case subsequence
}

/// One template alignment: how well it matched, and which query frames it used.
struct DTWAlignment: Equatable, Sendable {
    let distance: Float
    /// First query frame covered by the match, inclusive.
    let startIndex: Int
    /// Last query frame covered by the match, inclusive.
    let endIndex: Int

    var span: Int { max(0, endIndex - startIndex + 1) }
}

/// Nearest-neighbor DTW classifier.
///
/// Threshold guidance:
/// - Synthetic / smoke: acceptance ≈ 0.40, gap ≈ 0.02, motion ≈ 0.01
/// - Real TrueDepth: start near acceptance 0.75, gap 0.05, motion 0.02
///
/// IMPORTANT: the two strategies score on DIFFERENT scales. `.whole` returns a raw
/// accumulated cost that grows with sequence length, so its similarity values sit very
/// low on real data. `.subsequence` divides by the optimal path length, so its values
/// are per-step and land in a far more usable range. Re-tune all three thresholds
/// after switching strategies; the guidance above applies to `.whole` only.
final class DTWClassifier: MouthClassifying {
    var preprocessor: Preprocessor
    var acceptanceThreshold: Float
    var minimumScoreGap: Float
    var minimumMotionEnergy: Float
    /// Defaults to `.whole`, so behavior is unchanged until this is explicitly flipped.
    var matchStrategy: DTWMatchStrategy
    /// `.subsequence` only. Rejects alignments whose matched span is implausible next to
    /// the template length. This is what stops open-ended matching from collapsing onto
    /// a couple of quiet frames.
    var maxSpanRatio: Float

    private var templates: [(label: String, frames: [[Float]])] = []

    init(
        preprocessor: Preprocessor = Preprocessor(),
        acceptanceThreshold: Float = 0.75,
        minimumScoreGap: Float = 0.05,
        minimumMotionEnergy: Float = 0.02,
        matchStrategy: DTWMatchStrategy = .whole,
        maxSpanRatio: Float = 2.0
    ) {
        self.preprocessor = preprocessor
        self.acceptanceThreshold = acceptanceThreshold
        self.minimumScoreGap = minimumScoreGap
        self.minimumMotionEnergy = minimumMotionEnergy
        self.matchStrategy = matchStrategy
        self.maxSpanRatio = maxSpanRatio
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

        var byLabel: [String: DTWAlignment] = [:]
        for template in templates {
            guard let alignment = Self.align(
                query: processed.frames,
                template: template.frames,
                strategy: matchStrategy,
                maxSpanRatio: maxSpanRatio
            ) else { continue }
            if let existing = byLabel[template.label], existing.distance <= alignment.distance {
                continue
            }
            byLabel[template.label] = alignment
        }

        let ranked = byLabel
            .map { label, alignment in
                Candidate(
                    label: label,
                    distance: alignment.distance,
                    score: Self.similarity(from: alignment.distance),
                    alignment: alignment
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

    /// Aligns `query` against `template`. Returns nil when there is no usable alignment.
    static func align(
        query: [[Float]],
        template: [[Float]],
        strategy: DTWMatchStrategy,
        maxSpanRatio: Float = 2.0
    ) -> DTWAlignment? {
        guard !query.isEmpty, !template.isEmpty else { return nil }
        switch strategy {
        case .whole:
            // Unchanged legacy path: endpoints pinned, raw accumulated cost.
            let distance = dtwDistance(query, template)
            guard distance.isFinite else { return nil }
            return DTWAlignment(distance: distance, startIndex: 0, endIndex: query.count - 1)
        case .subsequence:
            return subsequenceAlignment(query: query, template: template, maxSpanRatio: maxSpanRatio)
        }
    }

    /// Open-begin / open-end DTW, normalized by the optimal path length.
    ///
    /// `D[i][0] = 0` lets a match begin at any query frame; taking the minimum over
    /// `D[i][m]` across every row lets it end at any query frame. The path-length
    /// division is not optional: a shorter path always accumulates less cost, so
    /// without it every template prefers the two quietest frames in the query.
    static func subsequenceAlignment(
        query: [[Float]],
        template: [[Float]],
        maxSpanRatio: Float
    ) -> DTWAlignment? {
        let n = query.count
        let m = template.count
        guard n > 0, m > 0 else { return nil }

        var previousCost = [Float](repeating: .infinity, count: m + 1)
        var previousSteps = [Int](repeating: 0, count: m + 1)
        var previousStart = [Int](repeating: 0, count: m + 1)
        var currentCost = [Float](repeating: .infinity, count: m + 1)
        var currentSteps = [Int](repeating: 0, count: m + 1)
        var currentStart = [Int](repeating: 0, count: m + 1)

        previousCost[0] = 0

        var best: DTWAlignment?

        for i in 1...n {
            // Free start: skipping the first i query frames costs nothing, and a path
            // leaving (i, 0) consumes query[i] next.
            currentCost[0] = 0
            currentSteps[0] = 0
            currentStart[0] = i

            for j in 1...m {
                let stepCost = euclidean(query[i - 1], template[j - 1])
                var bestPrevious = previousCost[j - 1]      // diagonal
                var steps = previousSteps[j - 1]
                var start = previousStart[j - 1]
                if previousCost[j] < bestPrevious {         // consume a query frame
                    bestPrevious = previousCost[j]
                    steps = previousSteps[j]
                    start = previousStart[j]
                }
                // `j > 1` keeps a match from leaving the free-start cell horizontally.
                // That transition would consume query[i - 1] while the cell records the
                // start as i, reporting a span one frame short. The diagonal out of
                // (i - 1, 0) already covers starting at query[i - 1], so nothing is lost.
                if j > 1, currentCost[j - 1] < bestPrevious {   // consume a template frame
                    bestPrevious = currentCost[j - 1]
                    steps = currentSteps[j - 1]
                    start = currentStart[j - 1]
                }
                currentCost[j] = stepCost + bestPrevious
                currentSteps[j] = steps + 1
                currentStart[j] = start
            }

            let total = currentCost[m]
            if total.isFinite {
                let startIndex = min(max(0, currentStart[m]), i - 1)
                let candidate = DTWAlignment(
                    distance: total / Float(max(1, currentSteps[m])),
                    startIndex: startIndex,
                    endIndex: i - 1
                )
                if spanIsPlausible(candidate.span, templateLength: m, maxRatio: maxSpanRatio),
                   candidate.distance < (best?.distance ?? .infinity) {
                    best = candidate
                }
            }

            swap(&previousCost, &currentCost)
            swap(&previousSteps, &currentSteps)
            swap(&previousStart, &currentStart)
        }

        return best
    }

    private static func spanIsPlausible(_ span: Int, templateLength: Int, maxRatio: Float) -> Bool {
        guard span > 0 else { return false }
        guard maxRatio > 1 else { return true }
        let length = Float(templateLength)
        return Float(span) >= length / maxRatio && Float(span) <= length * maxRatio
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
