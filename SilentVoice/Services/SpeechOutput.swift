import AVFoundation
import Foundation

@MainActor
protocol SpeechSpeaking {
    func speak(_ text: String)
    func stop()
}

/// Speaks recognized phrases aloud.
/// Prefers Grok Voice TTS when an xAI API key is available; otherwise uses on-device AVSpeech.
@MainActor
final class SpeechOutput: NSObject, SpeechSpeaking {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var speakTask: Task<Void, Never>?
    private let voiceID: String

    /// Published for UI: `grok` when the cloud voice is configured, else `device`.
    private(set) var engineName: String

    init(voiceID: String = GrokTTSClient.defaultVoiceID) {
        self.voiceID = voiceID
        self.engineName = GrokTTSClient.apiKey() == nil ? "device" : "grok"
        super.init()
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        speakTask?.cancel()
        stop()

        speakTask = Task { [weak self] in
            guard let self else { return }
            if GrokTTSClient.apiKey() != nil {
                do {
                    try await self.speakWithGrok(trimmed)
                    return
                } catch {
                    // Fall through to on-device speech if Grok is unreachable.
                }
            }
            guard !Task.isCancelled else { return }
            self.speakOnDevice(trimmed)
        }
    }

    func stop() {
        speakTask?.cancel()
        speakTask = nil
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func speakWithGrok(_ text: String) async throws {
        let data = try await GrokTTSClient.synthesize(text: text, voiceID: voiceID)
        guard !Task.isCancelled else { return }
        try configurePlaybackSession()
        let player = try AVAudioPlayer(data: data)
        player.prepareToPlay()
        audioPlayer = player
        engineName = "grok"
        player.play()
    }

    private func speakOnDevice(_ text: String) {
        engineName = "device"
        try? configurePlaybackSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    private func configurePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true, options: [])
    }
}
