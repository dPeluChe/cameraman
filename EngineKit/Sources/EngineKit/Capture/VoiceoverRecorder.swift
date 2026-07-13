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
    private var writer: VoiceoverAudioWriter?
    private var outputURL: URL?
    private var isRecording = false
    private var startTime: Date?

    public init() {}

    public var currentlyRecording: Bool { isRecording }

    /// Start recording to the given output URL.
    public func startRecording(to outputURL: URL) async throws {
        guard !isRecording else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw VoiceoverError.noMicrophoneAvailable
        }

        let settings = AudioRecorderUtilities.aacSettings(format: format)

        let file = try AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let writer = VoiceoverAudioWriter(file: file)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            writer.enqueue(buffer)
        }

        do {
            try engine.start()
            audioEngine = engine
            self.writer = writer
            self.outputURL = outputURL
            isRecording = true
            startTime = Date()
        } catch {
            inputNode.removeTap(onBus: 0)
            try? await writer.finish()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    /// Stop recording and return the file URL + duration.
    public func stopRecording() async throws -> VoiceoverResult {
        guard isRecording, let engine = audioEngine,
              let writer, let url = outputURL else {
            throw VoiceoverError.notRecording
        }

        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        audioEngine = nil

        let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0
        startTime = nil
        self.writer = nil
        outputURL = nil

        try await writer.finish()

        return VoiceoverResult(url: url, relativePath: "", duration: elapsed)
    }

    /// Cancel recording and delete the partial file.
    public func cancelRecording() async {
        guard isRecording else { return }
        let engine = audioEngine
        let writer = writer
        let url = outputURL
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        isRecording = false
        audioEngine = nil
        self.writer = nil
        outputURL = nil
        try? await writer?.finish()
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
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noMicrophoneAvailable: return "No microphone input available"
        case .notRecording: return "No recording in progress"
        case .writeFailed(let message): return "Voiceover write failed: \(message)"
        }
    }
}

final class VoiceoverAudioWriter: @unchecked Sendable {
    private var file: AVAudioFile?
    private let queue = DispatchQueue(
        label: "com.projectstudio.enginekit.VoiceoverRecorder.write",
        qos: .userInitiated
    )
    private let stateLock = NSLock()
    private var acceptingBuffers = true
    private var writeError: String?

    init(file: AVAudioFile) {
        self.file = file
    }

    func enqueue(_ buffer: AVAudioPCMBuffer) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard acceptingBuffers,
              let copy = AudioRecorderUtilities.copyBuffer(buffer) else { return }

        queue.async { [self] in
            guard let file else { return }
            do {
                try file.write(from: copy)
            } catch {
                if writeError == nil { writeError = error.localizedDescription }
            }
        }
    }

    func finish() async throws {
        let error = await withCheckedContinuation { continuation in
            stateLock.lock()
            acceptingBuffers = false
            queue.async { [self] in
                file = nil
                continuation.resume(returning: writeError)
            }
            stateLock.unlock()
        }
        if let error { throw VoiceoverError.writeFailed(error) }
    }
}
