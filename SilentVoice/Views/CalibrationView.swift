import SwiftUI

struct CalibrationView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 52))
            Text("Calibration")
                .font(.title.bold())
            Text("Recording controls will be implemented on the interface branch.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Calibrate")
    }
}
