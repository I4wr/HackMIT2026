import Foundation

@main
struct CaptureSmokeMain {
    static func main() throws {
        // Exact little-endian bytes, including invalid/nonpositive depths.
        let depth = CaptureArchive.packDepth([1, 0.5, .nan, .infinity, -.infinity, -1, 0])
        precondition(depth.values == Data([0, 0, 128, 63, 0, 0, 0, 63] + Array(repeating: 0, count: 20)))
        precondition(depth.mask == Data([1, 1, 0, 0, 0, 0, 0]))

        let legacy = Data("""
        {"id":"00000000-0000-0000-0000-000000000001","label":"help","frames":[{"timestamp":10,"features":[0.2]}]}
        """.utf8)
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        let old = try decoder.decode(MouthSample.self, from: legacy)
        precondition(old.captureSource == nil)
        let live = MouthSample(label: "help", frames: old.frames, captureSource: "TrueDepth")
        let roundTrip = try decoder.decode(MouthSample.self, from: encoder.encode(live))
        precondition(roundTrip == live)

        // A frame with missing depth still carries RGB, geometry and classifier features.
        let frame = CaptureFrameMetadata(
            index: 0, timestamp: 10, depthTimestamp: nil, blendShapes: ["jawOpen": 0.2],
            vertices: [[0, -0.03, 0.02]], mouthVertexIndices: [0], cameraTransform: [],
            faceTransform: [], cameraIntrinsics: [], cameraToFaceDistance: 0.4,
            rgbSourceWidth: 640, rgbSourceHeight: 480, rgbCrop: [200, 200, 100, 100],
            rgbWidth: 192, rgbHeight: 192, depthWidth: nil, depthHeight: nil,
            depthCalibration: nil, depthFiltered: nil, depthAccuracy: nil, depthQuality: nil,
            deviceOrientation: 1)
        let decoded = try decoder.decode(CaptureFrameMetadata.self, from: encoder.encode(frame))
        precondition(decoded.depthTimestamp == nil && decoded.rgbWidth == 192)
        precondition(decoded.blendShapes["jawOpen"] == 0.2 && decoded.vertices.count == 1)
        precondition(decoded.faceCrop == nil && decoded.faceOrientation == nil)
        var faceFrame = frame
        faceFrame.faceCrop = [100, 50, 300, 300]
        faceFrame.faceWidth = 256
        faceFrame.faceHeight = 256
        faceFrame.faceOrientation = 6
        let faceRoundTrip = try decoder.decode(CaptureFrameMetadata.self, from: encoder.encode(faceFrame))
        precondition(faceRoundTrip.faceWidth == 256 && faceRoundTrip.faceOrientation == 6)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try CaptureArchive.write([
            CaptureFile(name: "depth.f32", data: depth.values),
            CaptureFile(name: "depth-mask.u8", data: depth.mask),
            CaptureFile(name: "frame.json", data: encoder.encode(frame))
        ], to: directory)
        let savedDepth = try Data(contentsOf: directory.appendingPathComponent("depth.f32"))
        let savedMask = try Data(contentsOf: directory.appendingPathComponent("depth-mask.u8"))
        precondition(savedDepth == depth.values && savedMask == depth.mask)
        for rate in [30, 60, 120] {
            var sampler = MouthFrameSampler()
            let emitted = (0..<(rate * 3)).filter { sampler.shouldEmit(at: 10 + Double($0) / Double(rate)) }
            precondition(emitted.count == 90)
        }
        let schema = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "sample-data/feature_schema.json"))) as! [String: Any]
        precondition(schema["version"] as? Int == MouthFeatureSchema.version)
        precondition(schema["names"] as? [String] == MouthFeatureSchema.names)
        print("PASS: depth binary/mask, legacy/live samples, optional depth metadata, archive writes, 30 Hz sampling and feature schema")
    }
}
