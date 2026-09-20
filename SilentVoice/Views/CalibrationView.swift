import SwiftUI

struct CalibrationView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        CalibrationScreen(tracker: viewModel.tracker)
    }
}

private struct CalibrationScreen: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject var tracker: FaceTracker
    @StateObject private var capture = CaptureController()
    @State private var selectedPhrase = PhraseCatalog.words[0]
    @State private var captureTask: Task<Void, Never>?
    @State private var datasetSplit = "training"
    @State private var savedMessage: String?
    @State private var captureMessage: String?
    @State private var captureIsError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                cameraPreview
                FaceDiagnosticsView(tracker: viewModel.tracker)
                Text("Word to mouth")
                    .font(.headline)

                VStack(spacing: 8) {
                    ForEach(PhraseCatalog.recordingLabels, id: \.self) { phrase in
                        phraseRow(phrase)
                    }
                }

                progressSection
                Picker("Recording purpose", selection: $datasetSplit) {
                    Text("Training").tag("training")
                    Text("Validation").tag("validation")
                    Text("Test").tag("test")
                }
                .disabled(capture.phase.isBusy)
                Text("Validation and test takes are saved separately from training. Record them in a later session. For REST, stay relaxed. For UNKNOWN, make unrelated expressions or mouth other words.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let savedMessage {
                    Text(savedMessage).font(.footnote).foregroundStyle(.secondary)
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
        .navigationTitle("Calibrate")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                RecordButton(
                    title: "Record",
                    isEnabled: canRecord
                ) {
                    beginCapture(replacingLast: false)
                }

                Button("Re-record") {
                    beginCapture(replacingLast: true)
                }
                .disabled(capture.phase.isBusy || examplesForSelectedPhrase.isEmpty || datasetSplit != "training")
            }
            .padding()
            .background(.bar)
        }
        .overlay {
            CaptureStatusOverlay(phase: capture.phase)
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

    private var examplesForSelectedPhrase: [MouthSample] {
        viewModel.samples.filter { $0.label == selectedPhrase }
    }

    private var cameraPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            FaceCameraView()
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Text("Face the camera, then mouth the selected phrase.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var progressSection: some View {
        let count = examplesForSelectedPhrase.count
        let target = PhraseCatalog.targetExampleCount

        return VStack(alignment: .leading, spacing: 8) {
            Text("Training examples \(count)/\(target)")
                .font(.title3.bold())
                .accessibilityLabel("Example \(count) of \(target)")

            ProgressView(
                value: Double(min(count, target)),
                total: Double(target)
            )

            Text(count >= target ? "Target reached. Extra examples are still saved." : "Record a short silent articulation of the selected word.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func phraseRow(_ phrase: String) -> some View {
        let count = viewModel.samples.filter { $0.label == phrase }.count
        let isSelected = selectedPhrase == phrase

        return Button {
            selectedPhrase = phrase
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(phrase)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(count)/\(PhraseCatalog.targetExampleCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue.opacity(0.4) : Color.secondary.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
        .disabled(capture.phase.isBusy)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func beginCapture(replacingLast: Bool) {
        captureTask?.cancel()
        captureMessage = nil
        captureIsError = false
        captureTask = Task {
            let phrase = selectedPhrase
            let split = datasetSplit
            viewModel.lastErrorMessage = nil
            savedMessage = nil
            do {
                let sample = try await capture.capture(tracker: viewModel.tracker, label: phrase, datasetSplit: split)
                guard !Task.isCancelled else { return }
                if split == "training" { viewModel.addSample(sample, replacingLast: replacingLast) }
                if viewModel.lastErrorMessage == nil { savedMessage = "Saved \(split) recording for \(phrase)." }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                viewModel.lastErrorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        CalibrationView()
    }
    .environmentObject(AppViewModel())
}
