import Foundation

/// Version 1 of the raw camera contract. Persist this version with datasets if
/// the feature list ever changes; old samples must not silently be reinterpreted.
enum MouthFeatureSchema {
    static let version = 1
    static let names = [
        "jawOpen", "jawForward", "jawLeft", "jawRight",
        "mouthClose", "mouthFunnel", "mouthPucker", "mouthLeft", "mouthRight",
        "mouthSmileLeft", "mouthSmileRight", "mouthFrownLeft", "mouthFrownRight",
        "mouthDimpleLeft", "mouthDimpleRight", "mouthStretchLeft", "mouthStretchRight",
        "mouthRollLower", "mouthRollUpper", "mouthShrugLower", "mouthShrugUpper",
        "mouthPressLeft", "mouthPressRight", "cheekPuff"
    ]

    /// Missing coefficients are zero; corrupt values invalidate the whole frame.
    /// Baseline subtraction, smoothing and resampling belong to the classifier.
    static func features(from coefficients: [String: Float]) -> [Float]? {
        let values = names.map { coefficients[$0] ?? 0 }
        guard values.allSatisfy(\.isFinite) else { return nil }
        return values.map { min(1, max(0, $0)) }
    }
}

/// Selects real camera frames on a 30 Hz timeline without synthesizing frames.
struct MouthFrameSampler {
    static let framesPerSecond = 30.0
    private var nextTimestamp: TimeInterval?
    private var lastTimestamp: TimeInterval?

    mutating func shouldEmit(at timestamp: TimeInterval) -> Bool {
        guard timestamp.isFinite, timestamp >= 0 else { return false }
        if let lastTimestamp, timestamp <= lastTimestamp { return false }
        lastTimestamp = timestamp
        let interval = 1 / Self.framesPerSecond
        guard let nextTimestamp else {
            self.nextTimestamp = timestamp + interval
            return true
        }
        // Permit small capture-clock jitter at the nominal frame boundary.
        guard timestamp + 0.001 >= nextTimestamp else { return false }
        let elapsedIntervals = max(1, floor((timestamp - nextTimestamp) / interval) + 1)
        self.nextTimestamp = nextTimestamp + elapsedIntervals * interval
        return true
    }

    mutating func reset() {
        nextTimestamp = nil
        lastTimestamp = nil
    }
}
