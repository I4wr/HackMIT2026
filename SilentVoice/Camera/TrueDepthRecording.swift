import ARKit
import AVFoundation
import CoreImage
import UIKit

/// Only active during an explicit take. Never retain ARFrames or camera buffers.
@MainActor
final class TrueDepthRecording {
    enum RecordingError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let reason): return reason }
        }
    }

    let id = UUID()
    let label: String
    private let sessionID: UUID
    private let datasetSplit: String
    private let createdAt = Date()
    private let context = CIContext()
    private let directory: URL
    private var frames: [MouthFrame] = []
    private var depthFrameCount = 0
    private var issues: [String] = []
    private var writes: [Task<Void, Error>] = []
    private var pendingWrites = 0
    private var mouthIndices: [Int]?

    init(label: String, sessionID: UUID, datasetSplit: String) throws {
        self.label = label
        self.sessionID = sessionID
        self.datasetSplit = datasetSplit
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("captures", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func invalidate(_ reason: String) {
        if !issues.contains(reason) { issues.append(reason) }
    }

    func append(frame: ARFrame, face: ARFaceAnchor, features: MouthFrame) {
        // Bound memory and disk pressure. A dropped archive frame invalidates the take.
        guard pendingWrites < 4, frames.count < 300 else {
            invalidate("Recording could not keep up with the camera. Please try again.")
            return
        }
        do {
            let index = frames.count
            let width = CVPixelBufferGetWidth(frame.capturedImage)
            let height = CVPixelBufferGetHeight(frame.capturedImage)
            let vertices = face.geometry.vertices
            // Conservative lower-central-face region, fixed for the duration of a take.
            // Keep the entire mesh so this provisional selection can be refined offline.
            if mouthIndices == nil {
                mouthIndices = vertices.indices.filter {
                    abs(vertices[$0].x) < 0.055 && vertices[$0].y < -0.005 && vertices[$0].y > -0.080
                }
            }
            let indices = mouthIndices ?? []
            let cameraFromFace = simd_inverse(frame.camera.transform) * face.transform
            let points = indices.compactMap { index -> CGPoint? in
                guard index < vertices.count else { return nil }
                let v = vertices[index]
                let p = cameraFromFace * SIMD4<Float>(v.x, v.y, v.z, 1)
                guard p.z < -0.01 else { return nil }
                // AR camera: +X right, +Y up, looking along -Z. Native image: +Y down.
                let pixel = frame.camera.intrinsics * SIMD3<Float>(p.x / -p.z, -p.y / -p.z, 1)
                guard pixel.x.isFinite, pixel.y.isFinite else { return nil }
                return CGPoint(x: CGFloat(pixel.x), y: CGFloat(pixel.y))
            }
            guard points.count >= 4 else { throw RecordingError.invalid("Could not locate the mouth in the camera image.") }
            let xs = points.map(\.x), ys = points.map(\.y)
            let bounds = CGRect(x: xs.min()!, y: ys.min()!,
                                width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            let crop = bounds.insetBy(dx: -bounds.width * 0.25, dy: -bounds.height * 0.25).integral
            guard crop.width >= 16, crop.height >= 16,
                  CGRect(x: 0, y: 0, width: width, height: height).contains(crop) else {
                throw RecordingError.invalid("Keep your whole mouth in view and face the camera.")
            }
            // Core Image has a bottom-left origin. Export native orientation, never mirrored.
            let ciCrop = CGRect(x: crop.minX, y: CGFloat(height) - crop.maxY, width: crop.width, height: crop.height)
            let image = CIImage(cvPixelBuffer: frame.capturedImage).cropped(to: ciCrop)
                .transformed(by: CGAffineTransform(translationX: -ciCrop.minX, y: -ciCrop.minY))
                .transformed(by: CGAffineTransform(scaleX: 192 / crop.width, y: 192 / crop.height))
            guard let rgb = context.pngRepresentation(of: image, format: .RGBA8,
                                                     colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else {
                throw RecordingError.invalid("Could not encode the mouth image.")
            }
            var files = [CaptureFile(name: "rgb.png", data: rgb)]
            var depthWidth: Int?, depthHeight: Int?, depthTimestamp: TimeInterval?
            var calibration: DepthCalibrationMetadata?
            var filtered: Bool?, accuracy: Int?, quality: Int?
            // Missing depth never suppresses RGB, mesh or blendshapes.
            if let captured = frame.capturedDepthData,
               frame.capturedDepthDataTimestamp.isFinite, frame.capturedDepthDataTimestamp > 0 {
                let depth = captured.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
                let buffer = depth.depthDataMap
                let packed = try copyDepth(buffer)
                depthWidth = CVPixelBufferGetWidth(buffer)
                depthHeight = CVPixelBufferGetHeight(buffer)
                depthTimestamp = frame.capturedDepthDataTimestamp
                filtered = depth.isDepthDataFiltered
                accuracy = depth.depthDataAccuracy.rawValue
                quality = depth.depthDataQuality.rawValue
                files.append(CaptureFile(name: "depth.f32", data: packed.values))
                files.append(CaptureFile(name: "depth-mask.u8", data: packed.mask))
                if let c = depth.cameraCalibrationData {
                    calibration = DepthCalibrationMetadata(
                        intrinsics: flatten(c.intrinsicMatrix),
                        referenceWidth: c.intrinsicMatrixReferenceDimensions.width,
                        referenceHeight: c.intrinsicMatrixReferenceDimensions.height,
                        extrinsics: (0..<4).flatMap { column in (0..<3).map { c.extrinsicMatrix[column][$0] } },
                        pixelSize: c.pixelSize,
                        distortionCenter: [c.lensDistortionCenter.x, c.lensDistortionCenter.y],
                        lensDistortionLookupTable: c.lensDistortionLookupTable,
                        inverseLensDistortionLookupTable: c.inverseLensDistortionLookupTable)
                }
            }
            let metadata = CaptureFrameMetadata(
                index: index, timestamp: frame.timestamp, depthTimestamp: depthTimestamp,
                blendShapes: Dictionary(uniqueKeysWithValues: face.blendShapes.map { ($0.key.rawValue, $0.value.floatValue) }),
                vertices: vertices.map { [$0.x, $0.y, $0.z] }, mouthVertexIndices: indices,
                cameraTransform: flatten(frame.camera.transform), faceTransform: flatten(face.transform),
                cameraIntrinsics: flatten(frame.camera.intrinsics),
                cameraToFaceDistance: simd_length(SIMD3<Float>(cameraFromFace.columns.3.x, cameraFromFace.columns.3.y, cameraFromFace.columns.3.z)),
                rgbSourceWidth: width, rgbSourceHeight: height,
                rgbCrop: [crop.minX, crop.minY, crop.width, crop.height], rgbWidth: 192, rgbHeight: 192,
                depthWidth: depthWidth, depthHeight: depthHeight, depthCalibration: calibration,
                depthFiltered: filtered, depthAccuracy: accuracy, depthQuality: quality,
                deviceOrientation: UIDevice.current.orientation.rawValue)
            files.append(CaptureFile(name: "frame.json", data: try JSONEncoder().encode(metadata)))
            let target = directory.appendingPathComponent(String(format: "%06d", index), isDirectory: true)
            let packet = files
            pendingWrites += 1
            writes.append(Task {
                defer { pendingWrites -= 1 }
                try await Task.detached(priority: .utility) {
                    try CaptureArchive.write(packet, to: target)
                }.value
            })
            frames.append(features)
            if depthTimestamp != nil { depthFrameCount += 1 }
        } catch {
            invalidate(error.localizedDescription)
        }
    }

    func finish() async throws -> MouthSample {
        for write in writes {
            do { try await write.value } catch { invalidate("Could not save recording: \(error.localizedDescription)") }
        }
        if frames.count < 15 { invalidate("Too few camera frames. Keep your face visible and try again.") }
        if zip(frames, frames.dropFirst()).contains(where: { $1.timestamp - $0.timestamp > 0.2 }) {
            invalidate("The camera stream had a gap. Please record again.")
        }
        let duration = (frames.last?.timestamp ?? 0) - (frames.first?.timestamp ?? 0)
        let sample = MouthSample(id: id, label: label, frames: frames, captureSource: "TrueDepth")
        let manifest = CaptureManifest(
            schemaVersion: 1, sampleID: id, label: label, speakerID: Self.speakerID,
            sessionID: sessionID, deviceModel: Self.deviceModel, operatingSystem: UIDevice.current.systemVersion,
            createdAt: createdAt, featureSchemaVersion: MouthFeatureSchema.version, featureNames: MouthFeatureSchema.names,
            frameCount: frames.count, depthFrameCount: depthFrameCount,
            startedAt: frames.first?.timestamp, endedAt: frames.last?.timestamp,
            measuredFrameRate: duration > 0 ? Double(frames.count - 1) / duration : nil,
            valid: issues.isEmpty, issues: issues, datasetSplit: datasetSplit,
            rgbFormat: "PNG RGBA8 sRGB, 192x192, native camera orientation, unmirrored",
            depthFormat: "Native resolution, unrectified Float32 little-endian metres; UInt8 mask 1=valid, 0=missing; zero placeholders require mask",
            coordinateConvention: "Matrices column-major; vertices face-local metres; RGB crop top-left native pixels; depth calibration reference dimensions preserved",
            mouthSelection: "v1: fixed first-frame lower-face vertices abs(x)<0.055, -0.080<y<-0.005 metres; projected bounds +25% each side; verify on device")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let files = [CaptureFile(name: "metadata.json", data: try encoder.encode(manifest)),
                     CaptureFile(name: "sample.json", data: try encoder.encode(sample))]
        let target = directory
        try await Task.detached(priority: .utility) { try CaptureArchive.write(files, to: target) }.value
        guard issues.isEmpty else { throw RecordingError.invalid(issues.joined(separator: " ")) }
        return sample
    }

    private func copyDepth(_ buffer: CVPixelBuffer) throws -> (values: Data, mask: Data) {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
            throw RecordingError.invalid("Could not read the depth buffer.")
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let address = CVPixelBufferGetBaseAddress(buffer) else {
            throw RecordingError.invalid("Depth buffer has no pixels.")
        }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var values = [Float]()
        values.reserveCapacity(width * height)
        for y in 0..<height {
            let row = address.advanced(by: y * stride).assumingMemoryBound(to: Float.self)
            values.append(contentsOf: UnsafeBufferPointer(start: row, count: width))
        }
        return CaptureArchive.packDepth(values)
    }

    private func flatten(_ matrix: simd_float4x4) -> [Float] {
        (0..<4).flatMap { column in (0..<4).map { matrix[column][$0] } }
    }
    private func flatten(_ matrix: simd_float3x3) -> [Float] {
        (0..<3).flatMap { column in (0..<3).map { matrix[column][$0] } }
    }
    private static var speakerID: String {
        let key = "SilentVoice.captureSpeakerID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}
