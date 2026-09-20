import AVFoundation
import Foundation

@MainActor
protocol SpeechSpeaking {
    func speak(_ text: String)
    func stop()
}

/// Speaks recognized phrases aloud.
/// Prefers ElevenLabs when its API key is available; otherwise uses on-device AVSpeech.
@MainActor
final class SpeechOutput: NSObject, SpeechSpeaking {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var speakTask: Task<Void, Never>?
    private let voiceID: String

    /// Published for UI: `elevenlabs` when cloud speech succeeds, else `device`.
    private(set) var engineName: String

    init(voiceID: String = ElevenLabsTTSClient.defaultVoiceID) {
        self.voiceID = voiceID
        self.engineName = ElevenLabsTTSClient.apiKey() == nil ? "device" : "elevenlabs"
        super.init()
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        speakTask?.cancel()
        stop()

        speakTask = Task { [weak self] in
            guard let self else { return }
            if ElevenLabsTTSClient.apiKey() != nil {
                do {
                    try await self.speakWithElevenLabs(trimmed)
                    return
                } catch {
                    print("ElevenLabs TTS error: \(error.localizedDescription)")
                    // Fall through to on-device speech if ElevenLabs is unreachable.
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

    private func speakWithElevenLabs(_ text: String) async throws {
        let data = try await ElevenLabsTTSClient.synthesize(text: text, voiceID: voiceID)
        guard !Task.isCancelled else { return }
        try configurePlaybackSession()
        let player = try AVAudioPlayer(data: data)
        player.prepareToPlay()
        audioPlayer = player
        engineName = "elevenlabs"
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
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true, options: [])
#endif
    }
}
