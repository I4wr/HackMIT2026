import Foundation

/// Load / save labeled mouth sequences as JSON for Person 1 sample-data
/// and offline Person 2 evaluation.
enum SampleIO {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static func loadSample(from url: URL) throws -> MouthSample {
        let data = try Data(contentsOf: url)
        return try decoder.decode(MouthSample.self, from: data)
    }

    static func loadSamples(fromDirectory directory: URL) throws -> [MouthSample] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension.lowercased() == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try urls.map { try loadSample(from: $0) }
    }

    static func saveSample(_ sample: MouthSample, to url: URL) throws {
        let data = try encoder.encode(sample)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
