import Foundation

struct MouthFrame: Codable, Equatable, Sendable {
    let timestamp: TimeInterval
    let features: [Float]

    init(timestamp: TimeInterval, features: [Float]) {
        self.timestamp = timestamp
        self.features = features
    }
}

struct MouthSample: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String
    let frames: [MouthFrame]
    /// Nil for legacy/demo samples; live recordings link to captures/<id>/.
    let captureSource: String?

    init(id: UUID = UUID(), label: String, frames: [MouthFrame], captureSource: String? = nil) {
        self.id = id
        self.label = label
        self.frames = frames
        self.captureSource = captureSource
    }
}
