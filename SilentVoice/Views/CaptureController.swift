import Combine
import Foundation
import SwiftUI

enum CapturePhase: Equatable {
    case idle
    case countdown(Int)
    case recording
    case saving

    var isBusy: Bool {
        self != .idle
    }
}

@MainActor
final class CaptureController: ObservableObject {
    @Published private(set) var phase: CapturePhase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    private var stopRequested = false

    func stopSentence() {
        if phase == .recording { stopRequested = true }
    }

    func captureSentence(tracker: FaceTracker) async throws -> CapturedTake {
        guard !phase.isBusy else { throw TrueDepthRecording.RecordingError.invalid("A recording is already active.") }
        defer { phase = .idle }
        elapsed = 0
        stopRequested = false
        for remaining in stride(from: 3, through: 1, by: -1) {
            phase = .countdown(remaining)
            try await Task.sleep(for: .seconds(1))
        }
        try Task.checkCancellation()
        try tracker.beginRecording(label: "UNLABELED", requiresFace: true)
        phase = .recording
        let started = ContinuousClock.now
        do {
            while !stopRequested && elapsed < 10 {
                try await Task.sleep(for: .milliseconds(50))
                let duration = started.duration(to: .now).components
                elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            }
            phase = .saving
            let result = try await tracker.finishTake()
            try Task.checkCancellation()
            return result
        } catch {
            if phase == .recording { _ = try? await tracker.finishTake(cancelled: true) }
            throw error
        }
    }

    func capture(
        tracker: FaceTracker,
        label: String,
        datasetSplit: String = "unassigned",
        countdownSeconds: Int = 3,
        recordingDuration: TimeInterval = 1.5
    ) async throws -> MouthSample {
        defer { phase = .idle }
        for remaining in stride(from: countdownSeconds, through: 1, by: -1) {
            phase = .countdown(remaining)
            try await Task.sleep(for: .seconds(1))
        }

        try Task.checkCancellation()
        try tracker.beginRecording(label: label, datasetSplit: datasetSplit)
        phase = .recording
        do {
            try await Task.sleep(for: .seconds(recordingDuration))
        } catch {
            _ = try? await tracker.finishRecording(cancelled: true)
            throw error
        }

        phase = .saving
        let sample = try await tracker.finishRecording()
        try Task.checkCancellation()
        return sample
    }

    func reset() {
        phase = .idle
    }
}

struct CaptureStatusOverlay: View {
    let phase: CapturePhase
    var sentence = false

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .countdown(let value):
            overlay(title: "\(value)", subtitle: sentence ? "Mouth a sentence after the countdown" : "Mouth the word after the countdown")
        case .recording:
            if !sentence { overlay(title: "Recording", subtitle: "Keep articulating") }
        case .saving:
            overlay(title: "Saving", subtitle: "Finishing your recording")
        }
    }

    private func overlay(title: String, subtitle: String) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
        .allowsHitTesting(false) // Keep the preview's face overlay toggle usable during capture.
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
