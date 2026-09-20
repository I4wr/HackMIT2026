import Foundation

/// The research archive is separate from the small, backwards-compatible classifier JSON.
nonisolated struct CaptureFrameMetadata: Codable, Sendable {
    let index: Int
    let timestamp: TimeInterval
    let depthTimestamp: TimeInterval?
    let blendShapes: [String: Float]
    let vertices: [[Float]]
    let mouthVertexIndices: [Int]
    let cameraTransform: [Float]
    let faceTransform: [Float]
    let cameraIntrinsics: [Float]
    let cameraToFaceDistance: Float
    let rgbSourceWidth: Int
    let rgbSourceHeight: Int
    /// x, y, width, height in native RGB pixels, top-left origin; no preview mirroring.
    let rgbCrop: [Double]
    let rgbWidth: Int
    let rgbHeight: Int
    let depthWidth: Int?
    let depthHeight: Int?
    let depthCalibration: DepthCalibrationMetadata?
    let depthFiltered: Bool?
    let depthAccuracy: Int?
    let depthQuality: Int?
    let deviceOrientation: Int
    /// Optional so schema-v1 archives remain decodable. Crop is in native pixels.
    var faceCrop: [Double]? = nil
    var faceWidth: Int? = nil
    var faceHeight: Int? = nil
    var faceOrientation: Int? = nil // EXIF rotation applied to face.png; never mirrored.
}

nonisolated struct DepthCalibrationMetadata: Codable, Sendable {
    let intrinsics: [Float]
    let referenceWidth: Double
    let referenceHeight: Double
    let extrinsics: [Float]
    let pixelSize: Float
    let distortionCenter: [Double]
    // JSON encodes Data as base64; Apple's lookup tables contain native Float32 values.
    let lensDistortionLookupTable: Data?
    let inverseLensDistortionLookupTable: Data?
}

nonisolated struct CaptureManifest: Codable, Sendable {
    let schemaVersion: Int
    let sampleID: UUID
    let label: String
    let speakerID: String
    let sessionID: UUID
    let deviceModel: String
    let operatingSystem: String
    let createdAt: Date
    let featureSchemaVersion: Int
    let featureNames: [String]
    let frameCount: Int
    let depthFrameCount: Int
    let startedAt: TimeInterval?
    let endedAt: TimeInterval?
    let measuredFrameRate: Double?
    let valid: Bool
    let issues: [String]
    let datasetSplit: String
    let rgbFormat: String
    let depthFormat: String
    let coordinateConvention: String
    let mouthSelection: String
    var faceFrameCount: Int? = nil
    var faceFormat: String? = nil
}

struct CapturedTake: Sendable {
    let sample: MouthSample
    let archiveURL: URL
}

struct CaptureFile: Sendable {
    let name: String
    let data: Data
}

enum CaptureArchive {
    nonisolated static func write(_ files: [CaptureFile], to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files {
            try file.data.write(to: directory.appendingPathComponent(file.name), options: .atomic)
        }
    }

    /// Packed little-endian Float32 metres plus one validity byte per pixel.
    /// Invalid entries use a zero placeholder whose mask MUST be consulted.
    nonisolated static func packDepth(_ values: [Float]) -> (values: Data, mask: Data) {
        var pixels = [UInt32]()
        var mask = [UInt8]()
        pixels.reserveCapacity(values.count)
        mask.reserveCapacity(values.count)
        for value in values {
            let valid = value.isFinite && value > 0
            pixels.append((valid ? value : Float(0)).bitPattern.littleEndian)
            mask.append(valid ? 1 : 0)
        }
        return (pixels.withUnsafeBytes { Data($0) }, Data(mask))
    }
}
