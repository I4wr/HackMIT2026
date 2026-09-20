import Foundation
import Combine

protocol FaceTracking: AnyObject {
    var currentFeatures: [Float] { get }
    var isFaceDetected: Bool { get }
    func start()
    func stop()
}

/// Compile-safe stand-in owned by the integration branch.
/// Person 1 can replace its internals with ARKit without changing callers.
@MainActor
final class FaceTracker: ObservableObject, FaceTracking {
    @Published private(set) var currentFeatures: [Float] = []
    @Published private(set) var isFaceDetected = false

    func start() {}

    func stop() {
        currentFeatures = []
        isFaceDetected = false
    }
}
