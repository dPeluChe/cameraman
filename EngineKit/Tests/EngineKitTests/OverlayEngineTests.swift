//
//  OverlayEngineTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

/// Tests for OverlayEngine CRUD operations
final class OverlayEngineTests: XCTestCase {
    var overlayEngine: OverlayEngine!
    var projectStore: ProjectStore!
    var testProjectId: ProjectId!
    var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        // Create temporary directory for test projects
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OverlayEngineTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        projectStore = ProjectStore(baseDirectory: tempDirectory)
        overlayEngine = OverlayEngine(projectStore: projectStore)

        // Create a test project
        testProjectId = try await createTestProject()
    }

    override func tearDown() async throws {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Test Helpers

    func createTestProject() async throws -> ProjectId {
        let recordingResult = RecordingResult(
            screenPath: tempDirectory.appendingPathComponent("screen.mov"),
            cameraPath: nil,
            systemAudioPath: nil,
            micAudioPath: nil,
            telemetryPath: tempDirectory.appendingPathComponent("cursor.jsonl"),
            duration: 60.0,
            startTime: Date(),
            endTime: Date().addingTimeInterval(60.0)
        )

        // Create dummy files
        FileManager.default.createFile(atPath: recordingResult.screenPath.path, contents: Data())
        FileManager.default.createFile(atPath: recordingResult.telemetryPath.path, contents: Data())

        return try await projectStore.createProject(
            from: recordingResult,
            name: "Test Project",
            tags: ["test"]
        )
    }

    func createTestOverlay(
        type: Project.Overlay.OverlayType = .arrow,
        start: TimeInterval = 10.0,
        end: TimeInterval = 15.0,
        x: Double = 0.5,
        y: Double = 0.5
    ) async throws -> UUID {
        let transform = Project.Overlay.Transform(x: x, y: y, scale: 1.0, rotation: 0.0)
        let style = Project.Overlay.Style(
            stroke: "#FFFFFF",
            strokeWidth: 6.0,
            shadow: true,
            text: type == .text ? "Text" : nil,
            imagePath: type == .image ? "image.png" : nil
        )

        let result = try await overlayEngine.addOverlay(
            projectId: testProjectId,
            type: type,
            start: start,
            end: end,
            transform: transform,
            style: style
        )

        switch result {
        case .success(let overlayId):
            return overlayId
        case .failure:
            XCTFail("Failed to create test overlay")
            return UUID()
        }
    }

    // MARK: - Add Overlay Tests

    func testAddArrowOverlay() async throws {
        let transform = Project.Overlay.Transform(x: 0.3, y: 0.4, scale: 1.0, rotation: 0.0)
        let style = Project.Overlay.Style(stroke: "#FF0000", strokeWidth: 8.0, shadow: true)

        let result = try await overlayEngine.addOverlay(
            projectId: testProjectId,
            type: .arrow,
            start: 5.0,
            end: 10.0,
            transform: transform,
            style: style
        )

        switch result {
        case .success(let overlayId):
            // Verify overlay was added
            let overlays = try await overlayEngine.getOverlays(projectId: testProjectId)
            XCTAssertEqual(overlays.count, 1)
            XCTAssertEqual(overlays[0].id, overlayId)
            XCTAssertEqual(overlays[0].type, .arrow)
            XCTAssertEqual(overlays[0].start, 5.0)
            XCTAssertEqual(overlays[0].end, 10.0)
            XCTAssertEqual(overlays[0].transform.x, 0.3)
            XCTAssertEqual(overlays[0].transform.y, 0.4)
            XCTAssertEqual(overlays[0].style.stroke, "#FF0000")
        case .failure(let error):
            XCTFail("Failed to add arrow overlay: \(error.errorDescription ?? "Unknown error")")
        }
    }

    func testAddRectOverlay() async throws {
        let transform = Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0)
        let style = Project.Overlay.Style(stroke: "#00FF00", strokeWidth: 4.0, shadow: false)

        let result = try await overlayEngine.addOverlay(
            projectId: testProjectId,
            type: .rect,
            start: 0.0,
            end: 20.0,
            transform: transform,
            style: style
        )

        switch result {
        case .success(let overlayId):
            let overlays = try await overlayEngine.getOverlays(projectId: testProjectId)
            XCTAssertEqual(overlays.count, 1)
            XCTAssertEqual(overlays[0].id, overlayId)
            XCTAssertEqual(overlays[0].type, .rect)
        case .failure(let error):
            XCTFail("Failed to add rect overlay: \(error.errorDescription ?? "Unknown error")")
        }
    }

    func testAddLineOverlay() async throws {
        let transform = Project.Overlay.Transform(x: 0.2, y: 0.8, scale: 1.5, rotation: 45.0)
        let style = Project.Overlay.Style(stroke: "#0000FF", strokeWidth: 5.0, shadow: true)

        let result = try await overlayEngine.addOverlay(
            projectId: testProjectId,
            type: .line,
            start: 15.0,
            end: 25.0,
            transform: transform,
            style: style
        )

        switch result {
        case .success(let overlayId):
            let overlays = try await overlayEngine.getOverlays(projectId: testProjectId)
            XCTAssertEqual(overlays.count, 1)
            XCTAssertEqual(overlays[0].id, overlayId)
            XCTAssertEqual(overlays[0].type, .line)
            XCTAssertEqual(overlays[0].transform.rotation, 45.0)
        case .failure(let error):
            XCTFail("Failed to add line overlay: \(error.errorDescription ?? "Unknown error")")
        }
    }

    func testAddTextOverlay() async throws {
        let transform = Project.Overlay.Transform(x: 0.1, y: 0.1, scale: 1.0, rotation: 0.0)
        let style = Project.Overlay.Style(
            stroke: "",
            strokeWidth: 0,
            shadow: true,
            font: "Helvetica",
            size: 48.0,
            color: "#FFFFFF",
            bg: "rgba(0,0,0,0.5)",
            text: "Click here"
        )

        let result = try await overlayEngine.addOverlay(
            projectId: testProjectId,
            type: .text,
            start: 0.0,
            end: 5.0,
            transform: transform,
            style: style
        )

        switch result {
        case .success(let overlayId):
            let overlays = try await overlayEngine.getOverlays(projectId: testProjectId)
            XCTAssertEqual(overlays.count, 1)
            XCTAssertEqual(overlays[0].id, overlayId)
            XCTAssertEqual(overlays[0].type, .text)
            XCTAssertEqual(overlays[0].style.text, "Click here")
            XCTAssertEqual(overlays[0].style.font, "Helvetica")
            XCTAssertEqual(overlays[0].style.size, 48.0)
        case .failure(let error):
            XCTFail("Failed to add text overlay: \(error.errorDescription ?? "Unknown error")")
        }
    }

    func testAddMultipleOverlays() async throws {
        // Add multiple overlays
        _ = try await createTestOverlay(type: .arrow, start: 0.0, end: 5.0)
        _ = try await createTestOverlay(type: .rect, start: 5.0, end: 10.0)
        _ = try await createTestOverlay(type: .text, start: 10.0, end: 15.0)

        let overlays = try await overlayEngine.getOverlays(projectId: testProjectId)
        XCTAssertEqual(overlays.count, 3)
    }

    func testAddOverlayInvalidTimeRange() async throws {
        let transform = Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0)
        let style = Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 6.0, shadow: true)

        // Test: start >= end
        do {
            _ = try await overlayEngine.addOverlay(
                projectId: testProjectId,
                type: .arrow,
                start: 10.0,
                end: 5.0, // End before start
                transform: transform,
                style: style
            )
            XCTFail("Should have thrown error for invalid time range")
        } catch OverlayError.invalidTimeRange {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }

        // Test: negative start time
        do {
            _ = try await overlayEngine.addOverlay(
                projectId: testProjectId,
                type: .arrow,
                start: -1.0,
                end: 5.0,
                transform: transform,
                style: style
            )
            XCTFail("Should have thrown error for negative start time")
        } catch OverlayError.invalidTimeRange {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testAddOverlayOutsideTimeline() async throws {
        let transform = Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0)
        let style = Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 6.0, shadow: true)

        // Test: end time exceeds timeline duration
        do {
            _ = try await overlayEngine.addOverlay(
                projectId: testProjectId,
                type: .arrow,
                start: 50.0,
                end: 100.0, // Timeline is 60 seconds
                transform: transform,
                style: style
            )
            XCTFail("Should have thrown error for overlay outside timeline")
        } catch OverlayError.overlayOutsideTimeline {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testInvalidConfigurationIsRejectedWithoutPersistence() async throws {
        let transform = Project.Overlay.Transform(x: 0.5, y: 0.5, scale: .nan)
        let style = Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 6, shadow: false)

        do {
            _ = try await overlayEngine.addOverlay(
                projectId: testProjectId,
                type: .arrow,
                start: 1,
                end: 2,
                transform: transform,
                style: style
            )
            XCTFail("Expected invalid configuration")
        } catch OverlayError.invalidConfiguration {
        } catch {
            XCTFail("Wrong error type: \(error)")
        }

        let overlays = try await overlayEngine.getOverlays(projectId: testProjectId)
        XCTAssertTrue(overlays.isEmpty)
    }

    // MARK: - Update Overlay Tests

    func testUpdateOverlay() async throws {
        let overlayId = try await createTestOverlay()

        let newTransform = Project.Overlay.Transform(x: 0.8, y: 0.8, scale: 1.5, rotation: 90.0)
        let newStyle = Project.Overlay.Style(stroke: "#FFFF00", strokeWidth: 10.0, shadow: false)

        let result = try await overlayEngine.updateOverlay(
            projectId: testProjectId,
            overlayId: overlayId,
            start: 15.0,
            end: 20.0,
            transform: newTransform,
            style: newStyle
        )

        switch result {
        case .success(let updatedId):
            XCTAssertEqual(updatedId, overlayId)

            // Verify updates
            let overlay = try await overlayEngine.getOverlay(projectId: testProjectId, overlayId: overlayId)
            XCTAssertEqual(overlay.start, 15.0)
            XCTAssertEqual(overlay.end, 20.0)
            XCTAssertEqual(overlay.transform.x, 0.8)
            XCTAssertEqual(overlay.transform.y, 0.8)
            XCTAssertEqual(overlay.transform.scale, 1.5)
            XCTAssertEqual(overlay.transform.rotation, 90.0)
            XCTAssertEqual(overlay.style.stroke, "#FFFF00")
            XCTAssertEqual(overlay.style.strokeWidth, 10.0)
            XCTAssertFalse(overlay.style.shadow)
        case .failure(let error):
            XCTFail("Failed to update overlay: \(error.errorDescription ?? "Unknown error")")
        }
    }

    func testInvalidUpdateDoesNotPersistPartialChanges() async throws {
        let overlayId = try await createTestOverlay()
        let original = try await overlayEngine.getOverlay(projectId: testProjectId, overlayId: overlayId)
        var style = original.style
        style.imageOpacity = 2

        do {
            _ = try await overlayEngine.updateOverlay(
                projectId: testProjectId,
                overlayId: overlayId,
                start: 11,
                style: style
            )
            XCTFail("Expected invalid configuration")
        } catch OverlayError.invalidConfiguration {
        } catch {
            XCTFail("Wrong error type: \(error)")
        }

        let unchanged = try await overlayEngine.getOverlay(projectId: testProjectId, overlayId: overlayId)
        XCTAssertEqual(unchanged, original)
    }

    func testUpdateOverlayNotFound() async throws {
        let fakeId = UUID()

        do {
            _ = try await overlayEngine.updateOverlay(
                projectId: testProjectId,
                overlayId: fakeId,
                start: 5.0,
                end: 10.0
            )
            XCTFail("Should have thrown error for non-existent overlay")
        } catch OverlayError.overlayNotFound(let id) {
            XCTAssertEqual(id, fakeId)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testUpdateOverlayPartial() async throws {
        let overlayId = try await createTestOverlay(start: 10.0, end: 15.0)

        // Update only start time
        let result1 = try await overlayEngine.updateOverlay(
            projectId: testProjectId,
            overlayId: overlayId,
            start: 12.0
        )

        switch result1 {
        case .success:
            let overlay = try await overlayEngine.getOverlay(projectId: testProjectId, overlayId: overlayId)
            XCTAssertEqual(overlay.start, 12.0)
            XCTAssertEqual(overlay.end, 15.0) // Unchanged
        case .failure(let error):
            XCTFail("Failed to update overlay: \(error.errorDescription ?? "Unknown error")")
        }

        // Update only end time
        let result2 = try await overlayEngine.updateOverlay(
            projectId: testProjectId,
            overlayId: overlayId,
            end: 18.0
        )

        switch result2 {
        case .success:
            let overlay = try await overlayEngine.getOverlay(projectId: testProjectId, overlayId: overlayId)
            XCTAssertEqual(overlay.start, 12.0)
            XCTAssertEqual(overlay.end, 18.0)
        case .failure(let error):
            XCTFail("Failed to update overlay: \(error.errorDescription ?? "Unknown error")")
        }
    }

    // MARK: - Delete Overlay Tests

    func testDeleteOverlay() async throws {
        let overlayId = try await createTestOverlay()

        // Verify overlay exists
        var overlays = try await overlayEngine.getOverlays(projectId: testProjectId)
        XCTAssertEqual(overlays.count, 1)

        // Delete overlay
        let result = try await overlayEngine.deleteOverlay(
            projectId: testProjectId,
            overlayId: overlayId
        )

        switch result {
        case .success(let deletedId):
            XCTAssertEqual(deletedId, overlayId)

            // Verify deletion
            overlays = try await overlayEngine.getOverlays(projectId: testProjectId)
            XCTAssertEqual(overlays.count, 0)
        case .failure(let error):
            XCTFail("Failed to delete overlay: \(error.errorDescription ?? "Unknown error")")
        }
    }

    func testDeleteOverlayNotFound() async throws {
        let fakeId = UUID()

        do {
            _ = try await overlayEngine.deleteOverlay(
                projectId: testProjectId,
                overlayId: fakeId
            )
            XCTFail("Should have thrown error for non-existent overlay")
        } catch OverlayError.overlayNotFound(let id) {
            XCTAssertEqual(id, fakeId)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testDeleteOverlaysInRange() async throws {
        // Create overlays at different time ranges
        _ = try await createTestOverlay(start: 0.0, end: 5.0) // Inside range
        _ = try await createTestOverlay(start: 5.0, end: 10.0) // Inside range
        _ = try await createTestOverlay(start: 10.0, end: 15.0) // Partially overlaps
        _ = try await createTestOverlay(start: 20.0, end: 25.0) // Outside range

        // Delete overlays in range 0-12
        let result = try await overlayEngine.deleteOverlaysInRange(
            projectId: testProjectId,
            start: 0.0,
            end: 12.0
        )

        switch result {
        case .success(let count):
            XCTAssertEqual(count, 3) // Should delete 3 overlays (first 3)

            // Verify remaining overlay
            let overlays = try await overlayEngine.getOverlays(projectId: testProjectId)
            XCTAssertEqual(overlays.count, 1)
            XCTAssertEqual(overlays[0].start, 20.0)
        case .failure(let error):
            XCTFail("Failed to delete overlays in range: \(error.errorDescription ?? "Unknown error")")
        }
    }

    func testDeleteAllOverlays() async throws {
        // Create multiple overlays
        _ = try await createTestOverlay(start: 0.0, end: 5.0)
        _ = try await createTestOverlay(start: 5.0, end: 10.0)
        _ = try await createTestOverlay(start: 10.0, end: 15.0)

        // Verify count
        var overlays = try await overlayEngine.getOverlays(projectId: testProjectId)
        XCTAssertEqual(overlays.count, 3)

        // Delete all
        let result = try await overlayEngine.deleteAllOverlays(projectId: testProjectId)

        switch result {
        case .success(let count):
            XCTAssertEqual(count, 3)

            // Verify all deleted
            overlays = try await overlayEngine.getOverlays(projectId: testProjectId)
            XCTAssertEqual(overlays.count, 0)
        case .failure(let error):
            XCTFail("Failed to delete all overlays: \(error.errorDescription ?? "Unknown error")")
        }
    }

    // MARK: - Get Overlay Tests

    func testGetOverlay() async throws {
        let overlayId = try await createTestOverlay(
            type: .text,
            start: 5.0,
            end: 10.0,
            x: 0.3,
            y: 0.7
        )

        let overlay = try await overlayEngine.getOverlay(
            projectId: testProjectId,
            overlayId: overlayId
        )

        XCTAssertEqual(overlay.id, overlayId)
        XCTAssertEqual(overlay.type, .text)
        XCTAssertEqual(overlay.start, 5.0)
        XCTAssertEqual(overlay.end, 10.0)
        XCTAssertEqual(overlay.transform.x, 0.3)
        XCTAssertEqual(overlay.transform.y, 0.7)
    }

    func testGetOverlayNotFound() async throws {
        let fakeId = UUID()

        do {
            _ = try await overlayEngine.getOverlay(
                projectId: testProjectId,
                overlayId: fakeId
            )
            XCTFail("Should have thrown error for non-existent overlay")
        } catch OverlayError.overlayNotFound(let id) {
            XCTAssertEqual(id, fakeId)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testGetOverlaysInRange() async throws {
        // Create overlays at different time ranges
        _ = try await createTestOverlay(start: 0.0, end: 5.0)
        _ = try await createTestOverlay(start: 5.0, end: 10.0)
        _ = try await createTestOverlay(start: 10.0, end: 15.0)
        _ = try await createTestOverlay(start: 20.0, end: 25.0)

        // Get overlays in range 0-12
        let overlays = try await overlayEngine.getOverlaysInRange(
            projectId: testProjectId,
            start: 0.0,
            end: 12.0
        )

        XCTAssertEqual(overlays.count, 3)
        // Should be sorted by start time
        XCTAssertEqual(overlays[0].start, 0.0)
        XCTAssertEqual(overlays[1].start, 5.0)
        XCTAssertEqual(overlays[2].start, 10.0)
    }

    func testGetOverlaysSorted() async throws {
        // Create overlays in random order
        _ = try await createTestOverlay(start: 20.0, end: 25.0)
        _ = try await createTestOverlay(start: 0.0, end: 5.0)
        _ = try await createTestOverlay(start: 10.0, end: 15.0)
        _ = try await createTestOverlay(start: 5.0, end: 10.0)

        let overlays = try await overlayEngine.getOverlays(projectId: testProjectId)

        XCTAssertEqual(overlays.count, 4)
        // Should be sorted by start time
        XCTAssertEqual(overlays[0].start, 0.0)
        XCTAssertEqual(overlays[1].start, 5.0)
        XCTAssertEqual(overlays[2].start, 10.0)
        XCTAssertEqual(overlays[3].start, 20.0)
    }

    // MARK: - Duplicate Overlay Tests

    func testDuplicateOverlay() async throws {
        let overlayId = try await createTestOverlay(
            type: .arrow,
            start: 10.0,
            end: 15.0,
            x: 0.5,
            y: 0.5
        )

        let result = try await overlayEngine.duplicateOverlay(
            projectId: testProjectId,
            overlayId: overlayId,
            timeOffset: 10.0
        )

        switch result {
        case .success(let newOverlayId):
            XCTAssertNotEqual(newOverlayId, overlayId)

            // Verify both overlays exist
            let overlays = try await overlayEngine.getOverlays(projectId: testProjectId)
            XCTAssertEqual(overlays.count, 2)

            // Find original and duplicate
            let original = overlays.first { $0.id == overlayId }!
            let duplicate = overlays.first { $0.id == newOverlayId }!

            XCTAssertEqual(original.start, 10.0)
            XCTAssertEqual(original.end, 15.0)

            XCTAssertEqual(duplicate.start, 20.0) // 10.0 + 10.0 offset
            XCTAssertEqual(duplicate.end, 25.0)  // 15.0 + 10.0 offset
            XCTAssertEqual(duplicate.transform.x, 0.5)
            XCTAssertEqual(duplicate.transform.y, 0.5)
        case .failure(let error):
            XCTFail("Failed to duplicate overlay: \(error.errorDescription ?? "Unknown error")")
        }
    }

    func testDuplicateOverlayNotFound() async throws {
        let fakeId = UUID()

        do {
            _ = try await overlayEngine.duplicateOverlay(
                projectId: testProjectId,
                overlayId: fakeId
            )
            XCTFail("Should have thrown error for non-existent overlay")
        } catch OverlayError.overlayNotFound(let id) {
            XCTAssertEqual(id, fakeId)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Convenience Method Tests

    func testAddArrowOverlayConvenience() async throws {
        let result = try await overlayEngine.addArrowOverlay(
            projectId: testProjectId,
            start: 5.0,
            end: 10.0,
            x: 0.3,
            y: 0.4,
            scale: 1.5,
            rotation: 45.0,
            stroke: "#FF0000",
            strokeWidth: 10.0,
            shadow: false
        )

        switch result {
        case .success(let overlayId):
            let overlay = try await overlayEngine.getOverlay(
                projectId: testProjectId,
                overlayId: overlayId
            )
            XCTAssertEqual(overlay.type, .arrow)
            XCTAssertEqual(overlay.start, 5.0)
            XCTAssertEqual(overlay.end, 10.0)
            XCTAssertEqual(overlay.transform.x, 0.3)
            XCTAssertEqual(overlay.transform.y, 0.4)
            XCTAssertEqual(overlay.transform.scale, 1.5)
            XCTAssertEqual(overlay.transform.rotation, 45.0)
            XCTAssertEqual(overlay.style.stroke, "#FF0000")
            XCTAssertEqual(overlay.style.strokeWidth, 10.0)
            XCTAssertFalse(overlay.style.shadow)
        case .failure(let error):
            XCTFail("Failed to add arrow overlay: \(error.errorDescription ?? "Unknown error")")
        }
    }

    func testAddRectOverlayConvenience() async throws {
        let result = try await overlayEngine.addRectOverlay(
            projectId: testProjectId,
            start: 0.0,
            end: 20.0,
            x: 0.5,
            y: 0.5,
            stroke: "#00FF00",
            strokeWidth: 8.0
        )

        switch result {
        case .success(let overlayId):
            let overlay = try await overlayEngine.getOverlay(
                projectId: testProjectId,
                overlayId: overlayId
            )
            XCTAssertEqual(overlay.type, .rect)
            XCTAssertEqual(overlay.style.stroke, "#00FF00")
        case .failure(let error):
            XCTFail("Failed to add rect overlay: \(error.errorDescription ?? "Unknown error")")
        }
    }

    func testAddLineOverlayConvenience() async throws {
        let result = try await overlayEngine.addLineOverlay(
            projectId: testProjectId,
            start: 10.0,
            end: 15.0,
            x: 0.2,
            y: 0.8,
            rotation: 30.0
        )

        switch result {
        case .success(let overlayId):
            let overlay = try await overlayEngine.getOverlay(
                projectId: testProjectId,
                overlayId: overlayId
            )
            XCTAssertEqual(overlay.type, .line)
            XCTAssertEqual(overlay.transform.rotation, 30.0)
        case .failure(let error):
            XCTFail("Failed to add line overlay: \(error.errorDescription ?? "Unknown error")")
        }
    }

    func testAddTextOverlayConvenience() async throws {
        let result = try await overlayEngine.addTextOverlay(
            projectId: testProjectId,
            start: 0.0,
            end: 5.0,
            x: 0.1,
            y: 0.1,
            text: "Hello World",
            font: "Courier",
            size: 36.0,
            color: "#FFFF00",
            bg: "rgba(255,0,0,0.3)"
        )

        switch result {
        case .success(let overlayId):
            let overlay = try await overlayEngine.getOverlay(
                projectId: testProjectId,
                overlayId: overlayId
            )
            XCTAssertEqual(overlay.type, .text)
            XCTAssertEqual(overlay.style.text, "Hello World")
            XCTAssertEqual(overlay.style.font, "Courier")
            XCTAssertEqual(overlay.style.size, 36.0)
            XCTAssertEqual(overlay.style.color, "#FFFF00")
            XCTAssertEqual(overlay.style.bg, "rgba(255,0,0,0.3)")
        case .failure(let error):
            XCTFail("Failed to add text overlay: \(error.errorDescription ?? "Unknown error")")
        }
    }

    // MARK: - Project Not Found Tests

    func testOperationsOnNonExistentProject() async throws {
        let fakeProjectId = ProjectId()
        let transform = Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0.0)
        let style = Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 6.0, shadow: true)

        // Test add overlay
        do {
            _ = try await overlayEngine.addOverlay(
                projectId: fakeProjectId,
                type: .arrow,
                start: 0.0,
                end: 5.0,
                transform: transform,
                style: style
            )
            XCTFail("Should have thrown error for non-existent project")
        } catch EngineKitError.projectNotFound(let id) {
            XCTAssertEqual(id, fakeProjectId)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }

        // Test get overlays
        do {
            _ = try await overlayEngine.getOverlays(projectId: fakeProjectId)
            XCTFail("Should have thrown error for non-existent project")
        } catch EngineKitError.projectNotFound(let id) {
            XCTAssertEqual(id, fakeProjectId)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Performance Tests

    func testAddManyOverlaysPerformance() async throws {
        // The test fixture's timeline is 60 seconds. Earlier this loop ran
        // with `start: Double(i), end: Double(i + 1)` for i in 0..<100, so
        // every overlay past index 59 was rejected with overlayOutsideTimeline.
        // Pack the 100 overlays into the available 60-second window instead.
        measure {
            let group = DispatchGroup()
            var errors: [Error?] = []

            for i in 0..<100 {
                let start = Double(i) * 0.5   // 0.0, 0.5, ..., 49.5
                let end = start + 0.4         // 0.4, 0.9, ..., 49.9 — all < 60s

                group.enter()
                Task {
                    do {
                        _ = try await createTestOverlay(start: start, end: end)
                    } catch {
                        errors.append(error)
                    }
                    group.leave()
                }
            }

            group.wait()
            XCTAssertTrue(errors.isEmpty, "Errors occurred: \(errors.compactMap { $0 })")
        }
    }
}
