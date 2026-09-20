import Foundation

/// Simulator / unsupported-device stand-in. Matches Person 1's 24-feature schema.
enum MockMouthSequence {
    static let frameCount = 45
    static let frameInterval: TimeInterval = 1.0 / 30.0

    static func frames() -> [MouthFrame] {
        let featureCount = MouthFeatureSchema.names.count
        return (0..<frameCount).map { index in
            let timestamp = TimeInterval(index) * frameInterval
            let progress = Float(index) / Float(max(frameCount - 1, 1))
            let jaw = 0.08 + 0.35 * sin(progress * Float.pi)
            let mouthFunnel = max(0, jaw - 0.12)
            let lipPucker = 0.05 + 0.2 * (1 - abs(progress - 0.5) * 2)
            var features = Array(repeating: Float(0), count: featureCount)
            if featureCount > 0 { features[0] = jaw }
            if featureCount > 5 { features[5] = mouthFunnel }
            if featureCount > 6 { features[6] = lipPucker }
            return MouthFrame(timestamp: timestamp, features: features)
        }
    }
}
