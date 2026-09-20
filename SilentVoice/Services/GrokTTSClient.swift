import Foundation

/// Thin client for xAI Grok text-to-speech (`POST /v1/tts`).
enum GrokTTSClient {
    static let endpoint = URL(string: "https://api.x.ai/v1/tts")!
    static let defaultVoiceID = "rex"

    enum TTSError: LocalizedError {
        case missingAPIKey
        case badStatus(Int, String)
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Set XAI_API_KEY in the Xcode scheme or SilentVoice/Resources/Secrets.plist."
            case .badStatus(let code, let body):
                return "Grok TTS failed (\(code)): \(body)"
            case .emptyAudio:
                return "Grok TTS returned empty audio."
            }
        }
    }

    /// Resolves the key from (1) process environment `XAI_API_KEY`,
    /// (2) Info.plist `XAIAPIKey`,
    /// (3) bundled `Secrets.plist` (copy `Resources/Secrets.example.plist`).
    static func apiKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["XAI_API_KEY"], !env.isEmpty {
            return env
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "XAIAPIKey") as? String, !plist.isEmpty {
            return plist
        }
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url) as? [String: Any],
           let key = dict["XAI_API_KEY"] as? String,
           !key.isEmpty {
            return key
        }
        return nil
    }

    static func synthesize(
        text: String,
        voiceID: String = defaultVoiceID,
        language: String = "en",
        apiKey: String? = nil
    ) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TTSError.emptyAudio }
        guard let key = apiKey ?? Self.apiKey(), !key.isEmpty else {
            throw TTSError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": trimmed,
            "voice_id": voiceID,
            "language": language,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TTSError.badStatus(status, String(body.prefix(240)))
        }
        guard !data.isEmpty else { throw TTSError.emptyAudio }
        return data
    }
}
