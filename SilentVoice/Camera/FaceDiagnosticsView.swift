import SwiftUI

struct FaceDiagnosticsView: View {
    @ObservedObject var tracker: FaceTracker
    @State private var showSensorDetails = false
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    private let movements: [(String, String)] = [
        ("Jaw open", "jawOpen"), ("Mouth close", "mouthClose"),
        ("Lip pucker", "mouthPucker"), ("Lip funnel", "mouthFunnel"),
        ("Smile left", "mouthSmileLeft"), ("Smile right", "mouthSmileRight"),
        ("Lip down L", "mouthLowerDownLeft"), ("Lip down R", "mouthLowerDownRight")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Live readings", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                Text(tracker.isFaceDetected ? "Live" : "Waiting")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tracker.isFaceDetected ? .green : .secondary)
            }
            if let snapshot = tracker.diagnostics {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    metric("Colour camera", value: "\(snapshot.rgbWidth) × \(snapshot.rgbHeight)", symbol: "camera")
                    metric("Frame rate", value: String(format: "%.0f fps", tracker.framesPerSecond), symbol: "speedometer")
                    metric("Face distance", value: String(format: "%.0f cm", snapshot.faceDistanceCentimeters), symbol: "arrow.left.and.right")
                    metric("Depth", value: depthStatus(snapshot), symbol: "square.3.layers.3d")
                }

                Divider()
                Text("Mouth movement · 0–1")
                    .font(.subheadline.weight(.semibold))
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(movements, id: \.1) { label, key in
                        movement(label, value: snapshot.blendShapes[key])
                    }
                }

                DisclosureGroup("Depth, mesh & head movement", isExpanded: $showSensorDetails) {
                    VStack(alignment: .leading, spacing: 10) {
                        detail("Mesh vertices", value: "\(snapshot.vertexCount)")
                        detail("RGB exposure", value: String(format: "%.1f ms", snapshot.exposureMilliseconds))
                        if let depth = snapshot.depth {
                            detail("Depth resolution", value: "\(depth.width) × \(depth.height)")
                            detail("Valid depth pixels (sampled)", value: snapshot.hasRecentDepth ? String(format: "%.0f%%", depth.validFraction * 100) : "Stale")
                            detail("Median scene depth", value: snapshot.hasRecentDepth ? depth.medianMeters.map { String(format: "%.0f cm", $0 * 100) } ?? "No valid pixels" : "Stale")
                            detail("Depth sample age", value: snapshot.depthOffsetMilliseconds.map { String(format: "%.0f ms", max(0, $0)) } ?? "—")
                        }
                        detail("Depth samples received", value: snapshot.depthFramesPerSecond.map { String(format: "%.0f / sec", $0) } ?? "Measuring…")
                        Text("Depth statistics sample the whole depth image, including the background. They are not mouth-only measurements or recognition confidence.")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        detail("Head turn (yaw)", value: degrees(snapshot.yawDegrees))
                        detail("Head nod (pitch)", value: degrees(snapshot.pitchDegrees))
                        detail("Head tilt (roll)", value: degrees(snapshot.rollDegrees))
                        Text("Head angles are relative to your first tracked pose and reset when tracking is lost. Left/right movement labels refer to your face.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.top, 10)
                }
                .font(.subheadline)
            } else {
                Text(tracker.status.message)
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Face, colour and depth readings appear when tracking starts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func depthStatus(_ snapshot: FaceDiagnostics) -> String {
        guard snapshot.depth != nil else { return "Not available yet" }
        return snapshot.hasRecentDepth ? "Receiving" : "No recent frame"
    }

    private func degrees(_ value: Float) -> String { String(format: "%+.0f°", value) }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func movement(_ label: String, value: Float?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                Spacer(minLength: 4)
                Text(value.map { String(format: "%.2f", $0) } ?? "—").monospacedDigit()
            }
            .font(.caption)
            ProgressView(value: Double(min(1, max(0, value ?? 0)))).tint(.teal)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.map { String(format: "%.2f out of 1", $0) } ?? "Unavailable")
    }

    private func detail(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Text(value).monospacedDigit()
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }
}
