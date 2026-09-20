import SwiftUI

struct RecognitionView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        RecognitionScreen(tracker: viewModel.tracker)
    }
}

private struct RecognitionScreen: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject var tracker: FaceTracker
    @StateObject private var capture = CaptureController()
    @State private var captureTask: Task<Void, Never>?
    @State private var captureMessage: String?
    @State private var captureIsError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                cameraPreview

                if let prediction = viewModel.latestPrediction {
                    candidatesSection(prediction)
                    finalOutputSection(prediction)
                } else {
                    Text("Record a silent phrase to see candidates and the spoken output.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let message = captureMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(captureIsError ? Color.red : Color.secondary)
                }

                if let message = viewModel.lastErrorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle("Recognition")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                RecordButton(
                    title: "Record",
                    isEnabled: canRecord
                ) {
                    beginCapture()
                }

                Button {
                    viewModel.speakLatestPrediction()
                } label: {
                    Label("Speak", systemImage: "speaker.wave.2.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.latestPrediction?.accepted != true || capture.phase.isBusy)
                .accessibilityLabel("Speak")
            }
            .padding()
            .background(.bar)
        }
        .overlay {
            CaptureStatusOverlay(phase: capture.phase, frameCount: capture.capturedFrameCount)
        }
        .onDisappear {
            captureTask?.cancel()
            capture.reset()
        }
    }

    private var canRecord: Bool {
        guard !capture.phase.isBusy else { return false }
        switch tracker.status {
        case .permissionDenied, .requestingPermission, .failed(_):
            return false
        default:
            return true
        }
    }

    private var cameraPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            FaceCameraView()
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Text("Face the camera, mouth a phrase, then tap Record.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func candidatesSection(_ prediction: Prediction) -> some View {
        let rows: [(label: String, score: Float)] = {
            if prediction.candidates.isEmpty {
                return [(prediction.label, prediction.score)]
            }
            return prediction.candidates.prefix(3).map { ($0.label, $0.score) }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            Text("Top candidates")
                .font(.headline)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                CandidateRow(
                    rank: index + 1,
                    label: row.label,
                    score: row.score,
                    isWinner: index == 0
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func finalOutputSection(_ prediction: Prediction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Final output")
                .font(.headline)
            Text(prediction.accepted ? prediction.label : "UNKNOWN")
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
            if !prediction.accepted {
                Text("Best match: \(prediction.label == "UNKNOWN" ? (prediction.candidates.first?.label ?? "none") : prediction.label)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(prediction.accepted ? "Accepted" : "UNKNOWN — signal did not confidently match")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(prediction.accepted ? .green : .red)
            Text(String(format: "Score %.2f", prediction.score))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func beginCapture() {
        captureTask?.cancel()
        captureMessage = nil
        captureIsError = false
        captureTask = Task {
            switch await capture.run(from: tracker) {
            case .cancelled:
                return
            case .success(let frames, let warning):
                viewModel.predict(frames: frames)
                captureMessage = warning
                captureIsError = false
            case .failed(let message):
                captureMessage = message
                captureIsError = true
            }
        }
    }
}

private struct CandidateRow: View {
    let rank: Int
    let label: String
    let score: Float
    let isWinner: Bool

    var body: some View {
        HStack {
            Text("\(rank)")
                .font(.headline.monospacedDigit())
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.body.weight(isWinner ? .semibold : .regular))
                Text(String(format: "%.2f", score))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isWinner {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Candidate \(rank), \(label), score \(String(format: "%.2f", score))")
    }
}

#Preview {
    NavigationStack {
        RecognitionView()
    }
    .environmentObject(AppViewModel())
}
