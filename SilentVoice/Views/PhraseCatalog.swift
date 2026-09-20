import Foundation

enum PhraseCatalog {
    static let phrases = [
        "I need help",
        "I need water"
    ]

    static let targetExampleCount = 20
    static let recordingLabels = phrases + ["REST", "UNKNOWN"]
}
