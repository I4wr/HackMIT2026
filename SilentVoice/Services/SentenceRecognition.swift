import Foundation
import Combine

@MainActor
final class SentenceRecognition: ObservableObject {
    enum Phase: String { case idle, uploading = "Uploading…", transcribing = "Transcribing…" }
    @Published private(set) var phase: Phase = .idle
    @Published var text = ""
    @Published private(set) var result: TranscriptionResult?
    @Published private(set) var lastTake: CapturedTake?
    @Published private(set) var error: String?
    @Published private(set) var connectionMessage: String?
    @Published private(set) var checkingConnection = false
    private let service: any Transcribing
    private var requestID = UUID()
    private var task: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?
    private var healthID = UUID()

    init(service: (any Transcribing)? = nil) { self.service = service ?? LocalTranscriptionService() }
    var isBusy: Bool { phase != .idle }

    func speak(using output: any SpeechSpeaking) {
        guard !isBusy, result != nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        output.speak(text)
    }

    func prepareRecording() {
        cancel()
        text = ""
        result = nil
        lastTake = nil
        error = nil
    }

    func transcribe(_ take: CapturedTake, host: String, port: Int) {
        cancel()
        lastTake = take
        error = nil
        text = ""
        result = nil
        phase = .uploading
        let id = requestID
        task = Task { [self] in
            do {
                let output = try await service.transcribe(take, host: host, port: port) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, self.requestID == id, self.phase == .uploading else { return }
                        self.phase = .transcribing
                    }
                }
                guard !Task.isCancelled, requestID == id else { return }
                result = output
                text = output.transcript
                phase = .idle
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                self.error = "\(error.localizedDescription) Retry this recording or switch to Commands for offline use."
                phase = .idle
            }
        }
    }

    func testConnection(host: String, port: Int) {
        healthTask?.cancel()
        healthID = UUID()
        let id = healthID
        checkingConnection = true
        connectionMessage = nil
        healthTask = Task {
            do {
                let health = try await service.health(host: host, port: port)
                guard !Task.isCancelled, healthID == id else { return }
                connectionMessage = health.ready ? "Mac ready · \(health.device)"
                    : "Mac connected, model unavailable: \(health.error ?? "still loading")"
            } catch {
                guard !Task.isCancelled, healthID == id else { return }
                connectionMessage = "Could not connect: \(error.localizedDescription) Check the hostname, server, and Local Network permission in Settings."
            }
            checkingConnection = false
        }
    }

    func cancel() {
        requestID = UUID()
        task?.cancel()
        task = nil
        phase = .idle
        healthID = UUID()
        healthTask?.cancel()
        checkingConnection = false
    }
}
