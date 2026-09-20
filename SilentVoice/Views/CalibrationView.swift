import SwiftUI

struct CalibrationView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @StateObject private var capture = CaptureController()
    @State private var selectedPhrase = PhraseCatalog.phrases[0]
    @State private var captureTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Phrase to mouth")
                    .font(.headline)

                VStack(spacing: 8) {
                    ForEach(PhraseCatalog.phrases, id: \.self) { phrase in
                        phraseRow(phrase)
                    }
                }

                progressSection

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
                    isEnabled: !capture.phase.isBusy
                ) {
                    beginCapture(replacingLast: false)
                }

                Button("Re-record") {
                    beginCapture(replacingLast: true)
                }
                .disabled(capture.phase.isBusy || examplesForSelectedPhrase.isEmpty)
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

    private var examplesForSelectedPhrase: [MouthSample] {
        viewModel.samples.filter { $0.label == selectedPhrase }
    }

    private var progressSection: some View {
        let count = examplesForSelectedPhrase.count
        let target = PhraseCatalog.targetExampleCount

        return VStack(alignment: .leading, spacing: 8) {
            Text("Example \(count)/\(target)")
                .font(.title3.bold())
                .accessibilityLabel("Example \(count) of \(target)")

            ProgressView(
                value: Double(min(count, target)),
                total: Double(target)
            )

            Text(count >= target ? "Target reached. Extra examples are still saved." : "Record a short silent articulation of the selected phrase.")
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
        captureTask = Task {
            let finished = await capture.capture()
            guard finished, !Task.isCancelled else { return }
            if replacingLast {
                viewModel.removeLastSample(labeled: selectedPhrase)
            }
            viewModel.addSample(
                MouthSample(label: selectedPhrase, frames: MockMouthSequence.frames())
            )
        }
    }
}

#Preview {
    NavigationStack {
        CalibrationView()
    }
    .environmentObject(AppViewModel())
}
