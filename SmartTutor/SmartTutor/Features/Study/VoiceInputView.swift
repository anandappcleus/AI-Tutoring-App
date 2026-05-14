//
//  VoiceInputView.swift
//  SmartTutor
//
//  Sprint 6 — Bottom-sheet voice input using AVFoundation + Sarvam Saaras v2 STT.
//
//  Flow:
//    1. User taps mic button in StudyView → this sheet appears.
//    2. User taps "Start Recording" → AVAudioRecorder captures 16 kHz mono WAV.
//    3. User taps "Stop" → audio sent to SarvamSpeechClient.transcribe().
//    4. Transcript shown; user taps "Use This" → onTranscribe callback fires, sheet dismisses.
//
//  Usage:
//    .sheet(isPresented: $showVoiceInput) {
//        VoiceInputView(languageCode: profile.language) { text in
//            inputText = text
//        }
//    }
//

import AVFoundation
import Combine
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "VoiceInputView")

// MARK: - Recorder State

enum RecorderState: Equatable {
    case idle
    case recording
    case processing
    case done(String)    // transcript
    case failed(String)  // error message
}

// MARK: - Recorder Manager

@MainActor
final class VoiceRecorderManager: NSObject, ObservableObject {

    @Published private(set) var state: RecorderState = .idle

    private var recorder: AVAudioRecorder?
    private var audioFileURL: URL?

    private let sarvam: SarvamSpeechClient
    private let languageCode: String

    init(languageCode: String, sarvam: SarvamSpeechClient = .shared) {
        self.languageCode = languageCode
        self.sarvam = sarvam
    }

    // MARK: Start recording

    func startRecording() async {
        let granted = await requestMicrophonePermission()
        guard granted else {
            state = .failed("Microphone access denied. Enable it in Settings → Privacy → Microphone.")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("smarttutor_voice_\(UUID().uuidString).wav")
            audioFileURL = url

            let settings: [String: Any] = [
                AVFormatIDKey:             Int(kAudioFormatLinearPCM),
                AVSampleRateKey:           16_000,
                AVNumberOfChannelsKey:     1,
                AVLinearPCMBitDepthKey:    16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey:     false,
            ]

            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.record()
            state = .recording
            logger.info("Recording started  file=\(url.lastPathComponent)")
        } catch {
            state = .failed("Could not start recording: \(error.localizedDescription)")
        }
    }

    // MARK: Stop + transcribe

    func stopAndTranscribe() async {
        recorder?.stop()
        recorder = nil

        guard let url = audioFileURL else {
            state = .failed("No audio file found.")
            return
        }

        state = .processing

        do {
            let text = try await sarvam.transcribe(audioURL: url, languageCode: languageCode)
            state = .done(text)
            logger.info("Transcription ok  preview=\(text.prefix(60))")
        } catch {
            state = .failed(error.localizedDescription)
            logger.error("Transcription failed  \(error.localizedDescription)")
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: url)
        audioFileURL = nil
    }

    func reset() {
        recorder?.stop()
        recorder = nil
        if let url = audioFileURL { try? FileManager.default.removeItem(at: url) }
        audioFileURL = nil
        state = .idle
    }

    // MARK: Microphone permission

    private func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission {
                    cont.resume(returning: $0)
                }
            }
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension VoiceRecorderManager: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.state = .failed("Recording error: \(error?.localizedDescription ?? "unknown")")
        }
    }
}

// MARK: - View

struct VoiceInputView: View {
    let languageCode: String
    let onTranscribe: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager: VoiceRecorderManager

    /// Drives the pulse ring animation while recording.
    @State private var isPulsing = false

    init(languageCode: String = "en-IN", onTranscribe: @escaping (String) -> Void) {
        self.languageCode = languageCode
        self.onTranscribe = onTranscribe
        _manager = StateObject(wrappedValue: VoiceRecorderManager(languageCode: languageCode))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color(UIColor.systemGray4))
                .frame(width: 40, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 28)

            micIcon
                .padding(.bottom, 20)

            statusLabel
                .padding(.bottom, 32)

            actionButton

            if case .done(let text) = manager.state {
                useButton(text)
                    .padding(.top, 12)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .presentationDetents([.fraction(0.48)])
        .presentationDragIndicator(.hidden)
        .onChange(of: manager.state) { _, newState in
            isPulsing = (newState == .recording)
        }
        .onDisappear {
            manager.reset()
        }
    }

    // MARK: - Mic Icon with pulse ring

    private var micIcon: some View {
        ZStack {
            // Pulse ring — only visible while recording
            if manager.state == .recording {
                Circle()
                    .stroke(Color.red.opacity(0.3), lineWidth: 6)
                    .frame(width: isPulsing ? 116 : 96, height: isPulsing ? 116 : 96)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: isPulsing)
            }

            Circle()
                .fill(iconBackground)
                .frame(width: 96, height: 96)

            Image(systemName: iconName)
                .font(.system(size: 40))
                .foregroundColor(iconForeground)
        }
        .frame(width: 120, height: 120)
    }

    // MARK: - Status label

    private var statusLabel: some View {
        Text(labelText)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(manager.state == .failed("") ? .orange : .primary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(3)
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        switch manager.state {
        case .idle:
            Button("Start Recording") {
                Task { await manager.startRecording() }
            }
            .buttonStyle(VoiceButtonStyle(color: .indigo))

        case .recording:
            Button("Stop Recording") {
                Task { await manager.stopAndTranscribe() }
            }
            .buttonStyle(VoiceButtonStyle(color: .red))

        case .processing:
            HStack(spacing: 10) {
                ProgressView()
                Text("Transcribing…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
            }

        case .done:
            Button("Record Again") {
                manager.reset()
                Task { await manager.startRecording() }
            }
            .buttonStyle(VoiceButtonStyle(color: .indigo))

        case .failed:
            Button("Try Again") {
                manager.reset()
                Task { await manager.startRecording() }
            }
            .buttonStyle(VoiceButtonStyle(color: .orange))
        }
    }

    private func useButton(_ text: String) -> some View {
        Button("Use This") {
            onTranscribe(text)
            dismiss()
        }
        .buttonStyle(VoiceButtonStyle(color: .green))
    }

    // MARK: - Derived helpers

    private var labelText: String {
        switch manager.state {
        case .idle:
            return "Tap to ask your question aloud\nin Bengali, Hindi or English"
        case .recording:
            return "Listening… speak now"
        case .processing:
            return ""
        case .done(let text):
            let preview = text.count > 100 ? String(text.prefix(100)) + "…" : text
            return "\u{201C}\(preview)\u{201D}"
        case .failed(let msg):
            return msg
        }
    }

    private var iconName: String {
        switch manager.state {
        case .idle:       return "mic.circle.fill"
        case .recording:  return "waveform.circle.fill"
        case .processing: return "arrow.triangle.2.circlepath.circle.fill"
        case .done:       return "checkmark.circle.fill"
        case .failed:     return "exclamationmark.circle.fill"
        }
    }

    private var iconBackground: Color {
        switch manager.state {
        case .idle:       return Color.indigo.opacity(0.12)
        case .recording:  return Color.red.opacity(0.12)
        case .processing: return Color.orange.opacity(0.12)
        case .done:       return Color.green.opacity(0.12)
        case .failed:     return Color.orange.opacity(0.12)
        }
    }

    private var iconForeground: Color {
        switch manager.state {
        case .idle:       return .indigo
        case .recording:  return .red
        case .processing: return .orange
        case .done:       return .green
        case .failed:     return .orange
        }
    }
}

// MARK: - Button Style

private struct VoiceButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 36)
            .padding(.vertical, 14)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1.0))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
