//
//  AudioDriftDetector.swift
//  EngineKit
//
//  Compares audio and video track durations to detect sync drift.
//  Used during export to warn if drift exceeds threshold.
//

import AVFoundation
import Foundation
import os.log

public struct AudioDriftDetector {

    public struct DriftReport: Sendable {
        public let videoDuration: TimeInterval
        public let systemAudioDuration: TimeInterval?
        public let micAudioDuration: TimeInterval?
        public let systemAudioDriftMs: Double?
        public let micAudioDriftMs: Double?
        public let hasSignificantDrift: Bool

        public var summary: String {
            var lines: [String] = ["Video: \(String(format: "%.3f", videoDuration))s"]
            if let sys = systemAudioDuration, let drift = systemAudioDriftMs {
                lines.append("System audio: \(String(format: "%.3f", sys))s (drift: \(String(format: "%.1f", drift))ms)")
            }
            if let mic = micAudioDuration, let drift = micAudioDriftMs {
                lines.append("Mic audio: \(String(format: "%.3f", mic))s (drift: \(String(format: "%.1f", drift))ms)")
            }
            if hasSignificantDrift {
                lines.append("WARNING: Drift exceeds threshold")
            }
            return lines.joined(separator: "\n")
        }
    }

    private static let logger = Logger(subsystem: "com.projectstudio.enginekit", category: "AudioDriftDetector")

    /// Detect audio-video drift from source files in a project directory.
    /// - Parameters:
    ///   - project: Project with source paths
    ///   - projectDirectory: Base directory for resolving paths
    ///   - thresholdMs: Drift threshold in milliseconds (default 100ms)
    /// - Returns: DriftReport with durations and drift values
    public static func detect(
        project: Project,
        projectDirectory: URL,
        thresholdMs: Double = 100
    ) async -> DriftReport {
        guard let sources = project.primarySources else {
            return DriftReport(
                videoDuration: 0, systemAudioDuration: nil, micAudioDuration: nil,
                systemAudioDriftMs: nil, micAudioDriftMs: nil, hasSignificantDrift: false
            )
        }

        let screenURL = projectDirectory.appendingPathComponent(sources.screen.path)
        let videoDuration = await loadDuration(url: screenURL)

        var sysAudioDuration: TimeInterval?
        var micAudioDuration: TimeInterval?

        if let sysPath = sources.audio?.system?.path {
            sysAudioDuration = await loadDuration(url: projectDirectory.appendingPathComponent(sysPath))
        }
        if let micPath = sources.audio?.mic?.path {
            micAudioDuration = await loadDuration(url: projectDirectory.appendingPathComponent(micPath))
        }

        let sysDriftMs = sysAudioDuration.map { ($0 - videoDuration) * 1000 }
        let micDriftMs = micAudioDuration.map { ($0 - videoDuration) * 1000 }

        let hasSignificant = [sysDriftMs, micDriftMs].compactMap { $0 }.contains(where: { abs($0) > thresholdMs })

        if hasSignificant {
            logger.warning("Audio drift detected: sys=\(sysDriftMs.map { String(format: "%.1f", $0) } ?? "n/a")ms, mic=\(micDriftMs.map { String(format: "%.1f", $0) } ?? "n/a")ms")
        }

        return DriftReport(
            videoDuration: videoDuration,
            systemAudioDuration: sysAudioDuration,
            micAudioDuration: micAudioDuration,
            systemAudioDriftMs: sysDriftMs,
            micAudioDriftMs: micDriftMs,
            hasSignificantDrift: hasSignificant
        )
    }

    private static func loadDuration(url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        return (try? await asset.load(.duration).seconds) ?? 0
    }
}
