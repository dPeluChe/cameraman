//
//  LoggingSystemTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

/// Comprehensive test suite for LoggingSystem
final class LoggingSystemTests: XCTestCase {
    
    var loggingSystem: LoggingSystem!
    
    override func setUp() async throws {
        try await super.setUp()
        loggingSystem = await LoggingSystem.shared
        // Apply test configuration first — each of these calls emits its
        // own internal log message — then clear the buffer so each test
        // body starts with an empty log buffer.
        await loggingSystem.setMinimumLevel(.debug)
        await loggingSystem.setConsoleLogging(false)
        await loggingSystem.setSourceInfo(false)
        await loggingSystem.clearBuffer()
    }
    
    override func tearDown() async throws {
        // Clean up after each test
        await loggingSystem.clearBuffer()
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testLoggingSystemInitialization() async throws {
        // Verify logging system is accessible
        let system = await LoggingSystem.shared
        XCTAssertNotNil(system)
    }
    
    func testEngineKitLoggingAccess() async throws {
        // Verify EngineKit namespace provides access to logging
        let logging = EngineKit.logging
        XCTAssertNotNil(logging)
    }
    
    // MARK: - Configuration Tests
    
    func testSetMinimumLevel() async throws {
        await loggingSystem.setMinimumLevel(.warning)

        // Log at different levels
        await loggingSystem.debug(category: .general, "Debug message")
        await loggingSystem.info(category: .general, "Info message")
        await loggingSystem.warning(category: .general, "Warning message")
        await loggingSystem.error(category: .general, "Error message")
        
        let logs = await loggingSystem.getLogs()
        
        // Only warning and error should be present
        let debugLogs = logs.filter { $0.level == .debug }
        let infoLogs = logs.filter { $0.level == .info }
        let warningLogs = logs.filter { $0.level == .warning }
        let errorLogs = logs.filter { $0.level == .error }
        
        XCTAssertEqual(debugLogs.count, 0, "Debug logs should be filtered out")
        XCTAssertEqual(infoLogs.count, 0, "Info logs should be filtered out")
        XCTAssertEqual(warningLogs.count, 1, "Warning log should be present")
        XCTAssertEqual(errorLogs.count, 1, "Error log should be present")
    }
    
    func testSetConsoleLogging() async throws {
        // This test just verifies the method doesn't crash
        await loggingSystem.setConsoleLogging(true)
        await loggingSystem.setConsoleLogging(false)
        
        // Verify state
        let logs = await loggingSystem.getLogs()
        XCTAssertNotNil(logs)
    }
    
    func testSetSourceInfo() async throws {
        await loggingSystem.setSourceInfo(true)
        await loggingSystem.info(category: .general, "Test message with source")
        
        let logs = await loggingSystem.getRecentLogs(limit: 1)
        XCTAssertEqual(logs.count, 1)
        
        let log = logs.first!
        XCTAssertNotNil(log.metadata)
        XCTAssertTrue(log.metadata?.keys.contains("file") ?? false)
        XCTAssertTrue(log.metadata?.keys.contains("function") ?? false)
        XCTAssertTrue(log.metadata?.keys.contains("line") ?? false)
    }
    
    // MARK: - Basic Logging Tests
    
    func testDebugLog() async throws {
        await loggingSystem.debug(category: .general, "Debug test")
        
        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .debug)
        XCTAssertEqual(logs.first?.message, "Debug test")
        XCTAssertEqual(logs.first?.category, .general)
    }
    
    func testInfoLog() async throws {
        await loggingSystem.info(category: .capture, "Info test")
        
        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .info)
        XCTAssertEqual(logs.first?.category, .capture)
    }
    
    func testNoticeLog() async throws {
        await loggingSystem.notice(category: .export, "Notice test")
        
        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .notice)
        XCTAssertEqual(logs.first?.category, .export)
    }
    
    func testWarningLog() async throws {
        await loggingSystem.warning(category: .preview, "Warning test")
        
        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .warning)
        XCTAssertEqual(logs.first?.category, .preview)
    }
    
    func testErrorLog() async throws {
        await loggingSystem.error(category: .projectStore, "Error test")
        
        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .error)
        XCTAssertEqual(logs.first?.category, .projectStore)
    }
    
    func testFaultLog() async throws {
        await loggingSystem.fault(category: .transcription, "Fault test")
        
        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .fault)
        XCTAssertEqual(logs.first?.category, .transcription)
    }
    
    // MARK: - Category Tests
    
    func testAllCategories() async throws {
        let categories: [LoggingSystem.Category] = [
            .general, .capture, .export, .preview, .projectStore,
            .projectLibrary, .transcription, .telemetry, .overlay,
            .editor, .jobQueue, .crashReporter, .ui, .performance
        ]
        
        for category in categories {
            await loggingSystem.info(category: category, "Test message for \(category.rawValue)")
        }
        
        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, categories.count)
        
        // Verify each category is present
        for category in categories {
            let categoryLogs = logs.filter { $0.category == category }
            XCTAssertEqual(categoryLogs.count, 1, "Category \(category.rawValue) should have 1 log")
        }
    }
    
    // MARK: - Buffer Management Tests
    
    func testLogBuffer() async throws {
        // Add multiple logs
        for i in 0..<10 {
            await loggingSystem.info(category: .general, "Log \(i)")
        }
        
        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 10)
        
        // Verify order
        for (index, log) in logs.enumerated() {
            XCTAssertEqual(log.message, "Log \(index)")
        }
    }
    
    func testClearBuffer() async throws {
        await loggingSystem.info(category: .general, "Before clear")
        await loggingSystem.clearBuffer()
        
        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 0)
    }
    
    func testGetRecentLogs() async throws {
        // Add 20 logs
        for i in 0..<20 {
            await loggingSystem.info(category: .general, "Log \(i)")
        }
        
        // Get last 5
        let recentLogs = await loggingSystem.getRecentLogs(limit: 5)
        XCTAssertEqual(recentLogs.count, 5)
        
        // Verify they're the last 5
        XCTAssertEqual(recentLogs[0].message, "Log 15")
        XCTAssertEqual(recentLogs[4].message, "Log 19")
    }
    
    func testGetLogsByCategory() async throws {
        await loggingSystem.info(category: .capture, "Capture log")
        await loggingSystem.info(category: .export, "Export log")
        await loggingSystem.info(category: .capture, "Another capture log")
        
        let captureLogs = await loggingSystem.getLogs(category: .capture)
        let exportLogs = await loggingSystem.getLogs(category: .export)
        
        XCTAssertEqual(captureLogs.count, 2)
        XCTAssertEqual(exportLogs.count, 1)
    }
    
    func testGetLogsByLevel() async throws {
        await loggingSystem.debug(category: .general, "Debug")
        await loggingSystem.info(category: .general, "Info")
        await loggingSystem.error(category: .general, "Error")
        
        let debugLogs = await loggingSystem.getLogs(level: .debug)
        let infoLogs = await loggingSystem.getLogs(level: .info)
        let errorLogs = await loggingSystem.getLogs(level: .error)
        
        XCTAssertEqual(debugLogs.count, 1)
        XCTAssertEqual(infoLogs.count, 1)
        XCTAssertEqual(errorLogs.count, 1)
    }
    
    // MARK: - Export Tests
    
    func testExportLogs() async throws {
        await loggingSystem.info(category: .general, "Export test")
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_export_\(UUID().uuidString).json")
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        try await loggingSystem.exportLogs(to: tempURL)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        
        // Verify we can read the exported file. exportLogs serializes Date
        // as ISO8601 strings; the decoder must use the matching strategy.
        let data = try Data(contentsOf: tempURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let logs = try decoder.decode([LoggingSystem.LogEntry].self, from: data)
        
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.message, "Export test")
    }
    
    // MARK: - Signpost Tests
    
    func testBeginEndSignpost() async throws {
        // This test verifies signpost methods don't crash
        await loggingSystem.beginSignpost(name: "TestOperation", id: "test-1")
        await loggingSystem.endSignpost(name: "TestOperation", id: "test-1")
        
        // If we get here without crashing, the test passes
        XCTAssertTrue(true)
    }
    
    func testEmitSignpost() async throws {
        await loggingSystem.emitSignpost(name: "TestEvent", id: "test-2")
        
        // If we get here without crashing, the test passes
        XCTAssertTrue(true)
    }
    
    // MARK: - Global Convenience Functions Tests

    /// The global LogXxx helpers wrap actor calls in fire-and-forget Tasks,
    /// so the test has to wait for the spawned Task to land in the actor's
    /// queue before reading the buffer. A short sleep is the simplest
    /// reliable signal — Task.yield does not guarantee the detached Task
    /// has started.
    private static let globalLogDrainNanos: UInt64 = 100_000_000 // 100ms

    func testGlobalDebugFunction() async throws {
        LogDebug(.general, "Global debug test")
        try await Task.sleep(nanoseconds: Self.globalLogDrainNanos)

        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .debug)
    }

    func testGlobalInfoFunction() async throws {
        LogInfo(.capture, "Global info test")
        try await Task.sleep(nanoseconds: Self.globalLogDrainNanos)

        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .info)
    }

    func testGlobalNoticeFunction() async throws {
        LogNotice(.export, "Global notice test")
        try await Task.sleep(nanoseconds: Self.globalLogDrainNanos)

        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .notice)
    }

    func testGlobalWarningFunction() async throws {
        LogWarning(.preview, "Global warning test")
        try await Task.sleep(nanoseconds: Self.globalLogDrainNanos)

        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .warning)
    }

    func testGlobalErrorFunction() async throws {
        LogError(.projectStore, "Global error test")
        try await Task.sleep(nanoseconds: Self.globalLogDrainNanos)

        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .error)
    }

    func testGlobalFaultFunction() async throws {
        LogFault(.transcription, "Global fault test")
        try await Task.sleep(nanoseconds: Self.globalLogDrainNanos)

        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .fault)
    }
    
    // MARK: - Performance Tests
    
    func testLoggingPerformance() async throws {
        // Time the flood synchronously and assert a soft bound. Using
        // `measure` here would require fire-and-forget Tasks that leak
        // into the next test's setUp and pollute its buffer assertions.
        let start = Date()
        for i in 0..<1000 {
            await loggingSystem.debug(category: .general, "Performance test \(i)")
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 10.0, "1000 logs should complete in well under 10s")
    }
    
    func testLogBufferPerformance() async throws {
        // Add 1000 logs
        for i in 0..<1000 {
            await loggingSystem.info(category: .general, "Log \(i)")
        }
        
        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 1000)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyMessage() async throws {
        await loggingSystem.info(category: .general, "")
        
        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.message, "")
    }
    
    func testLongMessage() async throws {
        let longMessage = String(repeating: "A", count: 10000)
        await loggingSystem.info(category: .general, longMessage)
        
        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.message.count, 10000)
    }
    
    func testSpecialCharactersInMessage() async throws {
        let specialMessage = "Test with émojis 🎉 and spëcial çharacters"
        await loggingSystem.info(category: .general, specialMessage)
        
        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.message, specialMessage)
    }
    
    func testConcurrentLogging() async throws {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    await self.loggingSystem.info(category: .general, "Concurrent log \(i)")
                }
            }
        }
        
        let logs = await loggingSystem.getLogs()
        XCTAssertEqual(logs.count, 100)
    }
    
    // MARK: - Level Filtering Tests
    
    func testLevelFilteringOrder() async throws {
        await loggingSystem.setMinimumLevel(.error)

        await loggingSystem.debug(category: .general, "Debug")
        await loggingSystem.info(category: .general, "Info")
        await loggingSystem.warning(category: .general, "Warning")
        await loggingSystem.error(category: .general, "Error")
        await loggingSystem.fault(category: .general, "Fault")
        
        let logs = await loggingSystem.getLogs()
        
        // Only error and fault should be present
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs.filter { $0.level == .error }.count, 1)
        XCTAssertEqual(logs.filter { $0.level == .fault }.count, 1)
    }
}
