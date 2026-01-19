//
//  Job.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-18.
//

import Foundation

/// Job model for async operations (export, transcribe, etc.)
public struct Job: Codable, Equatable, Identifiable {
    /// Unique identifier
    public let jobId: JobId
    /// Job type
    public let type: JobType
    /// Associated project
    public let projectId: ProjectId
    /// Current status
    public var status: JobStatus
    /// Job start time
    public let startedAt: Date
    /// Job completion time (if completed)
    public var completedAt: Date?
    /// Error information (if failed)
    public var error: JobError?

    /// Job types
    public enum JobType: String, Codable {
        case export
        case transcribe
        case proxyGeneration
        case aiSuggestion
        case aiGeneration
    }

    /// Job status with progress
    public enum JobStatus: Codable, Equatable {
        case queued
        case running(progress: Double)
        case success
        case failed
        case canceled

        /// Helper to get progress value
        public var progress: Double {
            switch self {
            case .queued: return 0.0
            case .running(let p): return p
            case .success: return 1.0
            case .failed, .canceled: return 0.0
            }
        }
    }

    /// Detailed error information
    public struct JobError: Codable, Equatable {
        public let code: String
        public let message: String
        public let details: [String: AnyCodable]?
        public let recoverable: Bool

        public init(code: String, message: String, details: [String: AnyCodable]? = nil, recoverable: Bool = false) {
            self.code = code
            self.message = message
            self.details = details
            self.recoverable = recoverable
        }
    }

    public var id: JobId {
        jobId
    }
}

/// Helper type for Codable dictionaries with Any values
public enum AnyCodable: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case dictionary([String: AnyCodable])
    case array([AnyCodable])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            self = .dictionary(dictValue)
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            self = .array(arrayValue)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

/// Error codes for jobs
public enum JobErrorCode: String {
    case audioSyncDrift = "AUDIO_SYNC_DRIFT"
    case sourceFileMissing = "SOURCE_FILE_MISSING"
    case sourceFileCorrupted = "SOURCE_FILE_CORRUPTED"
    case insufficientDiskSpace = "INSUFFICIENT_DISK_SPACE"
    case transcriptionFailed = "TRANSCRIPTION_FAILED"
    case exportEncodingError = "EXPORT_ENCODING_ERROR"
}
