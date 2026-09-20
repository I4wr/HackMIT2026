import Foundation

/// Preprocesses a raw mouth sequence for DTW:
/// baseline → smooth → resample → optional feature velocities.
struct Preprocessor: Sendable {
    var targetFrameCount: Int
    var smoothingWindow: Int
    var includeVelocities: Bool

    init(
        targetFrameCount: Int = 45,
        smoothingWindow: Int = 3,
        includeVelocities: Bool = true
    ) {
        self.targetFrameCount = max(1, targetFrameCount)
        self.smoothingWindow = max(1, smoothingWindow)
        self.includeVelocities = includeVelocities
    }

    func process(_ frames: [MouthFrame]) -> ProcessedSequence {
        guard !frames.isEmpty else {
            return ProcessedSequence(frames: [], motionEnergy: 0)
        }

        let featureCount = frames.map(\.features.count).max() ?? 0
        guard featureCount > 0 else {
            return ProcessedSequence(frames: [], motionEnergy: 0)
        }

        let padded = frames.map { pad($0.features, to: featureCount) }
        let baselined = subtractBaseline(padded)
        let smoothed = smooth(baselined, window: smoothingWindow)
        let energy = Self.motionEnergy(of: smoothed)
        let resampled = resample(smoothed, to: targetFrameCount)
        let finalFrames = includeVelocities ? appendVelocities(resampled) : resampled
        return ProcessedSequence(frames: finalFrames, motionEnergy: energy)
    }

    func process(_ sample: MouthSample) -> ProcessedSequence {
        process(sample.frames)
    }

    static func motionEnergy(of series: [[Float]]) -> Float {
        guard series.count >= 2 else { return 0 }
        var total: Float = 0
        var steps = 0
        for i in 1..<series.count {
            let previous = series[i - 1]
            let current = series[i]
            let count = min(previous.count, current.count)
            guard count > 0 else { continue }
            var frameSum: Float = 0
            for j in 0..<count {
                frameSum += abs(current[j] - previous[j])
            }
            total += frameSum / Float(count)
            steps += 1
        }
        guard steps > 0 else { return 0 }
        return total / Float(steps)
    }

    private func pad(_ features: [Float], to count: Int) -> [Float] {
        if features.count >= count {
            return Array(features.prefix(count))
        }
        return features + Array(repeating: 0, count: count - features.count)
    }

    private func subtractBaseline(_ series: [[Float]]) -> [[Float]] {
        guard let first = series.first else { return series }
        return series.map { frame in
            zip(frame, first).map { $0 - $1 }
        }
    }

    private func smooth(_ series: [[Float]], window: Int) -> [[Float]] {
        guard window > 1, series.count > 1 else { return series }
        let radius = window / 2
        return series.indices.map { index in
            let start = max(0, index - radius)
            let end = min(series.count - 1, index + radius)
            let slice = series[start...end]
            let count = Float(slice.count)
            let featureCount = series[index].count
            return (0..<featureCount).map { featureIndex in
                slice.reduce(Float(0)) { $0 + $1[featureIndex] } / count
            }
        }
    }

    private func resample(_ series: [[Float]], to count: Int) -> [[Float]] {
        guard !series.isEmpty else { return [] }
        if series.count == count { return series }
        if series.count == 1 {
            return Array(repeating: series[0], count: count)
        }

        let lastIndex = Float(series.count - 1)
        return (0..<count).map { targetIndex in
            let position = Float(targetIndex) * lastIndex / Float(count - 1)
            let lower = Int(floor(position))
            let upper = min(series.count - 1, lower + 1)
            let t = position - Float(lower)
            let a = series[lower]
            let b = series[upper]
            return zip(a, b).map { $0 + ($1 - $0) * t }
        }
    }

    private func appendVelocities(_ series: [[Float]]) -> [[Float]] {
        guard !series.isEmpty else { return series }
        return series.indices.map { index in
            let previous = index == 0 ? series[index] : series[index - 1]
            let current = series[index]
            let velocity = zip(current, previous).map { $0 - $1 }
            return current + velocity
        }
    }
}
