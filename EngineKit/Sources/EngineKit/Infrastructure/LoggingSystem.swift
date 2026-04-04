//
//  LoggingSystem.swift
//  EngineKit
//
//  Created by Ralphy on 2026/dPeluChe
//

import Foundation
import os.log
import os.signpost

/// LoggingSystem provides centralized, structured logging across the entire EngineKit framework
/// Provides unified log levels, categories, and output formatting
public actor LoggingSystem {
    // MARK: - Properties
    
    /// Shared singleton instance
    public static let shared = LoggingSystem()
    
    /// Subsystem identifier for all logs
    private let subsystem = "com.projectstudio.enginekit"
    
    /// Minimum log level (logs below this level are not emitted)
    private(set) var minimumLevel: Level = .info
    
    /// Whether to include file and line number in logs
    private(set) var includeSourceInfo: Bool = false
    
    /// Whether to log to console (in addition to OSLog)
    private(set) var logToConsole: Bool = false
    
    /// Log buffer for programmatic access
    private var logBuffer: [LogEntry] = []
    
    /// Maximum buffer size
    private let maxBufferSize = 1000
    
    /// Logger instances for each category
    private var loggers: [Category: Logger] = [:]
    
    /// Signpost logger for performance tracing
    private let signpostLog = OSLog(
        subsystem: "com.projectstudio.enginekit",
        category: "PerformanceInstrumentation"
    )
    
    // MARK: - Initialization
    
    private init() {
        // Pre-initialize loggers for all categories
        for category in Category.allCases {
            loggers[category] = Logger(
                subsystem: subsystem,
                category: category.rawValue
            )
        }
    }
    
    // MARK: - Configuration
    
    /// Set the minimum log level
    public func setMinimumLevel(_ level: Level) {
        minimumLevel = level
        Task {
            log(level: .notice, category: .general, "Minimum log level set to \(level)")
        }
    }

    /// Enable or disable console logging
    public func setConsoleLogging(_ enabled: Bool) {
        logToConsole = enabled
        Task {
            log(level: .notice, category: .general, "Console logging \(enabled ? "enabled" : "disabled")")
        }
    }

    /// Enable or disable source info (file, line, function) in logs
    public func setSourceInfo(_ enabled: Bool) {
        includeSourceInfo = enabled
        Task {
            log(level: .notice, category: .general, "Source info \(enabled ? "enabled" : "disabled")")
        }
    }

    /// Clear the log buffer
    public func clearBuffer() {
        logBuffer.removeAll()
        Task {
            log(level: .debug, category: .general, "Log buffer cleared")
        }
    }
    
    // MARK: - Logging API
    
    /// Log a message at the specified level and category
    /// - Parameters:
    ///   - level: Log level
    ///   - category: Log category
    ///   - message: Message to log
    ///   - file: Source file (automatic)
    ///   - function: Source function (automatic)
    ///   - line: Source line (automatic)
    public func log(
        level: Level,
        category: Category,
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // Check minimum level
        guard level.rawValue >= minimumLevel.rawValue else { return }
        
        // Get logger for category
        guard let logger = loggers[category] else {
            return
        }
        
        // Format message with source info if enabled
        var formattedMessage = message
        if includeSourceInfo {
            let filename = URL(fileURLWithPath: file).lastPathComponent
            formattedMessage = "[\(filename):\(line) \(function)] \(message)"
        }
        
        // Log to OSLog
        logger.log(level: level.osLogType, "\(formattedMessage)")
        
        // Log to console if enabled
        if logToConsole {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let levelStr = "\(level)".uppercased()
            print("[\(timestamp)] [\(levelStr)] [\(category.rawValue)] \(formattedMessage)")
        }
        
        // Add to buffer
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            metadata: includeSourceInfo ? [
                "file": URL(fileURLWithPath: file).lastPathComponent,
                "function": function,
                "line": String(line)
            ] : nil
        )
        
        logBuffer.append(entry)
        
        // Trim buffer if needed
        if logBuffer.count > maxBufferSize {
            logBuffer.removeFirst(logBuffer.count - maxBufferSize)
        }
    }
    
    /// Log a debug message
    public func debug(
        category: Category,
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, category: category, message, file: file, function: function, line: line)
    }
    
    /// Log an info message
    public func info(
        category: Category,
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, category: category, message, file: file, function: function, line: line)
    }
    
    /// Log a notice message
    public func notice(
        category: Category,
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .notice, category: category, message, file: file, function: function, line: line)
    }
    
    /// Log a warning message
    public func warning(
        category: Category,
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, category: category, message, file: file, function: function, line: line)
    }
    
    /// Log an error message
    public func error(
        category: Category,
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .error, category: category, message, file: file, function: function, line: line)
    }
    
    /// Log a fault message
    public func fault(
        category: Category,
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .fault, category: category, message, file: file, function: function, line: line)
    }
    
    // MARK: - Programmatic Access
    
    /// Get all log entries from the buffer
    public func getLogs() -> [LogEntry] {
        return logBuffer
    }
    
    /// Get log entries filtered by category
    public func getLogs(category: Category) -> [LogEntry] {
        return logBuffer.filter { $0.category == category }
    }
    
    /// Get log entries filtered by level
    public func getLogs(level: Level) -> [LogEntry] {
        return logBuffer.filter { $0.level == level }
    }
    
    /// Get recent log entries
    /// - Parameter limit: Maximum number of entries to return
    public func getRecentLogs(limit: Int = 100) -> [LogEntry] {
        return Array(logBuffer.suffix(limit))
    }
    
    /// Export logs to a file
    /// - Parameter fileURL: Destination URL for the log file
    public func exportLogs(to fileURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(logBuffer)
        try data.write(to: fileURL)

        // Note: Can't call async function here in sync context
        // Use global LogNotice function instead if needed
    }
    
    // MARK: - Signpost API
    
    /// Begin a signpost interval for performance measurement
    /// - Parameters:
    ///   - name: Signpost name (must be constant string)
    ///   - id: Unique identifier
    ///   - message: Optional message
    public func beginSignpost(name: StaticString, id: String, message: String? = nil) {
        if #available(macOS 13.0, *) {
            let signpostID = OSSignpostID(log: signpostLog)
            os_signpost(.begin, log: signpostLog, name: name, "%{public}s", message ?? "")
        }
    }

    /// End a signpost interval
    /// - Parameters:
    ///   - name: Signpost name (must be constant string)
    ///   - id: Unique identifier
    ///   - message: Optional message
    public func endSignpost(name: StaticString, id: String, message: String? = nil) {
        if #available(macOS 13.0, *) {
            let signpostID = OSSignpostID(log: signpostLog)
            os_signpost(.end, log: signpostLog, name: name, "%{public}s", message ?? "")
        }
    }

    /// Emit a signpost event (instantaneous)
    /// - Parameters:
    ///   - name: Signpost name (must be constant string)
    ///   - id: Unique identifier
    ///   - message: Optional message
    public func emitSignpost(name: StaticString, id: String, message: String? = nil) {
        if #available(macOS 13.0, *) {
            let signpostID = OSSignpostID(log: signpostLog)
            os_signpost(.event, log: signpostLog, name: name, "%{public}s", message ?? "")
        }
    }
}
