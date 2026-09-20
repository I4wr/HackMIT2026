import SwiftUI

/// Placeholder preview surface for the ARKit view Person 1 will provide.
struct FaceCameraView: View {
    var body: some View {
        ZStack {
            Color.black
            Image(systemName: "faceid")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.8))
        }
        .accessibilityLabel("TrueDepth camera preview")
    }
}
