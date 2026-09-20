import Testing
@testable import SilentVoice

@Suite @MainActor
struct MouthFeaturePipelineTests {
    @Test func featureOrderIsStableRegardlessOfDictionaryOrder() throws {
        let names = MouthFeatureSchema.names
        #expect(MouthFeatureSchema.version == 1)
        #expect(names.count == 24)
        #expect(Set(names).count == 24)
        #expect(names == [
            "jawOpen", "jawForward", "jawLeft", "jawRight", "mouthClose",
            "mouthFunnel", "mouthPucker", "mouthLeft", "mouthRight",
            "mouthSmileLeft", "mouthSmileRight", "mouthFrownLeft", "mouthFrownRight",
            "mouthDimpleLeft", "mouthDimpleRight", "mouthStretchLeft", "mouthStretchRight",
            "mouthRollLower", "mouthRollUpper", "mouthShrugLower", "mouthShrugUpper",
            "mouthPressLeft", "mouthPressRight", "cheekPuff"
        ])
        let pairs = names.enumerated().map { ($0.element, Float($0.offset) / 24) }
        let features = try #require(MouthFeatureSchema.features(from: Dictionary(uniqueKeysWithValues: pairs.reversed())))
        #expect(features == (0..<24).map { Float($0) / 24 })
    }

    @Test func missingAndOutOfRangeCoefficients() throws {
        let features = try #require(MouthFeatureSchema.features(from: ["jawOpen": 2, "jawForward": -1, "unrelated": 0.5]))
        #expect(features == [1] + Array(repeating: Float(0), count: 23))
        #expect(MouthFeatureSchema.features(from: [:]) == Array(repeating: Float(0), count: 24))
    }

    @Test func nonfiniteCoefficientsAreRejected() {
        #expect(MouthFeatureSchema.features(from: ["jawOpen": .nan]) == nil)
        #expect(MouthFeatureSchema.features(from: ["mouthFunnel": .infinity]) == nil)
    }

    @Test(arguments: [30, 60, 120])
    func emitsThirtyFramesPerSecond(cameraRate: Int) {
        var sampler = MouthFrameSampler()
        let emitted = (0..<(cameraRate * 10)).filter {
            sampler.shouldEmit(at: 100 + Double($0) / Double(cameraRate))
        }
        #expect(emitted.count == 300)
    }

    @Test func handlesCaptureJitterWithoutHalvingRate() {
        var sampler = MouthFrameSampler()
        let emitted = (0..<300).filter {
            let jitter = $0.isMultiple(of: 2) ? 0.0002 : -0.0002
            return sampler.shouldEmit(at: 100 + Double($0) / 30 + jitter)
        }
        #expect(emitted.count == 300)
    }

    @Test func slowCameraDoesNotProduceSyntheticFrames() {
        var sampler = MouthFrameSampler()
        #expect((0..<150).filter { sampler.shouldEmit(at: Double($0) / 15) }.count == 150)
    }

    @Test func rejectsInvalidDuplicateAndBackwardsTimestamps() {
        var sampler = MouthFrameSampler()
        let times: [Double] = [.nan, .infinity, -1, 1, 1, 0.5, 1.01, 1 + 1.0 / 30]
        let results = times.map { sampler.shouldEmit(at: $0) }
        #expect(results == [false, false, false, true, false, false, false, true])
    }

    @Test func gapDoesNotCauseCatchUpBurstAndResetAcceptsNewClock() {
        var sampler = MouthFrameSampler()
        let results = [0.0, 10, 10.001].map { sampler.shouldEmit(at: $0) }
        #expect(results == [true, true, false])
        sampler.reset()
        let emitsAfterReset = sampler.shouldEmit(at: 0)
        #expect(emitsAfterReset)
    }
}
