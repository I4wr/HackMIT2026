import Foundation

struct SampleStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    func load() throws -> [MouthSample] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([MouthSample].self, from: Data(contentsOf: fileURL))
    }

    func save(_ samples: [MouthSample]) throws {
        let data = try JSONEncoder().encode(samples)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private static var defaultFileURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent("SilentVoice", isDirectory: true)
            .appendingPathComponent("mouth-samples.json")
    }
}
