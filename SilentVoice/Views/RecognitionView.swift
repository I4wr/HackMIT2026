import SwiftUI

struct RecognitionView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @StateObject private var capture = CaptureController()
    @State private var captureTask: Task<Void, Never>?

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
                    isEnabled: !capture.phase.isBusy
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
            CaptureStatusOverlay(phase: capture.phase)
        }
        .onAppear {
            viewModel.tracker.start()
        }
        .onDisappear {
            captureTask?.cancel()
            capture.reset()
            viewModel.tracker.stop()
        }
    }

    private var cameraPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            FaceCameraView()
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(alignment: .topLeading) {
                    FaceStatusBadge(tracker: viewModel.tracker)
                        .padding(12)
                }

            Text("Camera preview is a placeholder until TrueDepth capture is merged.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func candidatesSection(_ prediction: Prediction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top candidates")
                .font(.headline)

            CandidateRow(rank: 1, label: prediction.label, score: prediction.score, isWinner: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func finalOutputSection(_ prediction: Prediction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Final output")
                .font(.headline)
            Text(prediction.label)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(prediction.accepted ? "Accepted" : "UNKNOWN")
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
        captureTask = Task {
            let finished = await capture.capture()
            guard finished, !Task.isCancelled else { return }
            viewModel.predict(frames: MockMouthSequence.frames())
        }
    }
}

private struct FaceStatusBadge: View {
    @ObservedObject var tracker: FaceTracker

    var body: some View {
        let detected = tracker.isFaceDetected
        return HStack(spacing: 8) {
            Circle()
                .fill(detected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(detected ? "Face detected" : "Looking for face")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityLabel(detected ? "Face detected" : "Looking for face")
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
