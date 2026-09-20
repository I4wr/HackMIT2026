import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Calibrate", destination: CalibrationView())
                NavigationLink("Start silent speech", destination: RecognitionView())
            }
            .navigationTitle("SilentVoice")
        }
    }
}
