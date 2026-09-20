import Foundation

/// Output of preprocessing: fixed-length frames plus motion energy
/// used to reject REST / empty articulations before DTW.
struct ProcessedSequence: Sendable, Equatable {
    let frames: [[Float]]
    let motionEnergy: Float

    init(frames: [[Float]], motionEnergy: Float) {
        self.frames = frames
        self.motionEnergy = motionEnergy
    }

    var isEmpty: Bool { frames.isEmpty }
}
