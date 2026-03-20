//
//  LoggingSystemTypes.swift
//  EngineKit
//
//  Extracted from LoggingSystem.swift — types, enums, and global convenience functions
//

import Foundation
import os.log

extension LoggingSystem {
    /// Log levels following OSLog conventions
    public enum Level: Int, Sendable {
        case debug = 0
        case info = 1
        case notice = 2
        case warning = 3
        case error = 4
        case fault = 5

        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .notice: return .default
            case .warning: return .default
            case .error: return .error
            case .fault: return .fault
            }
        }
    }

    /// Log categories for different components
    public enum Category: String, Sendable {
        case general = "General"
        case capture = "Capture"
        case export = "Export"
        case preview = "Preview"
        case projectStore = "ProjectStore"
        case projectLibrary = "ProjectLibrary"
        case transcription = "Transcription"
        case telemetry = "Telemetry"
        case overlay = "Overlay"
        case editor = "Editor"
        case ai = "AI"
        case jobQueue = "JobQueue"
        case crashReporter = "CrashReporter"
        case ui = "UI"
        case performance = "Performance"
    }

    /// Log entry structure for programmatic access
    public struct LogEntry: Codable, Sendable {
        public let timestamp: Date
        public let level: Level
        public let category: Category
        public let message: String
        public let metadata: [String: String]?

        public init(
            timestamp: Date,
            level: Level,
            category: Category,
            message: String,
            metadata: [String: String]? = nil
        ) {
            self.timestamp = timestamp
            self.level = level
            self.category = category
            self.message = message
            self.metadata = metadata
        }

        enum CodingKeys: String, CodingKey {
            case timestamp
            case level
            case category
            case message
            case metadata
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            timestamp = try container.decode(Date.self, forKey: .timestamp)
            let levelRaw = try container.decode(Int.self, forKey: .level)
            level = Level(rawValue: levelRaw) ?? .info
            let categoryRaw = try container.decode(String.self, forKey: .category)
            category = Category(rawValue: categoryRaw) ?? .general
            message = try container.decode(String.self, forKey: .message)
            metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(level.rawValue, forKey: .level)
            try container.encode(category.rawValue, forKey: .category)
            try container.encode(message, forKey: .message)
            try container.encodeIfPresent(metadata, forKey: .metadata)
        }
    }
}

// MARK: - Category Conformance

extension LoggingSystem.Category: CaseIterable {
    public static var allCases: [LoggingSystem.Category] = [
        .general, .capture, .export, .preview, .projectStore,
        .projectLibrary, .transcription, .telemetry, .overlay,
        .editor, .ai, .jobQueue, .crashReporter, .ui, .performance
    ]
}

// MARK: - Global Convenience Functions

/// Log a debug message
public func LogDebug(
    _ category: LoggingSystem.Category,
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task {
        await LoggingSystem.shared.debug(
            category: category,
            message,
            file: file,
            function: function,
            line: line
        )
    }
}

/// Log an info message
public func LogInfo(
    _ category: LoggingSystem.Category,
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task {
        await LoggingSystem.shared.info(
            category: category,
            message,
            file: file,
            function: function,
            line: line
        )
    }
}

/// Log a notice message
public func LogNotice(
    _ category: LoggingSystem.Category,
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task {
        await LoggingSystem.shared.notice(
            category: category,
            message,
            file: file,
            function: function,
            line: line
        )
    }
}

/// Log a warning message
public func LogWarning(
    _ category: LoggingSystem.Category,
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task {
        await LoggingSystem.shared.warning(
            category: category,
            message,
            file: file,
            function: function,
            line: line
        )
    }
}

/// Log an error message
public func LogError(
    _ category: LoggingSystem.Category,
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task {
        await LoggingSystem.shared.error(
            category: category,
            message,
            file: file,
            function: function,
            line: line
        )
    }
}

/// Log a fault message
public func LogFault(
    _ category: LoggingSystem.Category,
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Task {
        await LoggingSystem.shared.fault(
            category: category,
            message,
            file: file,
            function: function,
            line: line
        )
    }
}
