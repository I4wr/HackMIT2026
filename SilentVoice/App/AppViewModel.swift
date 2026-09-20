import Foundation
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var samples: [MouthSample] = []
    @Published var latestPrediction: Prediction?
    @Published var lastErrorMessage: String?

    let tracker: FaceTracker
    let classifier: any MouthClassifying
    let speechOutput: SpeechOutput
    private let sampleStore: SampleStore

    init(
        tracker: FaceTracker? = nil,
        classifier: (any MouthClassifying)? = nil,
        sampleStore: SampleStore? = nil,
        speechOutput: SpeechOutput? = nil
    ) {
        self.tracker = tracker ?? FaceTracker()
        self.classifier = classifier ?? DTWClassifier()
        self.sampleStore = sampleStore ?? SampleStore()
        self.speechOutput = speechOutput ?? SpeechOutput()
        loadSamples()
    }

    func addSample(_ sample: MouthSample, replacingLast: Bool = false) {
        var updated = samples
        if replacingLast, let index = updated.lastIndex(where: { $0.label == sample.label }) {
            updated.remove(at: index)
        }
        updated.append(sample)
        do {
            try sampleStore.save(updated)
            samples = updated
            classifier.train(samples: samples)
        } catch {
            lastErrorMessage = "Could not save calibration samples: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func removeLastSample(labeled label: String) -> MouthSample? {
        guard let index = samples.lastIndex(where: { $0.label == label }) else { return nil }
        let removed = samples.remove(at: index)
        persistSamples()
        classifier.train(samples: samples)
        return removed
    }

    func predict(frames: [MouthFrame]) {
        latestPrediction = classifier.predict(frames: frames)
    }

    func speakLatestPrediction() {
        guard let prediction = latestPrediction, prediction.accepted else { return }
        speechOutput.speak(prediction.label)
    }

    private func loadSamples() {
        do {
            // Earlier UI versions generated mock samples; never train live recognition on them.
            samples = try sampleStore.load().filter { $0.captureSource == "TrueDepth" }
            classifier.train(samples: samples)
        } catch {
            lastErrorMessage = "Could not load calibration samples: \(error.localizedDescription)"
        }
    }

    private func persistSamples() {
        do {
            try sampleStore.save(samples)
        } catch {
            lastErrorMessage = "Could not save calibration samples: \(error.localizedDescription)"
        }
    }
}
