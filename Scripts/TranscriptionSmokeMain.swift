import Foundation

@MainActor
private final class FakeTranscriber: Transcribing {
    var pending: [CheckedContinuation<TranscriptionResult, Error>] = []
    func health(host: String, port: Int) async throws -> TranscriptionHealth {
        TranscriptionHealth(ready: true, modelVersion: "test", device: "cpu", error: nil)
    }
    func transcribe(_ take: CapturedTake, host: String, port: Int,
                    uploaded: @escaping @Sendable () -> Void) async throws -> TranscriptionResult {
        uploaded()
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
}

@MainActor
private final class FakeSpeaker: SpeechSpeaking {
    var spoken: [String] = []
    func speak(_ text: String) { spoken.append(text) }
    func stop() {}
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct TranscriptionSmokeMain {
    @MainActor
    static func until(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("Timed out waiting for state transition")
    }

    @MainActor
    static func main() async throws {
        let service = FakeTranscriber()
        let state = SentenceRecognition(service: service)
        let speaker = FakeSpeaker()
        let take = CapturedTake(sample: MouthSample(label: "UNLABELED", frames: []),
                                archiveURL: FileManager.default.temporaryDirectory)
        func result(_ text: String) -> TranscriptionResult {
            TranscriptionResult(sampleID: take.sample.id, transcript: text, modelVersion: "test", processingSeconds: 0.1)
        }

        state.transcribe(take, host: "mac.local", port: 8000)
        try await until { service.pending.count == 1 && state.phase == .transcribing }
        service.pending.removeFirst().resume(returning: result("original sentence"))
        try await until { state.result != nil }
        state.text = "  My edited sentence, exactly!  "
        state.speak(using: speaker)
        precondition(speaker.spoken == ["  My edited sentence, exactly!  "])
        precondition(state.result?.transcript == "original sentence")
        state.text = " \n "
        state.speak(using: speaker)
        precondition(speaker.spoken.count == 1)

        // The cancelled request deliberately ignores cancellation and completes late.
        state.transcribe(take, host: "mac.local", port: 8000)
        try await until { service.pending.count == 1 }
        let stale = service.pending.removeFirst()
        state.cancel()
        state.transcribe(take, host: "mac.local", port: 8000)
        try await until { service.pending.count == 1 }
        stale.resume(returning: result("stale"))
        service.pending.removeFirst().resume(returning: result("current"))
        try await until { !state.isBusy }
        precondition(state.text == "current")

        state.transcribe(take, host: "mac.local", port: 8000)
        try await until { service.pending.count == 1 }
        service.pending.removeFirst().resume(throwing: URLError(.notConnectedToInternet))
        try await until { state.error != nil }
        precondition(state.lastTake?.sample.id == take.sample.id && !state.isBusy)
        state.prepareRecording()
        precondition(state.lastTake == nil && state.result == nil && state.error == nil)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = LocalTranscriptionService(session: URLSession(configuration: configuration))
        StubURLProtocol.body = Data("{\"ready\":true,\"modelVersion\":\"test\",\"device\":\"cpu\",\"error\":null}".utf8)
        let health = try await client.health(host: "test.local", port: 8000)
        precondition(health.ready)
        StubURLProtocol.status = 503
        StubURLProtocol.body = Data("{\"code\":\"busy\",\"message\":\"Mac busy\"}".utf8)
        do {
            _ = try await client.health(host: "test.local", port: 8000)
            preconditionFailure("Expected server error")
        } catch { precondition(error.localizedDescription == "Mac busy") }
        for host in ["example.com", "http://mac.local", "mac.local/path", "..local"] {
            do {
                _ = try LocalTranscriptionService.baseURL(host: host, port: 8000)
                preconditionFailure("Expected invalid hostname")
            } catch {}
        }

        // Exercise archive packaging and response correlation through URLSession.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var metadata = CaptureManifest(
            schemaVersion: 2, sampleID: take.sample.id, label: "UNLABELED", speakerID: "test",
            sessionID: UUID(), deviceModel: "test", operatingSystem: "test", createdAt: Date(),
            featureSchemaVersion: 1, featureNames: [], frameCount: 15, depthFrameCount: 0,
            startedAt: 100, endedAt: 100 + 14.0 / 30, measuredFrameRate: 30, valid: true,
            issues: [], datasetSplit: "unassigned", rgbFormat: "PNG", depthFormat: "",
            coordinateConvention: "", mouthSelection: "")
        metadata.faceFrameCount = 15
        let encoder = JSONEncoder()
        try CaptureArchive.write([CaptureFile(name: "metadata.json", data: encoder.encode(metadata))], to: directory)
        for index in 0..<15 {
            var frame = CaptureFrameMetadata(
                index: index, timestamp: 100 + Double(index) / 30, depthTimestamp: nil, blendShapes: [:],
                vertices: [], mouthVertexIndices: [], cameraTransform: [], faceTransform: [],
                cameraIntrinsics: [], cameraToFaceDistance: 0.5, rgbSourceWidth: 640, rgbSourceHeight: 480,
                rgbCrop: [0, 0, 192, 192], rgbWidth: 192, rgbHeight: 192, depthWidth: nil,
                depthHeight: nil, depthCalibration: nil, depthFiltered: nil, depthAccuracy: nil,
                depthQuality: nil, deviceOrientation: 1)
            frame.faceWidth = 256
            frame.faceHeight = 256
            try CaptureArchive.write([
                CaptureFile(name: "frame.json", data: encoder.encode(frame)),
                CaptureFile(name: "face.png", data: Data("fixture: decoding is tested by the server suite".utf8))
            ], to: directory.appendingPathComponent(String(format: "%06d", index)))
        }
        let archivedTake = CapturedTake(sample: take.sample, archiveURL: directory)
        StubURLProtocol.status = 200
        StubURLProtocol.body = try encoder.encode(result("full HTTP response"))
        let response = try await client.transcribe(archivedTake, host: "mac.local", port: 8000, uploaded: {})
        precondition(response.transcript == "full HTTP response")
        StubURLProtocol.body = try encoder.encode(TranscriptionResult(sampleID: UUID(), transcript: "wrong take",
                                                                      modelVersion: "test", processingSeconds: 1))
        do {
            _ = try await client.transcribe(archivedTake, host: "mac.local", port: 8000, uploaded: {})
            preconditionFailure("Expected mismatched sample ID to be rejected")
        } catch { precondition(error.localizedDescription.contains("invalid transcript")) }
        metadata.faceFrameCount = 0
        try CaptureArchive.write([CaptureFile(name: "metadata.json", data: encoder.encode(metadata))], to: directory)
        do {
            _ = try await client.transcribe(archivedTake, host: "mac.local", port: 8000, uploaded: {})
            preconditionFailure("Expected incomplete face archive to be rejected")
        } catch { precondition(error.localizedDescription.contains("record it again")) }
        print("PASS: transcript edits, exact speech, stale-response protection, offline retry, HTTP errors, archive uploads, response correlation, and local hostnames")
    }
}
