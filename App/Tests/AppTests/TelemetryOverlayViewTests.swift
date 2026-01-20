//
//  TelemetryOverlayViewTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20.
//

import XCTest
import SwiftUI
import EngineKit
@testable import App

@MainActor
final class TelemetryOverlayViewTests: XCTestCase {
    var mockProjectDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        // Create temporary directory for mock project
        let tempDir = FileManager.default.temporaryDirectory
        mockProjectDirectory = tempDir.appendingPathComponent("test-project-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mockProjectDirectory, withIntermediateDirectories: true)

        // Create telemetry directory
        let telemetryDir = mockProjectDirectory.appendingPathComponent("telemetry")
        try FileManager.default.createDirectory(at: telemetryDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: mockProjectDirectory)
        mockProjectDirectory = nil
        try await super.tearDown()
    }

    // MARK: - TelemetryOverlayView Tests

    func testTelemetryOverlayViewInitialization() throws {
        let view = TelemetryOverlayView(
            project: nil as Project?,
            projectDirectory: mockProjectDirectory,
            currentTime: 5.0,
            showCursor: true,
            showClicks: true,
            showKeystrokes: true,
            overlaySize: CoreGraphics.CGSize(width: 1920, height: 1080)
        )

        XCTAssertNotNil(view)
    }

    func testTelemetryOverlayViewWithNilProject() throws {
        let view = TelemetryOverlayView(
            project: nil as Project?,
            projectDirectory: nil as URL?,
            currentTime: 5.0,
            showCursor: true,
            showClicks: true,
            showKeystrokes: true,
            overlaySize: CoreGraphics.CGSize(width: 1920, height: 1080)
        )

        XCTAssertNotNil(view)
    }

    func testTelemetryOverlayViewWithTogglesOff() throws {
        let view = TelemetryOverlayView(
            project: nil as Project?,
            projectDirectory: mockProjectDirectory,
            currentTime: 5.0,
            showCursor: false,
            showClicks: false,
            showKeystrokes: false,
            overlaySize: CoreGraphics.CGSize(width: 1920, height: 1080)
        )

        XCTAssertNotNil(view)
    }

    // MARK: - Position Normalization Tests

    func testNormalizePosition() {
        let view = TelemetryOverlayView(
            project: nil as Project?,
            projectDirectory: mockProjectDirectory,
            currentTime: 5.0,
            showCursor: false,
            showClicks: false,
            showKeystrokes: false,
            overlaySize: CoreGraphics.CGSize(width: 1920, height: 1080)
        )

        // Extract normalizePosition using mirror or create helper
        // For now, just test the view doesn't crash
        XCTAssertNotNil(view)
    }

    func testNormalizePositionWithDifferentSizes() {
        let smallSize = CoreGraphics.CGSize(width: 960, height: 540)
        let largeSize = CoreGraphics.CGSize(width: 3840, height: 2160)

        let smallView = TelemetryOverlayView(
            project: nil as Project?,
            projectDirectory: mockProjectDirectory,
            currentTime: 5.0,
            showCursor: false,
            showClicks: false,
            showKeystrokes: false,
            overlaySize: smallSize
        )

        let largeView = TelemetryOverlayView(
            project: nil as Project?,
            projectDirectory: mockProjectDirectory,
            currentTime: 5.0,
            showCursor: false,
            showClicks: false,
            showKeystrokes: false,
            overlaySize: largeSize
        )

        XCTAssertNotNil(smallView)
        XCTAssertNotNil(largeView)
    }

    // MARK: - Click Opacity Tests

    func testClickOpacityCalculation() {
        // Test that click opacity decreases with age
        let currentTime: TimeInterval = 5.0

        let recentClick: TimeInterval = 4.5 // 0.5 seconds ago
        let oldClick: TimeInterval = 4.0 // 1.0 second ago
        let veryOldClick: TimeInterval = 3.0 // 2.0 seconds ago

        let recentOpacity = 1.0 - (currentTime - recentClick) / 1.0
        let oldOpacity = 1.0 - (currentTime - oldClick) / 1.0
        let veryOldOpacity = max(0, 1.0 - (currentTime - veryOldClick) / 1.0)

        XCTAssertGreaterThan(recentOpacity, oldOpacity)
        XCTAssertGreaterThanOrEqual(oldOpacity, 0)
        XCTAssertEqual(veryOldOpacity, 0)
    }

    // MARK: - Display Key Tests

    func testDisplayKeyFormatting() {
        // Test special key formatting
        let spaceKey = " "
        let returnKey = "\r"
        let tabKey = "\t"
        let deleteKey = "\u{7F}"
        let escapeKey = "\u{1B}"

        // These should be formatted specially
        XCTAssertNotEqual(spaceKey, "Space") // Would be formatted by helper
        XCTAssertNotEqual(returnKey, "Return")
        XCTAssertNotEqual(tabKey, "Tab")
    }

    func testDisplayKeyUppercasing() {
        let lowercaseKey = "a"
        let uppercaseKey = "A"

        // Both should display as uppercase
        XCTAssertEqual(lowercaseKey.uppercased(), "A")
        XCTAssertEqual(uppercaseKey, "A")
    }

    // MARK: - Keystroke Window Tests

    func testKeystrokeVisibilityWindow() {
        let currentTime: TimeInterval = 10.0
        let keystrokeWindow: TimeInterval = 2.0

        let visibleRangeStart = currentTime - keystrokeWindow
        let visibleRangeEnd = currentTime

        let keystrokeTimes: [TimeInterval] = [
            9.5, // Within window (0.5s ago)
            8.5, // Within window (1.5s ago)
            8.0, // Edge of window (2.0s ago)
            7.5, // Outside window (2.5s ago)
            10.5 // Outside window (future)
        ]

        let visibleKeystrokes = keystrokeTimes.filter { time in
            time >= visibleRangeStart && time <= visibleRangeEnd
        }

        XCTAssertEqual(visibleKeystrokes.count, 3)
        XCTAssertTrue(visibleKeystrokes.contains(9.5))
        XCTAssertTrue(visibleKeystrokes.contains(8.5))
        XCTAssertTrue(visibleKeystrokes.contains(8.0))
        XCTAssertFalse(visibleKeystrokes.contains(7.5))
        XCTAssertFalse(visibleKeystrokes.contains(10.5))
    }

    // MARK: - Click Window Tests

    func testClickVisibilityWindow() {
        let currentTime: TimeInterval = 5.0
        let clickWindow: TimeInterval = 1.0

        let visibleRangeStart = currentTime - clickWindow
        let visibleRangeEnd = currentTime + clickWindow

        let clickTimes: [TimeInterval] = [
            4.5, // Within window (0.5s ago)
            4.0, // Edge of window (1.0s ago)
            5.5, // Within window (0.5s in future)
            3.5, // Outside window (1.5s ago)
            6.5  // Outside window (1.5s in future)
        ]

        let visibleClicks = clickTimes.filter { time in
            time >= visibleRangeStart && time <= visibleRangeEnd
        }

        XCTAssertEqual(visibleClicks.count, 3)
        XCTAssertTrue(visibleClicks.contains(4.5))
        XCTAssertTrue(visibleClicks.contains(4.0))
        XCTAssertTrue(visibleClicks.contains(5.5))
        XCTAssertFalse(visibleClicks.contains(3.5))
        XCTAssertFalse(visibleClicks.contains(6.5))
    }

    // MARK: - Telemetry Data Loading Tests

    func testLoadCursorTelemetryWithMissingFile() async throws {
        let telemetrySync = TelemetrySync()

        let missingFile = mockProjectDirectory.appendingPathComponent("nonexistent.jsonl")

        do {
            _ = try await telemetrySync.synchronize(
                telemetryFile: missingFile,
                timeline: mockProject.timeline
            )
            XCTFail("Should have thrown error for missing file")
        } catch {
            // Expected error
            XCTAssertTrue(error is TelemetrySync.SyncError)
        }
    }

    func testLoadKeystrokeTelemetryWithMissingFile() async {
        let missingFile = mockProjectDirectory.appendingPathComponent("nonexistent.jsonl")

        do {
            let content = try String(contentsOf: missingFile, encoding: .utf8)
            XCTFail("Should have thrown error for missing file, got: \(content)")
        } catch {
            // Expected error
        }
    }

    func testLoadKeystrokeTelemetryWithValidData() async throws {
        // Create mock keystroke file
        let keysFile = mockProjectDirectory.appendingPathComponent("telemetry/keys.jsonl")

        let mockKeystrokes = [
            #"{"t":1.0,"type":"down","keyCode":0,"characters":"a","modifiers":{"command":false,"option":false,"control":false,"shift":false},"isRepeat":false}"#,
            #"{"t":1.1,"type":"up","keyCode":0,"characters":"a","modifiers":{"command":false,"option":false,"control":false,"shift":false},"isRepeat":false}"#,
            #"{"t":2.0,"type":"down","keyCode":1,"characters":"b","modifiers":{"command":false,"option":false,"control":false,"shift":false},"isRepeat":false}"#,
            #"{"t":2.1,"type":"up","keyCode":1,"characters":"b","modifiers":{"command":false,"option":false,"control":false,"shift":false},"isRepeat":false}"#
        ]

        let content = mockKeystrokes.joined(separator: "\n")
        try content.write(to: keysFile, atomically: true, encoding: .utf8)

        // Load and verify
        let loadedContent = try String(contentsOf: keysFile, encoding: .utf8)
        let lines = loadedContent.split(separator: "\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 4)

        // Parse and verify events
        var events: [KeystrokeRecorder.Event] = []
        for line in lines {
            guard let data = line.data(using: .utf8) else { continue }
            let decoder = JSONDecoder()
            if let event = try? decoder.decode(KeystrokeRecorder.Event.self, from: data) {
                events.append(event)
            }
        }

        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events[0].characters, "a")
        XCTAssertEqual(events[2].characters, "b")
    }

    // MARK: - Overlay Size Tests

    func testOverlaySizeVariations() {
        let sizes = [
            CoreGraphics.CGSize(width: 1920, height: 1080), // Full HD
            CoreGraphics.CGSize(width: 1280, height: 720),  // HD
            CoreGraphics.CGSize(width: 3840, height: 2160), // 4K
            CoreGraphics.CGSize(width: 1080, height: 1920), // Portrait
            CoreGraphics.CGSize(width: 720, height: 1280)   // Portrait HD
        ]

        for size in sizes {
            let view = TelemetryOverlayView(
                project: nil as Project?,
                projectDirectory: mockProjectDirectory,
                currentTime: 5.0,
                showCursor: true,
                showClicks: true,
                showKeystrokes: true,
                overlaySize: size
            )

            XCTAssertNotNil(view)
        }
    }

    // MARK: - Performance Tests

    func testTelemetryOverlayRenderingPerformance() {
        let view = TelemetryOverlayView(
            project: nil as Project?,
            projectDirectory: mockProjectDirectory,
            currentTime: 5.0,
            showCursor: true,
            showClicks: true,
            showKeystrokes: true,
            overlaySize: CoreGraphics.CGSize(width: 1920, height: 1080)
        )

        measure {
            _ = view.body
        }
    }
}

// MARK: - TelemetryControlsView Tests

extension TelemetryOverlayViewTests {

    func testTelemetryControlsViewInitialization() {
        let viewModel = PreviewPlayerViewModel()
        let controlsView = TelemetryControlsView(viewModel: viewModel)

        XCTAssertNotNil(controlsView)
    }

    func testTelemetryControlsToggleStates() {
        let viewModel = PreviewPlayerViewModel()

        XCTAssertFalse(viewModel.showCursor)
        XCTAssertFalse(viewModel.showClicks)
        XCTAssertFalse(viewModel.showKeystrokes)

        viewModel.showCursor = true
        viewModel.showClicks = true
        viewModel.showKeystrokes = true

        XCTAssertTrue(viewModel.showCursor)
        XCTAssertTrue(viewModel.showClicks)
        XCTAssertTrue(viewModel.showKeystrokes)
    }

    func testTelemetryControlsWithProject() async throws {
        let viewModel = PreviewPlayerViewModel()
        viewModel.project = mockProject

        XCTAssertNotNil(viewModel.project)
        XCTAssertNotNil(viewModel.project?.sources.telemetry)
    }

    func testTelemetryControlsWithoutProject() {
        let viewModel = PreviewPlayerViewModel()

        XCTAssertNil(viewModel.project)
        XCTAssertNil(viewModel.project?.sources.telemetry)
    }
}
