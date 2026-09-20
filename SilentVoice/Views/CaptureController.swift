import Combine
import Foundation
import SwiftUI

enum CapturePhase: Equatable {
    case idle
    case countdown(Int)
    case recording

    var isBusy: Bool {
        self != .idle
    }
}

enum CaptureOutcome: Equatable {
    case cancelled
    case recorded([MouthFrame])
    case empty
}

enum ResolvedCapture: Equatable {
    case cancelled
    case success([MouthFrame], warning: String?)
    case failed(String)
}

@MainActor
final class CaptureController: ObservableObject {
    @Published private(set) var phase: CapturePhase = .idle
    @Published private(set) var capturedFrameCount = 0

    private var frameCancellable: AnyCancellable?
    private static let minimumFrameCount = 10

    func capture(
        from tracker: FaceTracker,
        countdownSeconds: Int = 3,
        recordingDuration: TimeInterval = 1.5
    ) async -> CaptureOutcome {
        capturedFrameCount = 0
        let buffer = FrameBuffer()

        for remaining in stride(from: countdownSeconds, through: 1, by: -1) {
            phase = .countdown(remaining)
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                reset()
                return .cancelled
            }
        }

        phase = .recording
        frameCancellable = tracker.frames.sink { [weak self] frame in
            buffer.frames.append(frame)
            self?.capturedFrameCount = buffer.frames.count
        }

        do {
            try await Task.sleep(for: .seconds(recordingDuration))
        } catch {
            stopListening()
            reset()
            return .cancelled
        }

        stopListening()
        phase = .idle
        return buffer.frames.isEmpty ? .empty : .recorded(buffer.frames)
    }

    func run(from tracker: FaceTracker) async -> ResolvedCapture {
        switch await capture(from: tracker) {
        case .cancelled:
            return .cancelled
        case .recorded(let frames) where frames.count >= Self.minimumFrameCount:
            return .success(frames, warning: nil)
        case .recorded, .empty:
            if tracker.status == .unsupported {
                return .success(
                    MockMouthSequence.frames(),
                    warning: "No TrueDepth camera. Using simulated frames so the screens can still be tested."
                )
            }
            return .failed("No mouth frames captured. Face the camera and try again.")
        }
    }

    func reset() {
        stopListening()
        phase = .idle
        capturedFrameCount = 0
    }

    private func stopListening() {
        frameCancellable?.cancel()
        frameCancellable = nil
    }
}

private final class FrameBuffer {
    var frames: [MouthFrame] = []
}

struct CaptureStatusOverlay: View {
    let phase: CapturePhase
    var frameCount: Int = 0

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .countdown(let value):
            badge(title: "\(value)", subtitle: "Mouth the phrase after the countdown")
        case .recording:
            badge(
                title: "Recording",
                subtitle: frameCount == 0 ? "Keep articulating" : "Keep articulating · \(frameCount) frames"
            )
        }
    }

    private func badge(title: String, subtitle: String) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(subtitle)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(24)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 24))
            Spacer()
        }
        .padding()
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

struct RecordButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "record.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}
