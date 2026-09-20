import Foundation

struct TranscriptionResult: Codable, Equatable, Sendable {
    let sampleID: UUID
    let transcript: String
    let modelVersion: String
    let processingSeconds: Double
}

struct TranscriptionHealth: Decodable, Sendable {
    let ready: Bool
    let modelVersion: String
    let device: String
    let error: String?
}

enum TranscriptionError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

@MainActor
protocol Transcribing {
    func health(host: String, port: Int) async throws -> TranscriptionHealth
    func transcribe(_ take: CapturedTake, host: String, port: Int,
                    uploaded: @escaping @Sendable () -> Void) async throws -> TranscriptionResult
}

/// No images or depth are sent except the finalized take's face PNGs.
@MainActor
final class LocalTranscriptionService: Transcribing {
    private let session: URLSession
    private let healthSession: URLSession

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        self.session = session ?? URLSession(configuration: configuration)
        let healthConfiguration = URLSessionConfiguration.ephemeral
        healthConfiguration.timeoutIntervalForRequest = 3
        healthConfiguration.timeoutIntervalForResource = 3
        healthConfiguration.waitsForConnectivity = true
        self.healthSession = session ?? URLSession(configuration: healthConfiguration)
    }

    static func baseURL(host: String, port: Int) throws -> URL {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard (host.hasSuffix(".local") || host == "localhost"),
              !host.hasPrefix("."), !host.contains(".."),
              host.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              (1...65535).contains(port), let url = URL(string: "http://\(host):\(port)") else {
            throw TranscriptionError.message("Enter your Mac’s local hostname (for example, macbook.local) and a port from 1 to 65535.")
        }
        return url
    }

    func health(host: String, port: Int) async throws -> TranscriptionHealth {
        var request = URLRequest(url: try Self.baseURL(host: host, port: port).appendingPathComponent("health"))
        request.timeoutInterval = 3
        let (data, response) = try await healthSession.data(for: request)
        try Self.check(response, data: data)
        return try JSONDecoder().decode(TranscriptionHealth.self, from: data)
    }

    func transcribe(_ take: CapturedTake, host: String, port: Int,
                    uploaded: @escaping @Sendable () -> Void) async throws -> TranscriptionResult {
        let url = try Self.baseURL(host: host, port: port).appendingPathComponent("v1/transcribe")
        let boundary = "SilentVoice-\(UUID().uuidString)"
        let archiveURL = take.archiveURL
        let sampleID = take.sample.id
        let packaging = Task.detached(priority: .utility) {
            try Self.package(archiveURL: archiveURL, sampleID: sampleID, boundary: boundary)
        }
        let body = try await withTaskCancellationHandler {
            try await packaging.value
        } onCancel: {
            packaging.cancel()
        }
        defer { try? FileManager.default.removeItem(at: body) }
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        let delegate = UploadObserver(uploaded: uploaded)
        let (data, response) = try await session.upload(for: request, fromFile: body, delegate: delegate)
        try Task.checkCancellation()
        try Self.check(response, data: data)
        let result = try JSONDecoder().decode(TranscriptionResult.self, from: data)
        guard result.sampleID == sampleID, !result.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              result.processingSeconds.isFinite, result.processingSeconds >= 0 else {
            throw TranscriptionError.message("The Mac returned an invalid transcript. Please retry.")
        }
        return result
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.message("The Mac returned an invalid response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            struct ServerError: Decodable { let message: String }
            let message = (try? JSONDecoder().decode(ServerError.self, from: data).message)
                ?? "The Mac could not transcribe this recording (HTTP \(http.statusCode))."
            throw TranscriptionError.message(message)
        }
    }

    nonisolated private static func package(archiveURL: URL, sampleID: UUID, boundary: String) throws -> URL {
        let manifest = try JSONDecoder().decode(CaptureManifest.self,
            from: Data(contentsOf: archiveURL.appendingPathComponent("metadata.json")))
        guard manifest.schemaVersion == 2, manifest.valid, manifest.sampleID == sampleID,
              (15...300).contains(manifest.frameCount), manifest.faceFrameCount == manifest.frameCount else {
            throw TranscriptionError.message("This recording has no complete face images. Please record it again.")
        }
        var timestamps: [Double] = []
        for index in 0..<manifest.frameCount {
            try Task.checkCancellation()
            let folder = archiveURL.appendingPathComponent(String(format: "%06d", index))
            let frame = try JSONDecoder().decode(CaptureFrameMetadata.self,
                from: Data(contentsOf: folder.appendingPathComponent("frame.json")))
            guard frame.index == index, frame.timestamp.isFinite, frame.faceWidth == 256, frame.faceHeight == 256 else {
                throw TranscriptionError.message("The face recording is incomplete. Please record it again.")
            }
            timestamps.append(frame.timestamp)
        }
        let wire: [String: Any] = ["sampleID": sampleID.uuidString, "schemaVersion": 2,
                                  "frameCount": manifest.frameCount, "timestamps": timestamps]
        let metadata = try JSONSerialization.data(withJSONObject: wire)
        let body = FileManager.default.temporaryDirectory.appendingPathComponent("transcription-\(UUID().uuidString).multipart")
        FileManager.default.createFile(atPath: body.path, contents: nil)
        let handle = try FileHandle(forWritingTo: body)
        defer { try? handle.close() }
        var bytes = 0
        func write(_ data: Data) throws {
            bytes += data.count
            guard bytes <= 100 * 1024 * 1024 else {
                throw TranscriptionError.message("Recording upload exceeds 100 MB. Record a shorter sentence.")
            }
            try handle.write(contentsOf: data)
        }
        do {
            try write(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"manifest\"\r\nContent-Type: application/json\r\n\r\n".utf8))
            try write(metadata)
            for index in 0..<manifest.frameCount {
                try Task.checkCancellation()
                let name = String(format: "%06d", index)
                try write(Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"frames\"; filename=\"\(name).png\"\r\nContent-Type: image/png\r\n\r\n".utf8))
                try write(Data(contentsOf: archiveURL.appendingPathComponent(name).appendingPathComponent("face.png")))
            }
            try write(Data("\r\n--\(boundary)--\r\n".utf8))
            return body
        } catch {
            try? FileManager.default.removeItem(at: body)
            throw error
        }
    }
}

private final class UploadObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let uploaded: @Sendable () -> Void
    init(uploaded: @escaping @Sendable () -> Void) { self.uploaded = uploaded }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesExpectedToSend > 0 && totalBytesSent >= totalBytesExpectedToSend { uploaded() }
    }
}
