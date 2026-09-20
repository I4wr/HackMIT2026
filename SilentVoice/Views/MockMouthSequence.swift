import Foundation

/// Synthetic TrueDepth frames so the interface can be exercised before Person 1's recorder lands.
enum MockMouthSequence {
    static let frameCount = 45
    static let frameInterval: TimeInterval = 1.0 / 30.0

    static func frames() -> [MouthFrame] {
        (0..<frameCount).map { index in
            let timestamp = TimeInterval(index) * frameInterval
            let progress = Float(index) / Float(max(frameCount - 1, 1))
            let jaw = 0.08 + 0.35 * sin(progress * Float.pi)
            let mouthFunnel = max(0, jaw - 0.12)
            let lipPucker = 0.05 + 0.2 * (1 - abs(progress - 0.5) * 2)
            return MouthFrame(timestamp: timestamp, features: [jaw, mouthFunnel, lipPucker])
        }
    }
}
