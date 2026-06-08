//
//  CrashReporter.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import os.log
import os.signpost

/// CrashReporter provides centralized crash reporting and crash log capture
/// Captures crashes, exceptions, and critical errors for debugging and monitoring
public actor CrashReporter {
    // MARK: - Types
    
    /// Crash report structure
    public struct CrashReport: Codable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let crashType: CrashType
        public let reason: String
        public let stackTrace: String?
        public let appVersion: String
        public let osVersion: String
        public let deviceModel: String
        public let metadata: [String: String]
        
        public enum CrashType: String, Codable, Sendable {
            case fatalError
            case nsException
            case signal
            case swiftError
            case unknown
        }
    }
    
    /// Crash severity level
    public enum Severity: String, Sendable {
        case debug
        case info
        case warning
        case error
        case fatal
    }
    
    // MARK: - Properties
    
    /// Shared instance
    public static let shared = CrashReporter()
    
    /// Structured logging
    private let logger = Logger(
        subsystem: "com.projectstudio.enginekit",
        category: "CrashReporter"
    )
    
    /// Signpost logger for performance instrumentation
    private let signpostLogger = OSLog(
        subsystem: "com.projectstudio.enginekit",
        category: "PerformanceInstrumentation"
    )
    
    /// Crash reports storage directory
    private let crashReportsDirectory: URL
    
    /// Maximum number of crash reports to keep
    private let maxCrashReports = 50
    
    /// Whether crash reporting is enabled
    private var _isEnabled: Bool = true
    
    /// Whether crash reporting is enabled
    var isEnabled: Bool {
        return _isEnabled
    }
    
    /// Metadata to include in all crash reports
    private var globalMetadata: [String: String] = [:]
    
    // MARK: - Initialization
    
    private init() {
        // Set up crash reports directory
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        let directory = appSupport
            .appendingPathComponent("ProjectStudio")
            .appendingPathComponent("CrashReports")
        
        self.init(crashReportsDirectory: directory)
    }
    
    /// Internal initializer for testing with custom directory
    init(crashReportsDirectory: URL) {
        self.crashReportsDirectory = crashReportsDirectory
        
        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: crashReportsDirectory,
            withIntermediateDirectories: true
        )
        
        logger.info("CrashReporter initialized with directory: \(crashReportsDirectory.path)")
    }
    
    // MARK: - Public API
    
    /// Enable or disable crash reporting
    public func setEnabled(_ enabled: Bool) {
        _isEnabled = enabled
        logger.info("Crash reporting \(enabled ? "enabled" : "disabled")")
    }

    /// Install crash handlers. Call once at app launch.
    public func start() async {
        await setupCrashHandlers()
    }
    
    /// Set global metadata to include in all crash reports
    public func setGlobalMetadata(_ metadata: [String: String]) {
        globalMetadata = metadata
        logger.debug("Updated global crash metadata: \(metadata.keys.count) entries")
    }
    
    /// Report a crash or critical error
    /// - Parameters:
    ///   - reason: Description of the crash/error
    ///   - severity: Severity level
    ///   - stackTrace: Optional stack trace
    ///   - metadata: Additional context
    public func reportCrash(
        reason: String,
        severity: Severity,
        stackTrace: String? = nil,
        metadata: [String: String] = [:]
    ) {
        guard _isEnabled else { return }
        
        // Merge global and local metadata
        var allMetadata = globalMetadata
        for (key, value) in metadata {
            allMetadata[key] = value
        }
        
        // Create crash report
        let report = CrashReport(
            id: UUID(),
            timestamp: Date(),
            crashType: inferCrashType(from: severity),
            reason: reason,
            stackTrace: stackTrace ?? captureStackTrace(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: getDeviceModel(),
            metadata: allMetadata
        )
        
        // Log to console
        logCrashReport(report, severity: severity)
        
        // Save to disk
        saveCrashReport(report)
        
        // Track signpost for crash
        let signpostID = OSSignpostID(log: signpostLogger)
        os_signpost(
            .event,
            log: signpostLogger,
            name: "CrashReport",
            signpostID: signpostID,
            "type=%{public}@, reason=%{public}@",
            report.crashType.rawValue,
            report.reason
        )
    }
    
    /// Report a non-fatal error (warning/error level)
    /// - Parameters:
    ///   - error: The error to report
    ///   - context: Additional context about where the error occurred
    ///   - metadata: Additional metadata
    public func reportError(
        _ error: Error,
        context: String = "",
        metadata: [String: String] = [:]
    ) {
        let severity: Severity
        if let nsError = error as NSError? {
            severity = nsError.domain == NSCocoaErrorDomain && nsError.code < 100 ? .warning : .error
        } else {
            severity = .error
        }
        
        var reason = error.localizedDescription
        if !context.isEmpty {
            reason = "[\(context)] \(reason)"
        }
        
        reportCrash(
            reason: reason,
            severity: severity,
            stackTrace: captureStackTrace(),
            metadata: metadata
        )
    }
    
    /// Get all crash reports
    public func getAllCrashReports() -> [CrashReport] {
        guard self._isEnabled else { return [] }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: crashReportsDirectory,
                includingPropertiesForKeys: nil
            )
            
            var reports: [CrashReport] = []
            for file in files where file.pathExtension == "json" {
                let data = try Data(contentsOf: file)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let report = try decoder.decode(CrashReport.self, from: data)
                reports.append(report)
            }
            
            // Sort by timestamp, newest first
            return reports.sorted { $0.timestamp > $1.timestamp }
        } catch {
            logger.error("Failed to load crash reports: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Get recent crash reports
    /// - Parameter limit: Maximum number of reports to return
    public func getRecentCrashReports(limit: Int = 10) -> [CrashReport] {
        return Array(getAllCrashReports().prefix(limit))
    }
    
    /// Clear all crash reports
    public func clearAllCrashReports() {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: crashReportsDirectory,
                includingPropertiesForKeys: nil
            )
            
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
            
            logger.info("Cleared all crash reports")
        } catch {
            logger.error("Failed to clear crash reports: \(error.localizedDescription)")
        }
    }
    
    /// Clear crash reports older than specified date
    /// - Parameter date: Cutoff date
    public func clearCrashReportsOlderThan(_ date: Date) {
        let reports = getAllCrashReports()
        var deletedCount = 0
        
        for report in reports where report.timestamp < date {
            let fileURL = crashReportsDirectory
                .appendingPathComponent(report.id.uuidString)
                .appendingPathExtension("json")
            
            do {
                try FileManager.default.removeItem(at: fileURL)
                deletedCount += 1
            } catch {
                logger.warning("Failed to delete crash report \(report.id): \(error.localizedDescription)")
            }
        }
        
        logger.info("Cleared \(deletedCount) crash reports older than \(date)")
    }
    
    /// Export crash reports as a ZIP archive
    /// - Parameter destinationURL: Destination URL for the ZIP file
    public func exportCrashReports(to destinationURL: URL) async throws {
        // This would require a ZIP library - for now, we'll just copy the directory
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        try fileManager.copyItem(at: crashReportsDirectory, to: destinationURL)
        
        logger.info("Exported crash reports to \(destinationURL.path)")
    }
    
    // MARK: - Private Methods
    
    private func setupCrashHandlers() async {
        // Set up signal handlers for common crash signals
        signal(SIGABRT) { _ in
            Task {
                await CrashReporter.shared.reportCrash(
                    reason: "SIGABRT - Abort signal",
                    severity: .fatal,
                    stackTrace: nil
                )
            }
        }
        
        signal(SIGBUS) { _ in
            Task {
                await CrashReporter.shared.reportCrash(
                    reason: "SIGBUS - Bus error",
                    severity: .fatal,
                    stackTrace: nil
                )
            }
        }
        
        signal(SIGFPE) { _ in
            Task {
                await CrashReporter.shared.reportCrash(
                    reason: "SIGFPE - Floating point exception",
                    severity: .fatal,
                    stackTrace: nil
                )
            }
        }
        
        signal(SIGILL) { _ in
            Task {
                await CrashReporter.shared.reportCrash(
                    reason: "SIGILL - Illegal instruction",
                    severity: .fatal,
                    stackTrace: nil
                )
            }
        }
        
        signal(SIGSEGV) { _ in
            Task {
                await CrashReporter.shared.reportCrash(
                    reason: "SIGSEGV - Segmentation fault",
                    severity: .fatal,
                    stackTrace: nil
                )
            }
        }
        
        // Set up Swift error handler
        NSSetUncaughtExceptionHandler { exception in
            Task {
                await CrashReporter.shared.reportCrash(
                    reason: "Uncaught exception: \(exception.name)",
                    severity: .fatal,
                    stackTrace: exception.callStackSymbols.joined(separator: "\n")
                )
            }
        }
        
        logger.debug("Crash handlers installed")
    }
    
    private func inferCrashType(from severity: Severity) -> CrashReport.CrashType {
        switch severity {
        case .fatal:
            return .fatalError
        case .error:
            return .swiftError
        default:
            return .unknown
        }
    }
    
    private func logCrashReport(_ report: CrashReport, severity: Severity) {
        let osLogType: OSLogType
        switch severity {
        case .debug:
            osLogType = .debug
        case .info:
            osLogType = .info
        case .warning:
            osLogType = .default
        case .error:
            osLogType = .error
        case .fatal:
            osLogType = .fault
        }
        
        logger.log(
            level: osLogType,
            "Crash Report: Type=\(report.crashType.rawValue), Reason=\(report.reason), App Version=\(report.appVersion), OS Version=\(report.osVersion), Device=\(report.deviceModel), Metadata=\(report.metadata)"
        )
        
        if let stackTrace = report.stackTrace {
            logger.error("Stack trace:\(stackTrace)")
        }
    }
    
    private func saveCrashReport(_ report: CrashReport) {
        let filename = report.id.uuidString + ".json"
        let fileURL = crashReportsDirectory.appendingPathComponent(filename)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            try data.write(to: fileURL)
            
            logger.debug("Saved crash report to \(fileURL.path)")
            
            // Clean up old reports if we have too many
            cleanupOldReports()
        } catch {
            logger.error("Failed to save crash report: \(error.localizedDescription)")
        }
    }
    
    private func cleanupOldReports() {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: crashReportsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
            
            if files.count > maxCrashReports {
                // Sort by modification date, oldest first
                let sortedFiles = files.sorted { file1, file2 in
                    let date1 = try? file1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast
                    let date2 = try? file2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast
                    return date1! < date2!
                }
                
                // Delete oldest files
                let filesToDelete = sortedFiles.prefix(files.count - maxCrashReports)
                for file in filesToDelete {
                    try FileManager.default.removeItem(at: file)
                }
                
                logger.debug("Cleaned up \(filesToDelete.count) old crash reports")
            }
        } catch {
            logger.warning("Failed to cleanup old crash reports: \(error.localizedDescription)")
        }
    }
    
    private func captureStackTrace() -> String {
        let threads = Thread.callStackSymbols
        return threads.joined(separator: "\n")
    }
    
    private func getDeviceModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}

// MARK: - Global Convenience Functions

/// Report a non-fatal error
public func reportError(
    _ error: Error,
    context: String = "",
    metadata: [String: String] = [:]
) {
    Task {
        await CrashReporter.shared.reportError(
            error,
            context: context,
            metadata: metadata
        )
    }
}

/// Report a crash or critical error
public func reportCrash(
    reason: String,
    severity: CrashReporter.Severity,
    metadata: [String: String] = [:]
) {
    Task {
        await CrashReporter.shared.reportCrash(
            reason: reason,
            severity: severity,
            metadata: metadata
        )
    }
}
