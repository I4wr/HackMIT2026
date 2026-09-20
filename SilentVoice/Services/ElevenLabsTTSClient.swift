import Foundation

/// Thin client for ElevenLabs text-to-speech (`POST /v1/text-to-speech/{voice_id}`).
enum ElevenLabsTTSClient {
    /// Adam: a deep, confident English voice.
    nonisolated static let defaultVoiceID = "pNInz6obpgDQGcFmaJgB"
    nonisolated static let defaultModelID = "eleven_multilingual_v2"

    enum TTSError: LocalizedError {
        case missingAPIKey
        case badStatus(Int, String)
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Set ELEVENLABS_API_KEY in the Xcode scheme or SilentVoice/Resources/Secrets.plist."
            case .badStatus(let code, let body):
                return "ElevenLabs TTS failed (\(code)): \(body)"
            case .emptyAudio:
                return "ElevenLabs returned empty audio."
            }
        }
    }

    static func apiKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"], !env.isEmpty {
            return env
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "ElevenLabsAPIKey") as? String,
           !plist.isEmpty {
            return plist
        }
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url) as? [String: Any],
           let key = dict["ELEVENLABS_API_KEY"] as? String,
           !key.isEmpty {
            return key
        }
        return nil
    }

    static func synthesize(
        text: String,
        voiceID: String = defaultVoiceID,
        modelID: String = defaultModelID,
        apiKey: String? = nil
    ) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TTSError.emptyAudio }
        guard let key = apiKey ?? Self.apiKey(), !key.isEmpty else {
            throw TTSError.missingAPIKey
        }

        let encodedVoiceID = voiceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? voiceID
        let endpoint = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(encodedVoiceID)?output_format=mp3_44100_128")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": trimmed,
            "model_id": modelID,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TTSError.badStatus(status, String(body.prefix(500)))
        }
        guard !data.isEmpty else { throw TTSError.emptyAudio }
        return data
    }
}
