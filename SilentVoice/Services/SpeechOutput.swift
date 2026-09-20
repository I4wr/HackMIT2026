import AVFoundation

@MainActor
protocol SpeechSpeaking {
    func speak(_ text: String)
}

@MainActor
final class SpeechOutput: SpeechSpeaking {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
