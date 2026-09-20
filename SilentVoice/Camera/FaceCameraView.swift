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
    @AppStorage("faceOverlayEnabled") private var faceOverlayEnabled = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            CameraPreview(session: tracker.session,
                          overlayEnabled: faceOverlayEnabled,
                          isTracking: tracker.isFaceDetected && scenePhase == .active)
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
        .overlay(alignment: .topTrailing) {
            Toggle(isOn: $faceOverlayEnabled) {
                Label("Face overlay", systemImage: "face.dashed")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 32, minHeight: 32)
            }
            .toggleStyle(.button)
            .font(.title3)
            .tint(.cyan)
            .foregroundStyle(.white)
            .padding(6)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            .padding(12)
            .accessibilityLabel("Face overlay")
            .accessibilityValue(faceOverlayEnabled ? "On" : "Off")
            .accessibilityHint("Shows tracked face points and connecting lines")
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
    let overlayEnabled: Bool
    let isTracking: Bool

    func makeCoordinator() -> FaceOverlayRenderer {
        FaceOverlayRenderer()
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.delegate = context.coordinator
        context.coordinator.setVisibility(enabled: overlayEnabled, isTracking: isTracking)
        view.automaticallyUpdatesLighting = false
        view.preferredFramesPerSecond = 30
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        if view.session !== session { view.session = session }
        context.coordinator.setVisibility(enabled: overlayEnabled, isTracking: isTracking)
    }

    static func dismantleUIView(_ view: ARSCNView, coordinator: FaceOverlayRenderer) {
        view.delegate = nil
        coordinator.invalidate()
    }
}
