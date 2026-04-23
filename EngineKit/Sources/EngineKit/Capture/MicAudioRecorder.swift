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
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: format.channelCount,
            AVSampleRateKey: format.sampleRate,
            AVEncoderBitRateKey: 128000
        ]

        let audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        self.audioFile = audioFile

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self, self.isRecording, !self.isPaused else { return }
            do {
                guard let audioFile = self.audioFile else { return }
                if let processor = self.audioProcessor, let processedBuffer = processor.process(buffer: buffer) {
                    try audioFile.write(from: processedBuffer)
                } else {
                    try audioFile.write(from: buffer)
                }
            } catch {
                self.logger.error("Error writing audio buffer: \(error.localizedDescription)")
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

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        isRecording = false
        audioEngine = nil

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
