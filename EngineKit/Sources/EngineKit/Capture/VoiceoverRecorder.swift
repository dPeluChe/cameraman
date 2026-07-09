//
//  VoiceoverRecorder.swift
//  EngineKit
//
//  Standalone microphone recorder for voiceover narration.
//  Records to a project's assets directory and returns an AudioClipRef
//  ready to insert on a timeline audio track.
//

import Foundation
import AVFoundation

/// Result of a voiceover recording session.
public struct VoiceoverResult: Sendable {
    public let url: URL
    public let relativePath: String
    public let duration: TimeInterval
}

/// Records microphone audio to a file for voiceover narration.
/// Uses AVAudioEngine + AVAudioFile (same pipeline as MicAudioRecorder
/// but simplified — no noise gate / echo cancellation needed for
/// standalone narration).
public actor VoiceoverRecorder {

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    private var startTime: Date?

    private let writeQueue = DispatchQueue(
        label: "com.projectstudio.enginekit.VoiceoverRecorder.write",
        qos: .userInitiated
    )

    public init() {}

    public var currentlyRecording: Bool { isRecording }

    /// Start recording to the given output URL.
    public func startRecording(to outputURL: URL) async throws {
        guard !isRecording else { return }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            self.audioEngine = nil
            throw VoiceoverError.noMicrophoneAvailable
        }

        let settings = AudioRecorderUtilities.aacSettings(format: format)

        let file = try AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        self.audioFile = file

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self, self.isRecording else { return }
            guard let copy = AudioRecorderUtilities.copyBuffer(buffer) else { return }
            self.writeQueue.async { [weak self] in
                guard let self = self, let file = self.audioFile else { return }
                try? file.write(from: copy)
            }
        }

        try engine.start()
        isRecording = true
        startTime = Date()
    }

    /// Stop recording and return the file URL + duration.
    public func stopRecording() async throws -> VoiceoverResult {
        guard isRecording, let url = audioFile?.url else {
            throw VoiceoverError.notRecording
        }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        isRecording = false
        audioEngine = nil
        audioFile = nil

        writeQueue.sync { }

        let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0
        startTime = nil

        return VoiceoverResult(url: url, relativePath: "", duration: elapsed)
    }

    /// Cancel recording and delete the partial file.
    public func cancelRecording() async {
        guard isRecording else { return }
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        isRecording = false
        audioEngine = nil
        let url = audioFile?.url
        audioFile = nil
        writeQueue.sync { }
        if let url { try? FileManager.default.removeItem(at: url) }
        startTime = nil
    }

    public func elapsed() -> TimeInterval {
        guard isRecording, let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
}

public enum VoiceoverError: Error, LocalizedError {
    case noMicrophoneAvailable
    case notRecording

    public var errorDescription: String? {
        switch self {
        case .noMicrophoneAvailable: return "No microphone input available"
        case .notRecording: return "No recording in progress"
        }
    }
}
