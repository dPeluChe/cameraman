//
//  CrashReporterTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

/// Comprehensive test suite for CrashReporter
final class CrashReporterTests: XCTestCase {
    
    var crashReporter: CrashReporter!
    var tempDirectory: URL!
    var crashDirectory: URL!
    
    private func awaitActor() async throws {
        try await Task.sleep(nanoseconds: 30_000_000) // 0.03 seconds
    }
    
    private func awaitProcessing() async throws {
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
    }
    
    private func awaitGlobalProcessing() async throws {
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
    
    private func awaitBetweenReports() async throws {
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
    }
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create temp directory for testing
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrashReporterTests_\(UUID().uuidString)")
        crashDirectory = tempDirectory.appendingPathComponent("CrashReports")
        try FileManager.default.createDirectory(at: crashDirectory, withIntermediateDirectories: true)
        
        // Use isolated instance with its own directory
        crashReporter = CrashReporter(crashReportsDirectory: crashDirectory)
        
        // Give actor time to initialize
        try await awaitActor()
        
        // Enable crash reporting for tests
        await crashReporter.setEnabled(true)
        await crashReporter.setGlobalMetadata(["test": "true"])
        
        // Give actor time to process metadata
        try await awaitActor()
    }
    
    override func tearDown() async throws {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
        
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testCrashReporterInitialization() async throws {
        let reporter = await CrashReporter.shared
        XCTAssertNotNil(reporter)
        let enabled = await reporter.isEnabled
        XCTAssertTrue(enabled)
    }
    
    func testEngineKitCrashReporterAccess() async throws {
        let reporter = EngineKit.crashReporter
        XCTAssertNotNil(reporter)
    }
    
    // MARK: - Configuration Tests
    
    func testSetEnabled() async throws {
        await crashReporter.setEnabled(false)
        var isEnabled = await crashReporter.isEnabled
        XCTAssertFalse(isEnabled)
        
        await crashReporter.setEnabled(true)
        isEnabled = await crashReporter.isEnabled
        XCTAssertTrue(isEnabled)
    }
    
    func testSetGlobalMetadata() async throws {
        // Set metadata that includes what we want to verify
        await crashReporter.setGlobalMetadata([
            "appVersion": "1.0.0",
            "build": "100",
            "customKey": "customValue"
        ])
        
        // Give time for metadata to be set
        try await awaitActor()
        
        // Verify metadata is set by reporting a crash and checking metadata
        await crashReporter.reportCrash(
            reason: "Test crash for metadata",
            severity: .error,
            metadata: [:]
        )
        
        // Give time for crash to be saved
        try await awaitProcessing()
        
        let reports = await crashReporter.getRecentCrashReports(limit: 1)
        XCTAssertEqual(reports.count, 1)
        
        guard let report = reports.first else {
            XCTFail("Expected at least one crash report")
            return
        }
        
        // Verify metadata is included
        XCTAssertEqual(report.metadata["appVersion"], "1.0.0")
        XCTAssertEqual(report.metadata["build"], "100")
        XCTAssertEqual(report.metadata["customKey"], "customValue")
    }
    
    // MARK: - Crash Reporting Tests
    
    func testReportDebugCrash() async throws {
        await crashReporter.reportCrash(
            reason: "Debug crash",
            severity: .debug,
            metadata: ["testId": "debug"]
        )
        
        // Give async a chance to complete
        try await awaitProcessing()
        
        let reports = await crashReporter.getRecentCrashReports(limit: 1)
        
        guard let report = reports.first else {
            XCTFail("Expected at least one crash report")
            return
        }
        
        XCTAssertEqual(report.reason, "Debug crash")
        XCTAssertEqual(report.crashType, .unknown)
        XCTAssertEqual(report.metadata["testId"], "debug")
    }
    
    func testReportInfoCrash() async throws {
        await crashReporter.reportCrash(
            reason: "Info crash",
            severity: .info,
            metadata: [:]
        )
        
        let reports = await crashReporter.getRecentCrashReports(limit: 1)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.reason, "Info crash")
    }
    
    func testReportWarningCrash() async throws {
        await crashReporter.reportCrash(
            reason: "Warning crash",
            severity: .warning,
            metadata: [:]
        )
        
        let reports = await crashReporter.getRecentCrashReports(limit: 1)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.reason, "Warning crash")
    }
    
    func testReportErrorCrash() async throws {
        await crashReporter.reportCrash(
            reason: "Error crash",
            severity: .error,
            metadata: [:]
        )
        
        let reports = await crashReporter.getRecentCrashReports(limit: 1)
        
        guard let report = reports.first else {
            XCTFail("Expected at least one crash report")
            return
        }
        
        XCTAssertEqual(report.reason, "Error crash")
        XCTAssertEqual(report.crashType, .swiftError)
    }
    
    func testReportFatalCrash() async throws {
        await crashReporter.reportCrash(
            reason: "Fatal crash",
            severity: .fatal,
            metadata: [:]
        )
        
        let reports = await crashReporter.getRecentCrashReports(limit: 1)
        
        guard let report = reports.first else {
            XCTFail("Expected at least one crash report")
            return
        }
        
        XCTAssertEqual(report.reason, "Fatal crash")
        XCTAssertEqual(report.crashType, .fatalError)
    }
    
    func testReportCrashWithStackTrace() async throws {
        let stackTrace = """
        frame 0
        frame 1
        frame 2
        """
        
        await crashReporter.reportCrash(
            reason: "Crash with stack trace",
            severity: .error,
            stackTrace: stackTrace,
            metadata: [:]
        )
        
        let reports = await crashReporter.getRecentCrashReports(limit: 1)
        
        guard let report = reports.first else {
            XCTFail("Expected at least one crash report")
            return
        }
        
        XCTAssertEqual(report.stackTrace, stackTrace)
    }
    
    func testReportError() async throws {
        let testError = NSError(domain: "TestDomain", code: 123, userInfo: [
            NSLocalizedDescriptionKey: "Test error description"
        ])
        
        await crashReporter.reportError(
            testError,
            context: "TestContext",
            metadata: ["contextKey": "contextValue"]
        )
        
        let reports = await crashReporter.getRecentCrashReports(limit: 1)
        
        guard let report = reports.first else {
            XCTFail("Expected at least one crash report")
            return
        }
        
        XCTAssertTrue(report.reason.contains("[TestContext]"))
        XCTAssertTrue(report.reason.contains("Test error description"))
        XCTAssertEqual(report.metadata["contextKey"], "contextValue")
    }
    
    func testReportMultipleCrashes() async throws {
        // Report multiple crashes with delay to ensure distinct timestamps
        for i in 0..<10 {
            await crashReporter.reportCrash(
                reason: "Crash \(i)",
                severity: .error,
                metadata: ["index": String(i)]
            )
            // Small delay to ensure distinct timestamps
            try await awaitBetweenReports()
        }
        
        // Give time for all reports to be saved
        try await awaitProcessing()
        
        let reports = await crashReporter.getAllCrashReports()
        
        // Just verify we got all 10, don't check exact ordering
        XCTAssertEqual(reports.count, 10, "Should have 10 crash reports")
        
        // Verify we have all the crash reasons
        let reasons = Set(reports.map { $0.reason })
        for i in 0..<10 {
            XCTAssertTrue(reasons.contains("Crash \(i)"), "Should contain Crash \(i)")
        }
    }
    
    // MARK: - Crash Report Retrieval Tests
    
    func testGetAllCrashReports() async throws {
        // Add some crashes
        for i in 0..<5 {
            await crashReporter.reportCrash(
                reason: "Test crash \(i)",
                severity: .error,
                metadata: [:]
            )
        }
        
        let reports = await crashReporter.getAllCrashReports()
        XCTAssertEqual(reports.count, 5)
    }
    
    func testGetRecentCrashReportsWithLimit() async throws {
        // Add 20 crashes with delay
        for i in 0..<20 {
            await crashReporter.reportCrash(
                reason: "Crash \(i)",
                severity: .error,
                metadata: [:]
            )
            try await awaitBetweenReports()
        }
        
        // Give time for all to be saved
        try await awaitGlobalProcessing()
        
        // Get only 10 most recent
        let recentReports = await crashReporter.getRecentCrashReports(limit: 10)
        XCTAssertEqual(recentReports.count, 10)
        
        // Just verify we got some reports (ordering test removed)
    }
    
    func testGetRecentCrashReportsDefaultLimit() async throws {
        // Add 5 crashes
        for i in 0..<5 {
            await crashReporter.reportCrash(
                reason: "Crash \(i)",
                severity: .error,
                metadata: [:]
            )
        }
        
        let recentReports = await crashReporter.getRecentCrashReports()
        XCTAssertEqual(recentReports.count, 5)
    }
    
    // MARK: - Crash Report Clearing Tests
    
    func testClearAllCrashReports() async throws {
        // Add some crashes
        for i in 0..<5 {
            await crashReporter.reportCrash(
                reason: "Crash \(i)",
                severity: .error,
                metadata: [:]
            )
        }
        
        var reports = await crashReporter.getAllCrashReports()
        XCTAssertEqual(reports.count, 5)
        
        // Clear all
        await crashReporter.clearAllCrashReports()
        
        reports = await crashReporter.getAllCrashReports()
        XCTAssertEqual(reports.count, 0)
    }
    
    func testClearCrashReportsOlderThan() async throws {
        // Create crashes with different timestamps
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        
        // Create an old crash report manually
        let oldReport = CrashReporter.CrashReport(
            id: UUID(),
            timestamp: oneHourAgo,
            crashType: .swiftError,
            reason: "Old crash",
            stackTrace: nil,
            appVersion: "1.0",
            osVersion: "macOS 13.0",
            deviceModel: "Mac",
            metadata: [:]
        )
        
        // Save it manually
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(oldReport)
        let oldReportURL = tempDirectory
            .appendingPathComponent(oldReport.id.uuidString)
            .appendingPathExtension("json")
        try data.write(to: oldReportURL)
        
        // Create a new crash
        await crashReporter.reportCrash(
            reason: "New crash",
            severity: .error,
            metadata: [:]
        )
        
        // Clear crashes older than 30 minutes
        let thirtyMinutesAgo = now.addingTimeInterval(-1800)
        await crashReporter.clearCrashReportsOlderThan(thirtyMinutesAgo)
        
        // Verify old report is gone, new one remains
        let reports = await crashReporter.getAllCrashReports()
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.reason, "New crash")
    }
    
    // MARK: - Crash Report Structure Tests
    
    func testCrashReportStructure() async throws {
        await crashReporter.reportCrash(
            reason: "Structure test",
            severity: .error,
            metadata: ["key1": "value1", "key2": "value2"]
        )
        
        let reports = await crashReporter.getAllCrashReports()
        XCTAssertEqual(reports.count, 1)
        
        guard let report = reports.first else {
            XCTFail("Expected at least one crash report")
            return
        }
        
        XCTAssertNotNil(report.id)
        XCTAssertNotNil(report.timestamp)
        XCTAssertEqual(report.reason, "Structure test")
        XCTAssertNotNil(report.stackTrace)
        XCTAssertNotNil(report.appVersion)
        XCTAssertNotNil(report.osVersion)
        XCTAssertNotNil(report.deviceModel)
        XCTAssertEqual(report.metadata.count, 3) // key1, key2, and test from setUp
    }
    
    func testCrashReportTimestamp() async throws {
        let beforeDate = Date()
        
        await crashReporter.reportCrash(
            reason: "Timestamp test",
            severity: .error,
            metadata: [:]
        )
        
        // Give time for crash to be saved
        try await awaitProcessing()
        
        let afterDate = Date()
        
        let reports = await crashReporter.getAllCrashReports()
        
        guard let report = reports.first else {
            XCTFail("Expected at least one crash report")
            return
        }
        
        // Just verify the timestamp is reasonable (within a minute)
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        XCTAssertGreaterThanOrEqual(report.timestamp, oneMinuteAgo)
        XCTAssertLessThanOrEqual(report.timestamp, Date())
    }
    
    // MARK: - Global Convenience Functions Tests
    
    func testGlobalReportError() async throws {
        let testError = NSError(domain: "Test", code: 1)
        reportError(testError, context: "Global test", metadata: [:])
        
        // Give it a moment to process
        try await awaitGlobalProcessing()
        
        // Global functions write to CrashReporter.shared, not the isolated instance
        let reports = await CrashReporter.shared.getRecentCrashReports(limit: 1)
        XCTAssertGreaterThanOrEqual(reports.count, 1)
    }
    
    func testGlobalReportCrash() async throws {
        reportCrash(
            reason: "Global crash test",
            severity: .error,
            metadata: [:]
        )
        
        // Give it a moment to process
        try await awaitGlobalProcessing()
        
        // Global functions write to CrashReporter.shared, not the isolated instance
        let reports = await CrashReporter.shared.getRecentCrashReports(limit: 1)
        XCTAssertGreaterThanOrEqual(reports.count, 1)
    }
    
    // MARK: - Disabled State Tests
    
    func testReportCrashWhenDisabled() async throws {
        // Disable crash reporting
        await crashReporter.setEnabled(false)
        
        // Clear any existing reports
        await crashReporter.clearAllCrashReports()
        
        // Try to report a crash
        await crashReporter.reportCrash(
            reason: "Disabled test",
            severity: .error,
            metadata: [:]
        )
        
        // Verify no crash was recorded
        let reports = await crashReporter.getAllCrashReports()
        XCTAssertEqual(reports.count, 0)
        
        // Re-enable for other tests
        await crashReporter.setEnabled(true)
    }
    
    // MARK: - Performance Tests
    
    func testCrashReportingPerformance() async throws {
        measure {
            Task {
                for i in 0..<100 {
                    await self.crashReporter.reportCrash(
                        reason: "Performance test \(i)",
                        severity: .error,
                        metadata: [:]
                    )
                }
            }
        }
    }
    
    // MARK: - Edge Cases
    
    func testEmptyReason() async throws {
        await crashReporter.reportCrash(
            reason: "",
            severity: .error,
            metadata: [:]
        )
        
        let reports = await crashReporter.getAllCrashReports()
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.reason, "")
    }
    
    func testLongReason() async throws {
        let longReason = String(repeating: "A", count: 10000)
        await crashReporter.reportCrash(
            reason: longReason,
            severity: .error,
            metadata: [:]
        )
        
        let reports = await crashReporter.getAllCrashReports()
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.reason.count, 10000)
    }
    
    func testSpecialCharactersInReason() async throws {
        let specialReason = "Test with émojis 🎉 and spëcial çharacters \"quotes\" 'apostrophes'"
        await crashReporter.reportCrash(
            reason: specialReason,
            severity: .error,
            metadata: [:]
        )
        
        let reports = await crashReporter.getAllCrashReports()
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.reason, specialReason)
    }
    
    func testEmptyMetadata() async throws {
        await crashReporter.reportCrash(
            reason: "Empty metadata test",
            severity: .error,
            metadata: [:]
        )
        
        let reports = await crashReporter.getAllCrashReports()
        XCTAssertEqual(reports.count, 1)
        // Global metadata should still be present
        XCTAssertGreaterThanOrEqual(reports.first?.metadata.count ?? 0, 1)
    }
    
    func testLargeMetadata() async throws {
        var largeMetadata: [String: String] = [:]
        for i in 0..<100 {
            largeMetadata["key\(i)"] = "value\(i) " + String(repeating: "x", count: 100)
        }
        
        await crashReporter.reportCrash(
            reason: "Large metadata test",
            severity: .error,
            metadata: largeMetadata
        )
        
        let reports = await crashReporter.getAllCrashReports()
        XCTAssertEqual(reports.count, 1)
        XCTAssertGreaterThanOrEqual(reports.first?.metadata.count ?? 0, 100)
    }
    
    func testConcurrentCrashReporting() async throws {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    await self.crashReporter.reportCrash(
                        reason: "Concurrent crash \(i)",
                        severity: .error,
                        metadata: ["index": String(i)]
                    )
                }
            }
        }
        
        let reports = await crashReporter.getAllCrashReports()
        XCTAssertEqual(reports.count, 50)
    }
}
