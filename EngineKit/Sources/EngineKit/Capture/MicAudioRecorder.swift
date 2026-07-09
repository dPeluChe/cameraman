//
//  MicAudioRecorder.swift
//  EngineKit
//
//  Extracted from Recorder.swift
//

import Foundation
import AVFoundation
import os.log

// MARK: - Mic Audio Recorder

/// Helper class for recording microphone audio
internal class MicAudioRecorder {
    private let outputURL: URL
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    private var isPaused = false
    private var startTime: Date?
    private let audioProcessor: AudioProcessor?
    private let audioProcessingConfig: AudioProcessingConfiguration

    /// Serial queue used to perform disk I/O off of the real-time audio tap
    /// thread. `installTap`'s callback runs on a high-priority audio thread
    /// and any blocking work there (file write, encoding) starves the audio
    /// engine and causes `HALC overload` warnings + dropped frames. We hop
    /// the buffer to this queue and write asynchronously.
    private let writeQueue = DispatchQueue(
        label: "com.projectstudio.enginekit.MicAudioRecorder.write",
        qos: .userInitiated
    )

    private let logger = Logger(subsystem: "com.projectstudio.enginekit", category: "MicAudioRecorder")

    init(outputURL: URL, audioProcessing: AudioProcessingConfiguration) {
        self.outputURL = outputURL
        self.audioProcessingConfig = audioProcessing

        if audioProcessing.noiseGateEnabled || audioProcessing.echoCancellationEnabled {
            self.audioProcessor = AudioProcessor(configuration: AudioProcessor.Configuration(
                noiseGateThreshold: audioProcessing.noiseGateThreshold,
                noiseGateAttack: 0.01,
                noiseGateRelease: 0.1,
                echoCancellationEnabled: audioProcessing.echoCancellationEnabled,
                echoCancellationLevel: audioProcessing.echoCancellationIntensity
            ))
        } else {
            self.audioProcessor = nil
        }
    }

    func startRecording() async throws {
        try await attemptStart()
    }

    private func attemptStart() async throws {
        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Validate format — invalid format (0 Hz / 0 ch) indicates audio session not ready
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            logger.warning("Mic input format invalid (sr=\(recordingFormat.sampleRate), ch=\(recordingFormat.channelCount)), retrying after delay...")
            self.audioEngine = nil
            try await Task.sleep(nanoseconds: 300_000_000) // 300ms retry

            let retryEngine = AVAudioEngine()
            self.audioEngine = retryEngine
            let retryNode = retryEngine.inputNode
            let retryFormat = retryNode.outputFormat(forBus: 0)

            guard retryFormat.sampleRate > 0, retryFormat.channelCount > 0 else {
                logger.error("Mic input format still invalid after retry — no mic available")
                throw Recorder.RecorderError.failedToStartMicCapture(
                    NSError(domain: "MicAudioRecorder", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Mic input format invalid after retry"])
                )
            }
            return try await startWithEngine(retryEngine, inputNode: retryNode, format: retryFormat)
        }

        try await startWithEngine(audioEngine, inputNode: inputNode, format: recordingFormat)
    }

    private func startWithEngine(_ audioEngine: AVAudioEngine, inputNode: AVAudioInputNode, format: AVAudioFormat) async throws {
        let settings = AudioRecorderUtilities.aacSettings(format: format)

        let audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        self.audioFile = audioFile

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self, self.isRecording, !self.isPaused else { return }

            // Copy the buffer before leaving the real-time thread — the tap
            // callback's `buffer` is owned by the audio engine and may be
            // reused before our async write completes.
            guard let bufferCopy = AudioRecorderUtilities.copyBuffer(buffer) else { return }
            let processed = self.audioProcessor?.process(buffer: bufferCopy) ?? bufferCopy

            // Hop disk I/O to a serial background queue. Keeps the audio
            // tap callback bounded and prevents starving the audio engine.
            self.writeQueue.async { [weak self] in
                guard let self = self, let audioFile = self.audioFile else { return }
                do {
                    try audioFile.write(from: processed)
                } catch {
                    self.logger.error("Error writing audio buffer: \(error.localizedDescription)")
                }
            }
        }

        try audioEngine.start()
        self.isRecording = true
        self.startTime = Date()
        logger.debug("Mic recording started (sr=\(format.sampleRate), ch=\(format.channelCount))")
    }

    func stopRecording() async throws -> URL {
        guard isRecording else {
            throw Recorder.RecorderError.recordingNotStarted
        }

        // Stop the engine first so no new buffers arrive on the tap callback.
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        isRecording = false
        audioEngine = nil

        // Drain any in-flight writes queued from the tap callback before we
        // return — otherwise the caller may try to read a truncated file.
        writeQueue.sync { }

        return outputURL
    }

    func pauseRecording() async throws {
        guard isRecording, !isPaused else {
            throw Recorder.RecorderError.recordingNotStarted
        }
        isPaused = true
    }

    func resumeRecording() async throws {
        guard isRecording, isPaused else {
            throw Recorder.RecorderError.recordingNotStarted
        }
        isPaused = false
    }
}
