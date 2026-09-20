import ARKit
import SwiftUI

/// FaceCameraView() shares the app's tracker. Standalone callers may pass one.
struct FaceCameraView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    private let tracker: FaceTracker?

    init(tracker: FaceTracker? = nil) {
        self.tracker = tracker
    }

    var body: some View {
        TrackingCameraSurface(tracker: tracker ?? viewModel.tracker)
    }
}

private struct TrackingCameraSurface: View {
    @ObservedObject var tracker: FaceTracker
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            CameraPreview(session: tracker.session)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Label(tracker.status.message,
                      systemImage: tracker.isFaceDetected ? "faceid" : "camera")
                if tracker.isFaceDetected {
                    Text("\(tracker.framesPerSecond, specifier: "%.0f") fps · \(tracker.currentFeatures.count) movement features")
                        .monospacedDigit()
                }
                if case .failed = tracker.status {
                    Button("Retry camera") { tracker.start() }
                        .buttonStyle(.bordered)
                }
            }
            .font(.caption)
            .foregroundStyle(.white)
            .padding(10)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            .padding(12)
        }
        .clipped()
        .onAppear {
            if scenePhase == .active { tracker.start() }
        }
        .onDisappear { tracker.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { tracker.start() } else { tracker.stop() }
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = false
        view.preferredFramesPerSecond = 30
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        if view.session !== session { view.session = session }
    }
}
