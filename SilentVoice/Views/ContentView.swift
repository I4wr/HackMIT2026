import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Speak without speaking")
                            .font(.title2.bold())
                        Text(sampleSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        RecognitionModesView()
                    } label: {
                        HomeActionCard(
                            title: "Start silent speech",
                            subtitle: "Transcribe a sentence or use offline commands",
                            systemImage: "waveform"
                        )
                    }
                    .buttonStyle(.plain)

                    if let prediction = viewModel.latestPrediction {
                        LatestResultCard(prediction: prediction)
                    }

                    if let message = viewModel.lastErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("SilentVoice")
        }
    }

    private var sampleSummary: String {
        let total = viewModel.samples.count
        if total == 0 {
            return "No calibration examples yet"
        }
        return "\(total) calibration example\(total == 1 ? "" : "s") saved"
    }

}

private struct HomeActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 48, height: 48)
                .foregroundStyle(.white)
                .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct LatestResultCard: View {
    let prediction: Prediction

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Latest output")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(prediction.label)
                .font(.title3.bold())
            Text(prediction.accepted ? "Accepted · \(scoreText)" : "Rejected · \(scoreText)")
                .font(.footnote)
                .foregroundStyle(prediction.accepted ? Color.secondary : Color.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var scoreText: String {
        String(format: "score %.2f", prediction.score)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppViewModel())
}
