import Foundation

/// Artificial samples so Person 2 can develop without TrueDepth / an iPhone.
/// Vocabulary matches the hackathon MVP phrases.
enum FakeMouthSamples {
    static let vocabulary = ["help", "water", "yes", "no", "stop"]

    static func help() -> MouthSample { pattern(label: "help", kind: .rising) }
    static func water() -> MouthSample { pattern(label: "water", kind: .falling) }
    static func yes() -> MouthSample { pattern(label: "yes", kind: .pulse) }
    static func no() -> MouthSample { pattern(label: "no", kind: .doublePulse) }
    static func stop() -> MouthSample { pattern(label: "stop", kind: .holdThenDrop) }
    static func rest() -> MouthSample { pattern(label: "REST", kind: .flat) }

    /// Two slightly noisy copies per phrase for training.
    static func trainingSet(noise: Float = 0.02) -> [MouthSample] {
        vocabulary.flatMap { label -> [MouthSample] in
            let base = sample(for: label)
            return [
                base,
                jitter(base, amount: noise),
            ]
        }
    }

    /// Held-out copies with different noise for evaluation.
    static func evaluationSet(noise: Float = 0.015) -> [(label: String, frames: [MouthFrame])] {
        vocabulary.map { label in
            let sample = jitter(sample(for: label), amount: noise)
            return (label, sample.frames)
        }
    }

    static func sample(for label: String) -> MouthSample {
        switch label {
        case "help": return help()
        case "water": return water()
        case "yes": return yes()
        case "no": return no()
        case "stop": return stop()
        case "REST": return rest()
        default: return rest()
        }
    }

    /// Unrelated wavy pattern — should classify as UNKNOWN when thresholds are strict.
    static func unrelatedFrames() -> [MouthFrame] {
        (0..<20).map { i in
            MouthFrame(
                timestamp: Double(i) * 0.05,
                features: [sin(Float(i)), cos(Float(i) * 2), 0.25]
            )
        }
    }

    // MARK: - Stress / collision fixtures

    /// Near-twin of `yes` with a slightly shifted pulse — used to stress DTW.
    static func yesNearCollision() -> MouthSample {
        pattern(label: "yes-twin", kind: .pulseShifted)
    }

    /// Another rising-ish shape close to `help` — should usually lose to help
    /// or be rejected by the score-gap rule when both templates exist.
    static func helpNearCollision() -> MouthSample {
        pattern(label: "help-twin", kind: .risingSoft)
    }

    /// Ambiguous mid-blend of yes+no energy — often should be UNKNOWN.
    static func ambiguousYesNo() -> MouthSample {
        pattern(label: "ambiguous", kind: .ambiguousYesNo)
    }

    static func noisyCopy(_ sample: MouthSample, amount: Float = 0.03) -> MouthSample {
        jitter(sample, amount: amount)
    }

    // MARK: - Pattern generators

    private enum Kind {
        case rising, falling, pulse, doublePulse, holdThenDrop, flat
        case pulseShifted, risingSoft, ambiguousYesNo
    }

    private static func pattern(label: String, kind: Kind, frameCount: Int = 20) -> MouthSample {
        let frames = (0..<frameCount).map { i -> MouthFrame in
            let t = Float(i) / Float(max(frameCount - 1, 1))
            let features: [Float]
            switch kind {
            case .rising:
                features = [t, t * 0.5, 0.1]
            case .falling:
                features = [1 - t, 1 - t * 0.5, 0.9]
            case .pulse:
                let bump = exp(-pow((t - 0.5) * 6, 2))
                features = [bump, bump * 0.7, 0.3]
            case .doublePulse:
                let bump1 = exp(-pow((t - 0.3) * 8, 2))
                let bump2 = exp(-pow((t - 0.7) * 8, 2))
                features = [bump1 + bump2, bump2, 0.55]
            case .holdThenDrop:
                let value: Float = t < 0.65 ? 0.85 : max(0, 0.85 - (t - 0.65) * 4)
                features = [value, value * 0.4, 0.2]
            case .flat:
                features = [0.05, 0.05, 0.05]
            case .pulseShifted:
                let bump = exp(-pow((t - 0.55) * 6, 2))
                features = [bump, bump * 0.65, 0.32]
            case .risingSoft:
                features = [t * 0.9, t * 0.45, 0.12]
            case .ambiguousYesNo:
                let bump = exp(-pow((t - 0.45) * 5, 2))
                let bump2 = exp(-pow((t - 0.65) * 7, 2))
                features = [bump * 0.7 + bump2 * 0.5, bump2, 0.4]
            }
            return MouthFrame(timestamp: Double(i) * 0.05, features: features)
        }
        return MouthSample(label: label, frames: frames)
    }

    private static func jitter(_ sample: MouthSample, amount: Float) -> MouthSample {
        let frames = sample.frames.map { frame -> MouthFrame in
            let noisy = frame.features.map { value -> Float in
                let delta = Float.random(in: -amount...amount)
                return value + delta
            }
            return MouthFrame(timestamp: frame.timestamp, features: noisy)
        }
        return MouthSample(id: UUID(), label: sample.label, frames: frames)
    }
}
