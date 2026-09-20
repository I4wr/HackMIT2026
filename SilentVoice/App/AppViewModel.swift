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
        self.classifier = classifier ?? MockClassifier()
        self.sampleStore = sampleStore ?? SampleStore()
        self.speechOutput = speechOutput ?? SpeechOutput()
        loadSamples()
    }

    func addSample(_ sample: MouthSample) {
        samples.append(sample)
        persistSamples()
        classifier.train(samples: samples)
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
            samples = try sampleStore.load()
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
