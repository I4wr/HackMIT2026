import SwiftUI

struct RecognitionView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 16) {
            FaceCameraView()
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Text(viewModel.latestPrediction?.label ?? "Ready to recognize")
                .font(.title2.bold())

            Button("Try mock prediction") {
                viewModel.predict(frames: [])
            }
            .buttonStyle(.borderedProminent)

            Button("Speak") {
                viewModel.speakLatestPrediction()
            }
            .disabled(viewModel.latestPrediction?.accepted != true)
        }
        .padding()
        .navigationTitle("Recognition")
    }
}
