import XCTest
@testable import SilentVoice

/// Add this folder as a unit-test target when Person 4 configures tests in Xcode.
final class SharedContractsTests: XCTestCase {
    func testMouthSampleRoundTripsThroughJSON() throws {
        let sample = MouthSample(label: "help", frames: [MouthFrame(timestamp: 0, features: [0.1])])
        let decoded = try JSONDecoder().decode(MouthSample.self, from: JSONEncoder().encode(sample))
        XCTAssertEqual(decoded, sample)
    }
}
