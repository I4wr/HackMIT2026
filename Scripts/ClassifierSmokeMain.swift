import Foundation

/// Offline Person 2 check — not part of the iOS app target.
@main
struct ClassifierSmokeMain {
    static func main() throws {
        let root = findRepoRoot()
        let sampleDir = root.appendingPathComponent("sample-data")

        try exportFixtures(to: sampleDir)
        try verifySampleIO(sampleDir: sampleDir)

        let acceptance = ClassifierIntegration.syntheticAcceptance
        let gap = ClassifierIntegration.syntheticGap
        let motion = ClassifierIntegration.syntheticMotionEnergy
        print("thresholds: accept=\(acceptance) gap=\(gap) motion=\(motion)")
        print(
            "real-data hints: accept=\(ClassifierIntegration.realDataAcceptanceHint) gap=\(ClassifierIntegration.realDataGapHint) motion=\(ClassifierIntegration.realDataMotionEnergyHint)"
        )

        let classifier = DTWClassifier(
            acceptanceThreshold: acceptance,
            minimumScoreGap: gap,
            minimumMotionEnergy: motion
        )
        classifier.train(samples: FakeMouthSamples.trainingSet() + [FakeMouthSamples.rest()])

        // REST must not become a trainable phrase template.
        let restEnergy = Preprocessor().process(FakeMouthSamples.rest()).motionEnergy
        print("REST motionEnergy=\(String(format: "%.4f", restEnergy))")

        let restPrediction = classifier.predict(frames: FakeMouthSamples.rest().frames)
        print(
            "REST → \(restPrediction.label) accepted=\(restPrediction.accepted) candidates=\(restPrediction.candidates.map(\.label))"
        )
        guard !restPrediction.accepted, restPrediction.label == "UNKNOWN" else {
            fputs("FAIL: REST should be UNKNOWN\n", stderr)
            exit(1)
        }

        let labeled = FakeMouthSamples.evaluationSet()
        let result = ClassifierEvaluator.evaluate(
            classifier: classifier,
            labeledFrames: labeled
        )
        print(
            "eval accuracy=\(String(format: "%.1f%%", result.accuracy * 100)) correct=\(result.correct)/\(result.total) unknowns=\(result.unknowns)"
        )
        guard result.accuracy == 1 else {
            fputs("FAIL: expected 100% on evaluation set\n", stderr)
            exit(1)
        }

        for label in FakeMouthSamples.vocabulary {
            let prediction = classifier.predict(frames: FakeMouthSamples.sample(for: label).frames)
            print(
                "\(label) → \(prediction.label) score=\(String(format: "%.3f", prediction.score)) accepted=\(prediction.accepted) top3=\(prediction.candidates.prefix(3).map(\.label))"
            )
            guard prediction.accepted, prediction.label == label, prediction.candidates.count <= 3 else {
                fputs("FAIL: expected \(label) with <=3 candidates\n", stderr)
                exit(1)
            }
        }

        let unknown = classifier.predict(frames: FakeMouthSamples.unrelatedFrames())
        print(
            "noise → \(unknown.label) score=\(String(format: "%.3f", unknown.score)) accepted=\(unknown.accepted)"
        )
        guard !unknown.accepted, unknown.label == "UNKNOWN" else {
            fputs("FAIL: expected UNKNOWN for unrelated frames\n", stderr)
            exit(1)
        }

        // Stress: near-collisions should not crash; prefer correct phrase or UNKNOWN.
        let yesTwin = classifier.predict(frames: FakeMouthSamples.yesNearCollision().frames)
        let helpTwin = classifier.predict(frames: FakeMouthSamples.helpNearCollision().frames)
        let ambiguous = classifier.predict(frames: FakeMouthSamples.ambiguousYesNo().frames)
        print(
            "stress yes-twin → \(yesTwin.label) accepted=\(yesTwin.accepted) score=\(String(format: "%.3f", yesTwin.score))"
        )
        print(
            "stress help-twin → \(helpTwin.label) accepted=\(helpTwin.accepted) score=\(String(format: "%.3f", helpTwin.score))"
        )
        print(
            "stress ambiguous → \(ambiguous.label) accepted=\(ambiguous.accepted) score=\(String(format: "%.3f", ambiguous.score)) top=\(ambiguous.candidates.prefix(2).map(\.label))"
        )
        // Soft twin of yes should map to yes or UNKNOWN — never a random other phrase with high confidence.
        if yesTwin.accepted {
            guard yesTwin.label == "yes" else {
                fputs("FAIL: yes-twin accepted as \(yesTwin.label)\n", stderr)
                exit(1)
            }
        }
        if helpTwin.accepted {
            guard helpTwin.label == "help" else {
                fputs("FAIL: help-twin accepted as \(helpTwin.label)\n", stderr)
                exit(1)
            }
        }

        let diskSamples = try SampleIO.loadSamples(fromDirectory: sampleDir)
        let fromDisk = DTWClassifier(
            acceptanceThreshold: acceptance,
            minimumScoreGap: gap,
            minimumMotionEnergy: motion
        )
        fromDisk.train(samples: diskSamples)
        let diskHelp = fromDisk.predict(frames: FakeMouthSamples.help().frames)
        print(
            "from sample-data JSON (\(diskSamples.count) files): help → \(diskHelp.label) accepted=\(diskHelp.accepted)"
        )
        guard diskHelp.accepted, diskHelp.label == "help" else {
            fputs("FAIL: sample-data retrain did not recognize help\n", stderr)
            exit(1)
        }

        let mock = MockClassifier()
        let mockPrediction = mock.predict(frames: [])
        guard mockPrediction.accepted, mockPrediction.label == "I need help" else {
            fputs("FAIL: MockClassifier contract\n", stderr)
            exit(1)
        }
        print("MockClassifier OK for Person 4 UI wiring")

        print("PASS: Person 2 solo work complete (waiting on TrueDepth samples + app wiring).")
    }

    private static func exportFixtures(to directory: URL) throws {
        let fixtures: [(String, MouthSample)] = [
            ("help-01.json", FakeMouthSamples.help()),
            ("help-02.json", FakeMouthSamples.noisyCopy(FakeMouthSamples.help())),
            ("water-01.json", FakeMouthSamples.water()),
            ("water-02.json", FakeMouthSamples.noisyCopy(FakeMouthSamples.water())),
            ("yes-01.json", FakeMouthSamples.yes()),
            ("no-01.json", FakeMouthSamples.no()),
            ("stop-01.json", FakeMouthSamples.stop()),
            ("rest-01.json", FakeMouthSamples.rest()),
        ]

        for (name, sample) in fixtures {
            try SampleIO.saveSample(sample, to: directory.appendingPathComponent(name))
        }
        print("wrote \(fixtures.count) JSON fixtures → \(directory.path)")
    }

    private static func verifySampleIO(sampleDir: URL) throws {
        let loaded = try SampleIO.loadSample(
            from: sampleDir.appendingPathComponent("help-01.json")
        )
        guard loaded.label == "help", !loaded.frames.isEmpty else {
            fputs("FAIL: SampleIO round-trip\n", stderr)
            exit(1)
        }
        print("SampleIO round-trip OK (\(loaded.frames.count) frames)")
    }

    private static func findRepoRoot() -> URL {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let marker = url.appendingPathComponent("SilentVoice")
            if FileManager.default.fileExists(atPath: marker.path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
