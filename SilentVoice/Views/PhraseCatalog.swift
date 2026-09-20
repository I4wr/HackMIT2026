import Foundation

enum PhraseCatalog {
    static let words = [
        "help",
        "water",
        "stop",
        "yes",
        "no"
    ]

    /// Compatibility alias for existing classifier/UI wiring.
    static let phrases = words

    static let spokenOutputByWord = [
        "help": "I need help",
        "water": "I need water",
        "stop": "Stop",
        "yes": "Yes",
        "no": "No"
    ]

    static let targetExampleCount = 20
    static let recordingLabels = words + ["REST", "UNKNOWN"]

    static func spokenOutput(for word: String) -> String {
        spokenOutputByWord[word.lowercased()] ?? word
    }
}
