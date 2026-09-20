import Foundation
import Combine
import ARKit
import AVFoundation
import QuartzCore

@MainActor
protocol FaceTracking: AnyObject {
    var currentFeatures: [Float] { get }
    var isFaceDetected: Bool { get }
    func start()
    func stop()
}

/// Owns the single AR session shared by the camera preview and feature stream.
@MainActor
final class FaceTracker: NSObject, ObservableObject, FaceTracking, @preconcurrency ARSessionDelegate {
    enum Status: Equatable {
        case stopped, requestingPermission, unsupported, permissionDenied
        case lookingForFace, tracking, interrupted
        case failed(String)

        var message: String {
            switch self {
            case .stopped: return "Camera stopped"
            case .requestingPermission: return "Allow camera access to track your mouth"
            case .unsupported: return "Face tracking requires a physical TrueDepth iPhone"
            case .permissionDenied: return "Allow camera access for SilentVoice in Settings"
            case .lookingForFace: return "Position your face in front of the camera"
            case .tracking: return "Face detected"
            case .interrupted: return "Camera interrupted"
            case .failed(let message): return "Camera error: \(message)"
            }
        }
    }

    @Published private(set) var currentFeatures: [Float] = []
    @Published private(set) var isFaceDetected = false
    @Published private(set) var status: Status = .stopped
    @Published private(set) var framesPerSecond: Double = 0
    @Published private(set) var latestFrame: MouthFrame?

    static let featureNames = MouthFeatureSchema.names
    static let featureSchemaVersion = MouthFeatureSchema.version

    /// Emits once per sampled camera frame, including when the mouth is still.
    /// Delivery is on the main actor. Subscribe before start(); no frames replay.
    var frames: AnyPublisher<MouthFrame, Never> { frameSubject.eraseToAnyPublisher() }

    let session = ARSession()
    private let frameSubject = PassthroughSubject<MouthFrame, Never>()
    private var sampler = MouthFrameSampler()
    private var wantsToRun = false
    private var requestID = UUID()
    private var runStartedAt: TimeInterval = 0
    private var rateWindowStart: TimeInterval?
    private var rateWindowCount = 0

    override init() {
        super.init()
        // ARKit delegate callbacks and all observable state use the same queue.
        session.delegateQueue = .main
        session.delegate = self
    }

    func start() {
        guard !wantsToRun else { return }
        guard ARFaceTrackingConfiguration.isSupported,
              AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) != nil
        else {
            status = .unsupported
            return
        }
        wantsToRun = true
        requestID = UUID()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            runSession()
        case .notDetermined:
            status = .requestingPermission
            let pendingRequest = requestID
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self, self.wantsToRun, self.requestID == pendingRequest else { return }
                    if granted {
                        self.runSession()
                    } else {
                        self.wantsToRun = false
                        self.status = .permissionDenied
                    }
                }
            }
        case .denied, .restricted:
            wantsToRun = false
            status = .permissionDenied
        @unknown default:
            wantsToRun = false
            status = .permissionDenied
        }
    }

    private func runSession() {
        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 1
        configuration.isLightEstimationEnabled = false
        // Prefer native 30 Hz; higher-rate devices are sampled by timestamp.
        let formats = ARFaceTrackingConfiguration.supportedVideoFormats.filter {
            $0.captureDeviceType == .builtInTrueDepthCamera && $0.captureDevicePosition == .front
        }
        guard let format = formats.first(where: { $0.framesPerSecond == 30 }) ?? formats.first else {
            wantsToRun = false
            status = .unsupported
            return
        }
        configuration.videoFormat = format
        clearFace()
        runStartedAt = CACurrentMediaTime()
        status = .lookingForFace
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        wantsToRun = false
        requestID = UUID() // Ignore an outstanding permission response.
        session.pause()
        clearFace()
        status = .stopped
    }

    private func clearFace() {
        if !currentFeatures.isEmpty { currentFeatures = [] }
        if isFaceDetected { isFaceDetected = false }
        if latestFrame != nil { latestFrame = nil }
        if framesPerSecond != 0 { framesPerSecond = 0 }
        sampler.reset()
        rateWindowStart = nil
        rateWindowCount = 0
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard wantsToRun, frame.timestamp >= runStartedAt,
              status == .lookingForFace || status == .tracking else { return }
        guard let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first(where: \.isTracked) else {
            clearFace()
            if status != .lookingForFace { status = .lookingForFace }
            return
        }
        let coefficients = Dictionary(uniqueKeysWithValues: face.blendShapes.map {
            ($0.key.rawValue, $0.value.floatValue)
        })
        guard let features = MouthFeatureSchema.features(from: coefficients) else {
            clearFace()
            status = .lookingForFace
            return
        }
        guard sampler.shouldEmit(at: frame.timestamp) else { return }
        // ARFrame.timestamp is monotonic uptime, in seconds, not wall-clock time.
        let sample = MouthFrame(timestamp: frame.timestamp, features: features)
        currentFeatures = features
        if !isFaceDetected { isFaceDetected = true }
        if status != .tracking { status = .tracking }
        latestFrame = sample
        updateFrameRate(at: frame.timestamp)
        frameSubject.send(sample)
    }

    private func updateFrameRate(at timestamp: TimeInterval) {
        guard let start = rateWindowStart else {
            rateWindowStart = timestamp
            return
        }
        rateWindowCount += 1
        let duration = timestamp - start
        if duration >= 1 {
            framesPerSecond = Double(rateWindowCount) / duration
            rateWindowStart = timestamp
            rateWindowCount = 0
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        guard wantsToRun else { return }
        clearFace()
        status = .interrupted
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        guard wantsToRun else { return }
        runSession()
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard wantsToRun else { return }
        stop()
        status = .failed(error.localizedDescription)
    }
}
