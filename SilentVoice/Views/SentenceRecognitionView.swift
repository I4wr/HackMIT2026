import SwiftUI

struct RecognitionModesView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @AppStorage("SilentVoice.recognitionMode") private var mode = "Sentences"

    var body: some View {
        VStack(spacing: 0) {
            Picker("Recognition mode", selection: $mode) {
                Text("Sentences").tag("Sentences")
                Text("Commands").tag("Commands")
            }
            .pickerStyle(.segmented)
            .padding()
            if mode == "Commands" {
                RecognitionView()
            } else {
                SentenceRecognitionView(sentences: viewModel.sentences) { mode = "Commands" }
            }
        }
    }
}

struct SentenceRecognitionView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject var sentences: SentenceRecognition
    let switchToCommands: () -> Void
    @StateObject private var capture = CaptureController()
    @State private var captureTask: Task<Void, Never>?
    @State private var captureError: String?
    @AppStorage("SilentVoice.macHost") private var host = ""
    @AppStorage("SilentVoice.macPort") private var port = "8000"

    private var busy: Bool { capture.phase.isBusy || sentences.isBusy }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Mouth a short English sentence, then review the transcript before speaking.")
                    .foregroundStyle(.secondary)
                FaceCameraView()
                    .frame(height: 280)
                    .overlay { CaptureStatusOverlay(phase: capture.phase, sentence: true) }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                if capture.phase == .recording {
                    Text(String(format: "Recording · %.1f / 10 seconds", min(10, capture.elapsed)))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.red)
                }
                if sentences.isBusy {
                    HStack { ProgressView(); Text(sentences.phase.rawValue) }
                }
                if sentences.result != nil {
                    Text("Review transcript").font(.headline)
                    TextEditor(text: $sentences.text)
                        .frame(minHeight: 120)
                        .padding(8)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.3)))
                        .accessibilityLabel("Editable transcript")
                    Text("Experimental lip-reading can make mistakes. Speak reads your edited text.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = captureError ?? sentences.error {
                    Text(error).foregroundStyle(.red)
                    if sentences.lastTake != nil {
                        Button("Retry recording") { retry() }.disabled(busy)
                    }
                    Button("Use offline Commands", action: switchToCommands)
                }
                connectionSettings
                FaceDiagnosticsView(tracker: viewModel.tracker)
            }
            .padding()
        }
        .navigationTitle("Silent sentences")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if capture.phase == .recording {
                    Button("Stop recording") { capture.stopSentence() }
                        .buttonStyle(.borderedProminent).tint(.red)
                        .disabled(capture.elapsed < 0.5)
                        .frame(maxWidth: .infinity)
                } else {
                    RecordButton(title: "Record sentence", isEnabled: !busy && !host.isEmpty) { record() }
                }
                Button {
                    sentences.speak(using: viewModel.speechOutput)
                } label: {
                    Label("Speak", systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || sentences.result == nil || sentences.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding().background(.bar)
        }
        .onAppear { viewModel.tracker.start() }
        .onDisappear {
            captureTask?.cancel()
            sentences.cancel()
            viewModel.speechOutput.stop()
            viewModel.tracker.stop()
        }
        .onChange(of: host) { _, _ in sentences.cancel() }
        .onChange(of: port) { _, _ in sentences.cancel() }
    }

    private var connectionSettings: some View {
        DisclosureGroup("Mac connection") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Mac hostname, e.g. macbook.local", text: $host)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Mac hostname")
                TextField("Port", text: $port)
                    .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Mac port")
                Button(sentences.checkingConnection ? "Connecting…" : "Test Connection") {
                    sentences.testConnection(host: host, port: Int(port) ?? 0)
                }
                .disabled(sentences.checkingConnection)
                if let message = sentences.connectionMessage { Text(message).font(.footnote) }
                Text("Run the SilentVoice server on your Mac and connect both devices to the same Wi-Fi. Face recordings are sent to that Mac for transcription.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .disabled(busy)
    }

    private func record() {
        captureTask?.cancel()
        sentences.prepareRecording()
        viewModel.speechOutput.stop()
        captureError = nil
        captureTask = Task {
            do {
                _ = try LocalTranscriptionService.baseURL(host: host, port: Int(port) ?? 0)
                let take = try await capture.captureSentence(tracker: viewModel.tracker)
                guard !Task.isCancelled else { return }
                sentences.transcribe(take, host: host, port: Int(port) ?? 0)
            } catch {
                guard !Task.isCancelled else { return }
                captureError = error.localizedDescription
            }
        }
    }

    private func retry() {
        guard let take = sentences.lastTake else { return }
        captureError = nil
        sentences.transcribe(take, host: host, port: Int(port) ?? 0)
    }
}
