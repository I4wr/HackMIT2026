import Foundation

struct MouthFrame: Codable, Equatable, Sendable {
    let timestamp: TimeInterval
    let features: [Float]
}

struct MouthSample: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String
    let frames: [MouthFrame]

    init(id: UUID = UUID(), label: String, frames: [MouthFrame]) {
        self.id = id
        self.label = label
        self.frames = frames
    }
}
