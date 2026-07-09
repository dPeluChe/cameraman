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

    var editor: ProjectEditor?
    var playerViewModel: PreviewPlayerViewModel?
    var projectDirectory: URL?

    /// Start recording. Audio is saved to the project's assets/voiceovers/ directory.
    func startRecording() async {
        guard !isRecording else { return }
        guard let projectDir = projectDirectory else {
            errorMessage = "No project directory available"
            return
        }

        let permission = await PermissionManager.shared.requestMicrophonePermission()
        guard permission == .authorized else {
            errorMessage = "Microphone permission required. Enable it in System Settings > Privacy > Microphone."
            return
        }

        let voiceoverDir = projectDir.appendingPathComponent("assets/voiceovers")
        try? FileManager.default.createDirectory(at: voiceoverDir, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let url = voiceoverDir.appendingPathComponent("voiceover_\(timestamp).m4a")
        outputFileURL = url

        do {
            try await recorder.startRecording(to: url)
            isRecording = true
            elapsedTime = 0
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
            outputFileURL = nil
        }
    }

    /// Stop recording and insert the clip at the given timeline position.
    func stopRecording(at timelinePosition: TimeInterval) async {
        guard isRecording else { return }
        stopTimer()

        do {
            let result = try await recorder.stopRecording()
            isRecording = false

            guard let editor = editor else { return }
            let relativePath = "assets/voiceovers/\(result.url.lastPathComponent)"

            // Get actual duration from the audio file for accuracy
            let asset = AVAsset(url: result.url)
            let duration = try? await asset.load(.duration)
            let actualDuration = duration.map { CMTimeGetSeconds($0) } ?? result.duration

            _ = await editor.addVoiceoverClip(
                path: relativePath,
                duration: actualDuration,
                at: timelinePosition
            )
            await playerViewModel?.refreshPreview(with: editor.project)
        } catch {
            errorMessage = error.localizedDescription
            isRecording = false
        }

        outputFileURL = nil
    }

    /// Cancel recording and discard the file.
    func cancelRecording() async {
        guard isRecording else { return }
        stopTimer()
        await recorder.cancelRecording()
        isRecording = false
        elapsedTime = 0
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
}
