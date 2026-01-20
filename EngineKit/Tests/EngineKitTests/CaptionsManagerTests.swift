//
//  CaptionsManagerTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

final class CaptionsManagerTests: XCTestCase {
    var tempDirectory: URL!
    var testSRTFile: URL!
    var testVTTFile: URL!

    override func setUp() async throws {
        try await super.setUp()

        // Create temporary directory for test files
        let tempDir = FileManager.default.temporaryDirectory
        tempDirectory = tempDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Create test SRT file
        testSRTFile = tempDirectory.appendingPathComponent("test.srt")
        let srtContent = """
        1
        00:00:00,000 --> 00:00:03,200
        Hello, in this video we're going to explore

        2
        00:00:03,200 --> 00:00:06,800
        how to build a modern macOS application

        3
        00:00:06,800 --> 00:00:10,500
        using SwiftUI and the AVFoundation framework

        4
        00:00:10,500 --> 00:00:15,000
        We'll cover recording, editing, and exporting videos
        """
        try srtContent.write(to: testSRTFile, atomically: true, encoding: .utf8)

        // Create test VTT file
        testVTTFile = tempDirectory.appendingPathComponent("test.vtt")
        let vttContent = """
        WEBVTT

        1
        00:00:00.000 --> 00:00:03.200
        Hello, in this video we're going to explore

        2
        00:00:03.200 --> 00:00:06.800
        how to build a modern macOS application

        3
        00:00:06.800 --> 00:00:10.500
        using SwiftUI and the AVFoundation framework

        4
        00:00:10.500 --> 00:00:15.000
        We'll cover recording, editing, and exporting videos
        """
        try vttContent.write(to: testVTTFile, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitializationWithDefaultStyle() async throws {
        let manager = CaptionsManager()
        let style = await manager.getStyle()

        XCTAssertEqual(style.fontFamily, "Helvetica")
        XCTAssertEqual(style.fontSize, 0.06)
        XCTAssertEqual(style.textColor, "#FFFFFF")
        XCTAssertEqual(style.backgroundColor, "#000000")
        XCTAssertEqual(style.backgroundOpacity, 0.7)
        XCTAssertEqual(style.verticalPosition, 0.1)
        XCTAssertEqual(style.horizontalAlignment, 0.5)
        XCTAssertTrue(style.shadow)
    }

    func testInitializationWithCustomStyle() async throws {
        let customStyle = CaptionsManager.CaptionStyle(
            fontFamily: "Arial",
            fontSize: 0.08,
            textColor: "#FFFF00",
            backgroundColor: "#0000FF",
            backgroundOpacity: 0.9,
            verticalPosition: 0.2,
            horizontalAlignment: 0.3,
            maxLineWidth: 0.7,
            maxLines: 3,
            shadow: false
        )

        let manager = CaptionsManager(style: customStyle)
        let style = await manager.getStyle()

        XCTAssertEqual(style.fontFamily, "Arial")
        XCTAssertEqual(style.fontSize, 0.08)
        XCTAssertEqual(style.textColor, "#FFFF00")
        XCTAssertEqual(style.backgroundColor, "#0000FF")
        XCTAssertEqual(style.backgroundOpacity, 0.9)
        XCTAssertEqual(style.verticalPosition, 0.2)
        XCTAssertEqual(style.horizontalAlignment, 0.3)
        XCTAssertFalse(style.shadow)
    }

    // MARK: - SRT Loading Tests

    func testLoadSRTFile() async throws {
        let manager = CaptionsManager()
        try await manager.loadCaptions(from: testSRTFile.path)

        let hasCaptions = await manager.hasCaptions()
        let captionCount = await manager.getCaptionCount()
        XCTAssertTrue(hasCaptions)
        XCTAssertEqual(captionCount, 4)
    }

    func testLoadSRTFileParseContent() async throws {
        let manager = CaptionsManager()
        try await manager.loadCaptions(from: testSRTFile.path)

        let captions = await manager.getAllCaptions()

        XCTAssertEqual(captions.count, 4)

        // Check first caption
        XCTAssertEqual(captions[0].id, 1)
        XCTAssertEqual(captions[0].start, 0.0)
        XCTAssertEqual(captions[0].end, 3.2)
        XCTAssertEqual(captions[0].text, "Hello, in this video we're going to explore")

        // Check second caption
        XCTAssertEqual(captions[1].id, 2)
        XCTAssertEqual(captions[1].start, 3.2)
        XCTAssertEqual(captions[1].end, 6.8)
        XCTAssertEqual(captions[1].text, "how to build a modern macOS application")

        // Check third caption
        XCTAssertEqual(captions[2].id, 3)
        XCTAssertEqual(captions[2].start, 6.8)
        XCTAssertEqual(captions[2].end, 10.5)

        // Check fourth caption
        XCTAssertEqual(captions[3].id, 4)
        XCTAssertEqual(captions[3].start, 10.5)
        XCTAssertEqual(captions[3].end, 15.0)
    }

    // MARK: - VTT Loading Tests

    func testLoadVTTFile() async throws {
        let manager = CaptionsManager()
        try await manager.loadCaptions(from: testVTTFile.path)

        let hasCaptions_1 = await manager.hasCaptions()


        XCTAssertTrue(hasCaptions_1)
        let getCaptionCount_9 = await manager.getCaptionCount()

        XCTAssertEqual(getCaptionCount_9, 4)
    }

    func testLoadVTTFileParseContent() async throws {
        let manager = CaptionsManager()
        try await manager.loadCaptions(from: testVTTFile.path)

        let captions = await manager.getAllCaptions()

        XCTAssertEqual(captions.count, 4)

        // Check first caption
        XCTAssertEqual(captions[0].id, 1)
        XCTAssertEqual(captions[0].start, 0.0)
        XCTAssertEqual(captions[0].end, 3.2)
        XCTAssertEqual(captions[0].text, "Hello, in this video we're going to explore")

        // Check second caption
        XCTAssertEqual(captions[1].id, 2)
        XCTAssertEqual(captions[1].start, 3.2)
        XCTAssertEqual(captions[1].end, 6.8)
        XCTAssertEqual(captions[1].text, "how to build a modern macOS application")
    }

    // MARK: - Caption Query Tests

    func testGetCaptionAtTime() async throws {
        let manager = CaptionsManager()
        try await manager.loadCaptions(from: testSRTFile.path)

        // Test at start of first caption
        let caption1 = await manager.getCaption(at: 1.0)
        XCTAssertNotNil(caption1)
        XCTAssertEqual(caption1?.id, 1)
        XCTAssertEqual(caption1?.text, "Hello, in this video we're going to explore")

        // Test at middle of second caption
        let caption2 = await manager.getCaption(at: 5.0)
        XCTAssertNotNil(caption2)
        XCTAssertEqual(caption2?.id, 2)

        // Test at gap between captions
        let captionNone = await manager.getCaption(at: 16.0)
        XCTAssertNil(captionNone)

        // Test before any captions
        let captionBefore = await manager.getCaption(at: -1.0)
        XCTAssertNil(captionBefore)
    }

    func testGetCaptionAtBoundary() async throws {
        let manager = CaptionsManager()
        try await manager.loadCaptions(from: testSRTFile.path)

        // Test at exact start time (should be included)
        let captionAtStart = await manager.getCaption(at: 3.2)
        XCTAssertNotNil(captionAtStart)
        XCTAssertEqual(captionAtStart?.id, 2)

        // Test at exact end time (should be included)
        let captionAtEnd = await manager.getCaption(at: 3.2)
        XCTAssertNotNil(captionAtEnd)
    }

    func testGetCaptionByIndex() async throws {
        let manager = CaptionsManager()
        try await manager.loadCaptions(from: testSRTFile.path)

        let caption1 = await manager.getCaption(byIndex: 1)
        XCTAssertNotNil(caption1)
        XCTAssertEqual(caption1?.id, 1)
        XCTAssertEqual(caption1?.text, "Hello, in this video we're going to explore")

        let caption3 = await manager.getCaption(byIndex: 3)
        XCTAssertNotNil(caption3)
        XCTAssertEqual(caption3?.id, 3)

        let captionNone = await manager.getCaption(byIndex: 99)
        XCTAssertNil(captionNone)
    }

    func testGetActiveCaptions() async throws {
        let manager = CaptionsManager()
        try await manager.loadCaptions(from: testSRTFile.path)

        // Test with single active caption
        let captions = await manager.getActiveCaptions(at: 1.0)
        XCTAssertEqual(captions.count, 1)
        XCTAssertEqual(captions[0].id, 1)

        // Test with no active captions
        let captionsNone = await manager.getActiveCaptions(at: 100.0)
        XCTAssertEqual(captionsNone.count, 0)
    }

    // MARK: - Style Management Tests

    func testUpdateStyle() async throws {
        let manager = CaptionsManager()

        var style = await manager.getStyle()
        XCTAssertEqual(style.fontSize, 0.06)

        let newStyle = CaptionsManager.CaptionStyle(fontSize: 0.1)
        await manager.updateStyle(newStyle)

        style = await manager.getStyle()
        XCTAssertEqual(style.fontSize, 0.1)
    }

    func testStylePresets() async throws {
        let defaultStyle = CaptionsManager.CaptionStyle.default
        XCTAssertEqual(defaultStyle.fontSize, 0.06)
        XCTAssertEqual(defaultStyle.maxLines, 2)

        let largeStyle = CaptionsManager.CaptionStyle.large
        XCTAssertEqual(largeStyle.fontSize, 0.08)
        XCTAssertEqual(largeStyle.maxLines, 3)

        let minimalStyle = CaptionsManager.CaptionStyle.minimal
        XCTAssertEqual(minimalStyle.backgroundOpacity, 0.0)
        XCTAssertTrue(minimalStyle.shadow)
    }

    // MARK: - Enable/Disable Tests

    func testSetEnabled() async throws {
        let manager = CaptionsManager()
        try await manager.loadCaptions(from: testSRTFile.path)

        // Initially enabled
        let isEnabled_2 = await manager.isEnabled()

        XCTAssertTrue(isEnabled_2)

        // Disable
        await manager.setEnabled(false)
        let isEnabled_7 = await manager.isEnabled()

        XCTAssertFalse(isEnabled_7)

        // Caption query should return nil when disabled
        let caption = await manager.getCaption(at: 1.0)
        XCTAssertNil(caption)

        // Re-enable
        await manager.setEnabled(true)
        let isEnabled_3 = await manager.isEnabled()

        XCTAssertTrue(isEnabled_3)

        // Caption query should work again
        let caption2 = await manager.getCaption(at: 1.0)
        XCTAssertNotNil(caption2)
    }

    // MARK: - Error Handling Tests

    func testLoadNonExistentFile() async {
        let manager = CaptionsManager()

        do {
            try await manager.loadCaptions(from: "/non/existent/path.srt")
            XCTFail("Should have thrown an error")
        } catch let error as CaptionsManager.CaptionsError {
            switch error {
            case .fileNotFound:
                XCTAssertTrue(true)
            default:
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testLoadEmptyFile() async throws {
        let emptyFile = tempDirectory.appendingPathComponent("empty.srt")
        try "".write(to: emptyFile, atomically: true, encoding: .utf8)

        let manager = CaptionsManager()

        do {
            try await manager.loadCaptions(from: emptyFile.path)
            XCTFail("Should have thrown an error")
        } catch let error as CaptionsManager.CaptionsError {
            switch error {
            case .emptyFile:
                XCTAssertTrue(true)
            default:
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testLoadInvalidSRTFormat() async throws {
        let invalidFile = tempDirectory.appendingPathComponent("invalid.srt")
        try "invalid content without timestamps".write(to: invalidFile, atomically: true, encoding: .utf8)

        let manager = CaptionsManager()

        do {
            try await manager.loadCaptions(from: invalidFile.path)
            XCTFail("Should have thrown an error")
        } catch let error as CaptionsManager.CaptionsError {
            switch error {
            case .parseError:
                XCTAssertTrue(true)
            default:
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testLoadInvalidVTTFormat() async throws {
        let invalidFile = tempDirectory.appendingPathComponent("invalid.vtt")
        try "invalid content without WEBVTT header".write(to: invalidFile, atomically: true, encoding: .utf8)

        let manager = CaptionsManager()

        do {
            try await manager.loadCaptions(from: invalidFile.path)
            XCTFail("Should have thrown an error")
        } catch let error as CaptionsManager.CaptionsError {
            switch error {
            case .invalidFormat:
                XCTAssertTrue(true)
            default:
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Utility Method Tests

    func testGetTimeRange() async throws {
        let manager = CaptionsManager()
        try await manager.loadCaptions(from: testSRTFile.path)

        let range = await manager.getTimeRange()
        XCTAssertNotNil(range)
        XCTAssertEqual(range?.0, 0.0) // Start time
        XCTAssertEqual(range?.1, 15.0) // End time
    }

    func testGetTimeRangeEmpty() async {
        let manager = CaptionsManager()
        let range = await manager.getTimeRange()
        XCTAssertNil(range)
    }

    func testClearCaptions() async throws {
        let manager = CaptionsManager()
        try await manager.loadCaptions(from: testSRTFile.path)

        let hasCaptions_4 = await manager.hasCaptions()


        XCTAssertTrue(hasCaptions_4)
        let getCaptionCount_10 = await manager.getCaptionCount()

        XCTAssertEqual(getCaptionCount_10, 4)

        await manager.clear()

        let hasCaptions_8 = await manager.hasCaptions()


        XCTAssertFalse(hasCaptions_8)
        let getCaptionCount_11 = await manager.getCaptionCount()

        XCTAssertEqual(getCaptionCount_11, 0)
    }

    func testCaptionEntryEquality() async throws {
        let entry1 = CaptionsManager.CaptionEntry(id: 1, start: 0.0, end: 3.2, text: "Test")
        let entry2 = CaptionsManager.CaptionEntry(id: 1, start: 0.0, end: 3.2, text: "Test")
        let entry3 = CaptionsManager.CaptionEntry(id: 2, start: 0.0, end: 3.2, text: "Test")

        XCTAssertEqual(entry1, entry2)
        XCTAssertNotEqual(entry1, entry3)
    }

    // MARK: - Auto-Detection Tests

    func testAutoDetectSRTFormat() async throws {
        // Create file without extension
        let noExtFile = tempDirectory.appendingPathComponent("captions")
        try String(data: Data(contentsOf: testSRTFile), encoding: .utf8)?.write(to: noExtFile, atomically: true, encoding: .utf8)

        let manager = CaptionsManager()
        try await manager.loadCaptions(from: noExtFile.path)

        let hasCaptions_5 = await manager.hasCaptions()


        XCTAssertTrue(hasCaptions_5)
        let getCaptionCount_12 = await manager.getCaptionCount()

        XCTAssertEqual(getCaptionCount_12, 4)
    }

    func testAutoDetectVTTFormat() async throws {
        // Create file without extension
        let noExtFile = tempDirectory.appendingPathComponent("captions")
        try String(data: Data(contentsOf: testVTTFile), encoding: .utf8)?.write(to: noExtFile, atomically: true, encoding: .utf8)

        let manager = CaptionsManager()
        try await manager.loadCaptions(from: noExtFile.path)

        let hasCaptions_6 = await manager.hasCaptions()


        XCTAssertTrue(hasCaptions_6)
        let getCaptionCount_13 = await manager.getCaptionCount()

        XCTAssertEqual(getCaptionCount_13, 4)
    }

    // MARK: - Multi-Line Caption Tests

    func testMultiLineCaptions() async throws {
        let multiLineFile = tempDirectory.appendingPathComponent("multiline.srt")
        let content = """
        1
        00:00:00,000 --> 00:00:03,000
        This is the first line.
        This is the second line.

        2
        00:00:03,000 --> 00:00:06,000
        Another caption
        with multiple lines
        """
        try content.write(to: multiLineFile, atomically: true, encoding: .utf8)

        let manager = CaptionsManager()
        try await manager.loadCaptions(from: multiLineFile.path)

        let captions = await manager.getAllCaptions()
        XCTAssertEqual(captions.count, 2)

        // Check that multi-line text is preserved
        XCTAssertTrue(captions[0].text.contains("first line"))
        XCTAssertTrue(captions[0].text.contains("second line"))

        XCTAssertTrue(captions[1].text.contains("Another caption"))
        XCTAssertTrue(captions[1].text.contains("with multiple lines"))
    }

    // MARK: - Performance Tests

    func testPerformanceCaptionParsing() async throws {
        measure {
            Task {
                let manager = CaptionsManager()
                try? manager.loadCaptions(from: testSRTFile.path)
                _ = await manager.getCaptionCount()
            }
        }
    }

    func testPerformanceCaptionQuery() async throws {
        let manager = CaptionsManager()
        try await manager.loadCaptions(from: testSRTFile.path)

        // Measure performance of caption queries
        let start = Date()
        for i in 0..<1000 {
            let time = Double(i) / 100.0
            _ = await manager.getCaption(at: time)
        }
        let duration = Date().timeIntervalSince(start)

        // Should complete 1000 queries in reasonable time (< 1 second)
        XCTAssertLessThan(duration, 1.0, "Caption queries should be fast")
    }
}
