//
//  VoiceoverRecordingViewModel.swift
//  App
//
//  Manages standalone voiceover recording: start/stop/cancel,
//  elapsed timer, and clip insertion into the timeline.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import EngineKit

@MainActor
final class VoiceoverRecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var errorMessage: String?

    private let recorder = VoiceoverRecorder()
    private var timer: Timer?
    private var outputFileURL: URL?
    private var recordingRequestID: UUID?

    var editor: ProjectEditor?
    var playerViewModel: PreviewPlayerViewModel?
    var projectDirectory: URL?

    /// Start recording. Audio is saved to the project's assets/voiceovers/ directory.
    func startRecording() async {
        guard !isRecording else { return }
        errorMessage = nil
        guard let projectDir = projectDirectory else {
            errorMessage = "No project directory available"
            return
        }

        let requestID = UUID()
        recordingRequestID = requestID
        let permission = await PermissionManager.shared.requestMicrophonePermission()
        guard recordingRequestID == requestID else { return }
        guard permission == .authorized else {
            recordingRequestID = nil
            errorMessage = "Microphone permission required. Enable it in System Settings > Privacy > Microphone."
            return
        }

        do {
            let voiceoverDir = projectDir.appendingPathComponent("assets/voiceovers")
            try FileManager.default.createDirectory(at: voiceoverDir, withIntermediateDirectories: true)
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let url = voiceoverDir.appendingPathComponent("voiceover_\(timestamp).m4a")
            outputFileURL = url
            try await recorder.startRecording(to: url)
            guard recordingRequestID == requestID else {
                await recorder.cancelRecording()
                removeOutputFile()
                outputFileURL = nil
                return
            }
            recordingRequestID = nil
            isRecording = true
            elapsedTime = 0
            startTimer()
        } catch {
            guard recordingRequestID == requestID else { return }
            recordingRequestID = nil
            errorMessage = error.localizedDescription
            removeOutputFile()
            outputFileURL = nil
        }
    }

    /// Stop recording and insert the clip at the given timeline position.
    @discardableResult
    func stopRecording(at timelinePosition: TimeInterval) async -> Bool {
        guard isRecording else { return false }
        stopTimer()

        do {
            let result = try await recorder.stopRecording()
            isRecording = false

            guard let editor else {
                throw VoiceoverInsertionError.editorUnavailable
            }
            let relativePath = "assets/voiceovers/\(result.url.lastPathComponent)"

            // Get actual duration from the audio file for accuracy
            let asset = AVAsset(url: result.url)
            let duration = try? await asset.load(.duration)
            let actualDuration = duration.map { CMTimeGetSeconds($0) } ?? result.duration

            guard await editor.addVoiceoverClip(
                path: relativePath,
                duration: actualDuration,
                at: timelinePosition
            ) != nil else {
                throw VoiceoverInsertionError.clipInsertionFailed
            }
            playerViewModel?.refreshPreview(with: editor.project)
            outputFileURL = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            isRecording = false
            removeOutputFile()
            outputFileURL = nil
            return false
        }
    }

    /// Cancel recording and discard the file.
    func cancelRecording() async {
        recordingRequestID = nil
        stopTimer()
        await recorder.cancelRecording()
        removeOutputFile()
        isRecording = false
        elapsedTime = 0
        errorMessage = nil
        outputFileURL = nil
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedTime = await self?.recorder.elapsed() ?? 0
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    var formattedElapsedTime: String {
        let total = elapsedTime
        let mins = Int(total) / 60
        let secs = total.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%05.2f", mins, secs)
    }

    private func removeOutputFile() {
        guard let outputFileURL else { return }
        try? FileManager.default.removeItem(at: outputFileURL)
    }
}

private enum VoiceoverInsertionError: LocalizedError {
    case editorUnavailable
    case clipInsertionFailed

    var errorDescription: String? {
        switch self {
        case .editorUnavailable:
            return "The recording could not be added because the editor is unavailable."
        case .clipInsertionFailed:
            return "The recording was created but could not be inserted into the timeline."
        }
    }
}
