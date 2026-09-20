import Foundation

/// Offline A/B for `.whole` vs `.subsequence` matching — not part of the iOS app target.
///
/// Simulates the real capture failure: the articulation does not fill the recording
/// window, because the speaker reacted late or finished early, so the query carries
/// leading and trailing rest frames the template does not have.
///
/// `.whole` DTW must warp those rest frames against the template's own frames.
/// `.subsequence` DTW skips them for free and reports the span it matched.
///
/// Note this isolates the ALIGNMENT problem only. Padding repeats the first frame, so
/// `Preprocessor.subtractBaseline` still sees the same baseline. The frame-0 baseline
/// problem is fixed by endpointing at capture time, not here.
@main
struct SegmentationSmokeMain {
    static func main() {
        let training = FakeMouthSamples.trainingSet()
        let evaluation = FakeMouthSamples.evaluationSet()

        let whole = make(.whole)
        let subsequence = make(.subsequence)
        whole.train(samples: training)
        subsequence.train(samples: training)

        print("templates=\(training.count) evaluation=\(evaluation.count)")
        print("")
        print("leading rest frames │ .whole top-1 │ .subsequence top-1")
        print("────────────────────┼──────────────┼───────────────────")

        var rows: [(pad: Int, whole: Double, subsequence: Double)] = []
        for pad in [0, 3, 6, 9, 12] {
            let shifted = evaluation.map {
                (label: $0.label, frames: padded($0.frames, leading: pad, trailing: pad / 2))
            }
            let a = topOneAccuracy(whole, shifted)
            let b = topOneAccuracy(subsequence, shifted)
            rows.append((pad, a, b))
            print("\(column("\(pad)", 19)) │ \(column(percent(a), 12)) │ \(column(percent(b), 18))")
        }

        print("")
        print("Recovered spans (.subsequence), 9 leading rest frames:")
        for item in evaluation.prefix(5) {
            let frames = padded(item.frames, leading: 9, trailing: 4)
            let prediction = subsequence.predict(frames: frames)
            guard let top = prediction.candidates.first else {
                print("  \(item.label) → no candidates")
                continue
            }
            let span = top.alignment.map { "[\($0.startIndex)...\($0.endIndex)] span=\($0.span)" } ?? "n/a"
            let distance = String(format: "%.4f", top.distance)
            print("  \(column(item.label, 6)) → \(column(top.label, 6)) dist=\(distance) \(span)")
        }

        // Invariants that must hold by construction, whatever the accuracy numbers say.
        var checked = 0
        for item in evaluation {
            let frames = padded(item.frames, leading: 9, trailing: 4)
            let prediction = subsequence.predict(frames: frames)
            // DTW indices address the resampled sequence (45 frames by default).
            let processedCount = subsequence.preprocessor.process(frames).frames.count
            for candidate in prediction.candidates {
                guard let alignment = candidate.alignment else {
                    fputs("FAIL: .subsequence candidate missing alignment\n", stderr)
                    exit(1)
                }
                guard alignment.distance.isFinite, alignment.distance >= 0 else {
                    fputs("FAIL: non-finite alignment distance for \(candidate.label)\n", stderr)
                    exit(1)
                }
                guard alignment.startIndex >= 0,
                      alignment.endIndex < processedCount,
                      alignment.startIndex <= alignment.endIndex else {
                    fputs("FAIL: span out of bounds for \(candidate.label): "
                          + "[\(alignment.startIndex)...\(alignment.endIndex)] of \(processedCount) processed frames\n", stderr)
                    exit(1)
                }
                checked += 1
            }
        }
        print("")
        print("span invariants OK across \(checked) alignments")

        guard let widest = rows.last else {
            fputs("FAIL: no rows evaluated\n", stderr)
            exit(1)
        }
        print("at \(widest.pad) leading rest frames: "
              + ".whole \(percent(widest.whole)) vs .subsequence \(percent(widest.subsequence))")
        print("PASS: subsequence matching ran clean. Compare the table before flipping matchStrategy.")
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f", value * 100) + "%"
    }

    private static func column(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
    }

    private static func make(_ strategy: DTWMatchStrategy) -> DTWClassifier {
        DTWClassifier(
            acceptanceThreshold: ClassifierIntegration.syntheticAcceptance,
            minimumScoreGap: ClassifierIntegration.syntheticGap,
            minimumMotionEnergy: ClassifierIntegration.syntheticMotionEnergy,
            matchStrategy: strategy
        )
    }

    /// Threshold-independent: the two strategies score on different scales, so ranking
    /// is the only fair comparison. Acceptance is tuned separately, per strategy.
    private static func topOneAccuracy(
        _ classifier: DTWClassifier,
        _ items: [(label: String, frames: [MouthFrame])]
    ) -> Double {
        guard !items.isEmpty else { return 0 }
        var correct = 0
        for item in items where classifier.predict(frames: item.frames).candidates.first?.label == item.label {
            correct += 1
        }
        return Double(correct) / Double(items.count)
    }

    /// Repeats the first and last frame so the articulation sits inside a longer window,
    /// the way a real take does when the speaker starts late or stops early.
    private static func padded(_ frames: [MouthFrame], leading: Int, trailing: Int) -> [MouthFrame] {
        guard let first = frames.first, let last = frames.last else { return frames }
        var features: [[Float]] = []
        if leading > 0 { features.append(contentsOf: Array(repeating: first.features, count: leading)) }
        features.append(contentsOf: frames.map(\.features))
        if trailing > 0 { features.append(contentsOf: Array(repeating: last.features, count: trailing)) }
        let step = 1.0 / 30.0
        return features.enumerated().map {
            MouthFrame(timestamp: Double($0.offset) * step, features: $0.element)
        }
    }
}
