import ARKit
import AVFoundation
import Foundation

/// A small live snapshot, independent of recording and classifier inputs.
struct FaceDiagnostics {
    var blendShapes: [String: Float] = [:]
    var rgbWidth = 0
    var rgbHeight = 0
    var exposureMilliseconds: Double = 0
    var faceDistanceCentimeters: Float = 0
    var vertexCount = 0
    var pitchDegrees: Float = 0
    var yawDegrees: Float = 0
    var rollDegrees: Float = 0
    var depth: DepthSnapshot?
    var depthOffsetMilliseconds: Double?
    var depthFramesPerSecond: Double?

    struct DepthSnapshot {
        let timestamp: TimeInterval
        let width: Int
        let height: Int
        let validFraction: Double
        let medianMeters: Float?
    }

    var hasRecentDepth: Bool {
        guard let depthOffsetMilliseconds else { return false }
        return abs(depthOffsetMilliseconds) <= 500
    }
}

/// Inspect at most ~3,000 depth pixels at 5 Hz; retain values, never AR buffers.
@MainActor
struct FaceDiagnosticsSampler {
    private var lastPublishedAt: TimeInterval?
    private var lastDepthReadAt: TimeInterval?
    private var lastDepthTimestamp: TimeInterval?
    private var depth: FaceDiagnostics.DepthSnapshot?
    private var depthRateWindow: TimeInterval?
    private var depthCount = 0
    private var depthRate: Double?
    private var referenceRotation: simd_quatf?

    mutating func update(frame: ARFrame, face: ARFaceAnchor,
                         blendShapes: [String: Float]) -> FaceDiagnostics? {
        if depthRateWindow == nil { depthRateWindow = frame.timestamp }
        if let capturedDepth = frame.capturedDepthData,
           frame.capturedDepthDataTimestamp.isFinite, frame.capturedDepthDataTimestamp > 0,
           frame.capturedDepthDataTimestamp != lastDepthTimestamp {
            lastDepthTimestamp = frame.capturedDepthDataTimestamp
            depthCount += 1
            if lastDepthReadAt == nil || frame.timestamp - lastDepthReadAt! >= 0.2 {
                depth = Self.inspectDepth(capturedDepth, timestamp: frame.capturedDepthDataTimestamp)
                lastDepthReadAt = frame.timestamp
            }
        }
        if let start = depthRateWindow, frame.timestamp - start >= 1 {
            depthRate = Double(depthCount) / (frame.timestamp - start)
            depthRateWindow = frame.timestamp
            depthCount = 0
        }
        if let lastPublishedAt, frame.timestamp - lastPublishedAt < 0.2 { return nil }
        lastPublishedAt = frame.timestamp

        let cameraFromFace = simd_inverse(frame.camera.transform) * face.transform
        let rotation = simd_quatf(cameraFromFace)
        if referenceRotation == nil { referenceRotation = rotation }
        let relative = simd_float3x3(referenceRotation!.inverse * rotation)
        let degrees: Float = 180 / .pi
        var snapshot = FaceDiagnostics()
        snapshot.blendShapes = blendShapes.filter { $0.value.isFinite }
        snapshot.rgbWidth = CVPixelBufferGetWidth(frame.capturedImage)
        snapshot.rgbHeight = CVPixelBufferGetHeight(frame.capturedImage)
        snapshot.exposureMilliseconds = frame.camera.exposureDuration * 1000
        let translation = cameraFromFace.columns.3
        snapshot.faceDistanceCentimeters = simd_length(SIMD3(translation.x, translation.y, translation.z)) * 100
        snapshot.vertexCount = face.geometry.vertices.count
        snapshot.pitchDegrees = atan2(relative[1].z, relative[2].z) * degrees
        snapshot.yawDegrees = asin(min(1, max(-1, -relative[0].z))) * degrees
        snapshot.rollDegrees = atan2(relative[0].y, relative[0].x) * degrees
        snapshot.depth = depth
        snapshot.depthOffsetMilliseconds = depth.map { (frame.timestamp - $0.timestamp) * 1000 }
        snapshot.depthFramesPerSecond = depthRate
        return snapshot
    }

    private static func inspectDepth(_ captured: AVDepthData, timestamp: TimeInterval) -> FaceDiagnostics.DepthSnapshot? {
        let buffer = captured.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32).depthDataMap
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var valid: [Float] = []
        var sampled = 0
        for y in stride(from: 0, to: height, by: max(1, (height + 47) / 48)) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in stride(from: 0, to: width, by: max(1, (width + 63) / 64)) {
                sampled += 1
                let value = row[x]
                if value.isFinite && value > 0 { valid.append(value) }
            }
        }
        valid.sort()
        return FaceDiagnostics.DepthSnapshot(
            timestamp: timestamp, width: width, height: height,
            validFraction: sampled > 0 ? Double(valid.count) / Double(sampled) : 0,
            medianMeters: valid.isEmpty ? nil : valid[valid.count / 2])
    }
}
