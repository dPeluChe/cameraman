//
//  EngineKit.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation

/// EngineKit is the core module for Project Studio.
/// It provides all recording, editing, and export functionality.
///
/// Architecture:
/// - CaptureEngine: Screen + Audio capture
/// - CameraEngine: Camera capture
/// - TelemetryRecorder: Cursor/click tracking
/// - ProjectStore: Project persistence
/// - PreviewEngine: Non-destructive playback
/// - ExportEngine: Async export jobs
/// - TranscriptionEngine: Offline STT via Whisper.cpp
/// - OverlayEngine: Vector overlay rendering
/// - JobQueue: Job management with progress/cancellation
///
@_exported import struct Foundation.UUID

/// Main EngineKit namespace
public enum EngineKit {
    /// Version information
    public static let version = "0.1.0"
    /// Build information
    public static let build = "1"
}

// MARK: - Common Types

/// Unique identifier for projects
public typealias ProjectId = UUID

/// Unique identifier for jobs
public typealias JobId = UUID

/// Unique identifier for recording sessions
public typealias RecordingSessionId = UUID

/// Result of a recording session
public struct RecordingResult {
    /// Path to the screen recording
    public let screenPath: URL
    /// Path to the camera recording (if available)
    public let cameraPath: URL?
    /// Path to system audio (if available)
    public let systemAudioPath: URL?
    /// Path to microphone audio (if available)
    public let micAudioPath: URL?
    /// Path to telemetry data
    public let telemetryPath: URL
    /// Duration of the recording
    public let duration: TimeInterval
    /// Timestamp of recording start
    public let startTime: Date
    /// Timestamp of recording end
    public let endTime: Date
}

/// Status of a job
public enum JobStatus: Equatable {
    case queued
    case running(progress: Double)
    case success
    case failed
    case canceled
}

/// Error types for EngineKit
public enum EngineKitError: Error, LocalizedError {
    case projectNotFound(ProjectId)
    case sourceFileMissing(path: String)
    case sourceFileCorrupted(path: String)
    case insufficientDiskSpace(requiredBytes: UInt64, availableBytes: UInt64)
    case transcriptionFailed(underlying: Error?)
    case exportEncodingError(underlying: Error)
    case audioSyncDrift(detectedMs: Int, atTimestamp: TimeInterval)
    case invalidConfiguration(String)
    case permissionDenied(String)
    case operationCanceled

    public var errorDescription: String? {
        switch self {
        case .projectNotFound(let id):
            return "Project not found: \(id.uuidString)"
        case .sourceFileMissing(let path):
            return "Source file missing: \(path)"
        case .sourceFileCorrupted(let path):
            return "Source file corrupted: \(path)"
        case .insufficientDiskSpace(let required, let available):
            return "Insufficient disk space. Required: \(required) bytes, Available: \(available) bytes"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error?.localizedDescription ?? "Unknown error")"
        case .exportEncodingError(let error):
            return "Export encoding error: \(error.localizedDescription)"
        case .audioSyncDrift(let drift, let timestamp):
            return "Audio drift detected: \(drift)ms at \(timestamp)s"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .permissionDenied(let resource):
            return "Permission denied: \(resource)"
        case .operationCanceled:
            return "Operation canceled"
        }
    }
}
