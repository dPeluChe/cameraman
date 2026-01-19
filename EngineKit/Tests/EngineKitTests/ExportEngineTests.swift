//
//  ExportEngineTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

/// Tests for ExportEngine
final class ExportEngineTests: XCTestCase {
    private var jobQueue: JobQueue!
    private var projectStore: ProjectStore!
    private var exportEngine: ExportEngine!
    private var testProjectDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        jobQueue = JobQueue()
        projectStore = ProjectStore()
        exportEngine = ExportEngine(jobQueue: jobQueue, projectStore: projectStore)

        // Create temporary directory for test projects
        let tempDir = FileManager.default.temporaryDirectory
        testProjectDirectory = tempDir.appendingPathComponent("ExportEngineTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testProjectDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try await super.tearDown()

        // Clean up test directory
        try? FileManager.default.removeItem(at: testProjectDirectory)
    }

    // MARK: - Export Preset Tests

    func testExportPresets() {
        // Test default preset
        let defaultPreset = ExportPreset.web1080h264
        XCTAssertEqual(defaultPreset.id, "web_1080_h264")
        XCTAssertEqual(defaultPreset.name, "Web 1080p (H.264)")
        XCTAssertEqual(defaultPreset.output.width, 1920)
        XCTAssertEqual(defaultPreset.output.height, 1080)
        XCTAssertEqual(defaultPreset.output.fps, 60)
        XCTAssertEqual(defaultPreset.output.codec, "h264")
        XCTAssertEqual(defaultPreset.output.bitrateMbps, 8.0)
        XCTAssertEqual(defaultPreset.output.audioBitrateKbps, 192)

        // Test HEVC preset
        let hevcPreset = ExportPreset.high1080hevc
        XCTAssertEqual(hevcPreset.id, "high_1080_hevc")
        XCTAssertEqual(hevcPreset.output.codec, "hevc")
        XCTAssertEqual(hevcPreset.output.bitrateMbps, 12.0)

        // Test portrait preset
        let portraitPreset = ExportPreset.portrait1080h264
        XCTAssertEqual(portraitPreset.id, "portrait_1080_h264")
        XCTAssertEqual(portraitPreset.output.width, 1080)
        XCTAssertEqual(portraitPreset.output.height, 1920)
    }

    // MARK: - Export Options Tests

    func testExportOptions() {
        // Test default options
        let defaultOptions = ExportOptions.default
        XCTAssertFalse(defaultOptions.burnCaptions)
        XCTAssertTrue(defaultOptions.includeCursorHighlight)
        XCTAssertNil(defaultOptions.outputFilename)

        // Test custom options
        let customOptions = ExportOptions(
            burnCaptions: true,
            includeCursorHighlight: false,
            outputFilename: "custom_export.mp4"
        )
        XCTAssertTrue(customOptions.burnCaptions)
        XCTAssertFalse(customOptions.includeCursorHighlight)
        XCTAssertEqual(customOptions.outputFilename, "custom_export.mp4")
    }

    // MARK: - Error Tests

    func testExportErrors() {
        // Test noSegments error
        let noSegmentsError = ExportError.noSegments
        XCTAssertEqual(noSegmentsError.localizedDescription, "Project has no timeline segments to export")

        // Test sourceFileNotFound error
        let fileNotFoundError = ExportError.sourceFileNotFound("sources/screen.mov")
        XCTAssertTrue(fileNotFoundError.localizedDescription.contains("sources/screen.mov"))

        // Test assetNotReadable error
        let notReadableError = ExportError.assetNotReadable("screen")
        XCTAssertEqual(notReadableError.localizedDescription, "Asset not readable: screen")

        // Test compositionFailed error
        let compositionError = ExportError.compositionFailed("Failed to create video track")
        XCTAssertTrue(compositionError.localizedDescription.contains("Failed to create video track"))

        // Test noVideoTrack error
        let noVideoError = ExportError.noVideoTrack
        XCTAssertEqual(noVideoError.localizedDescription, "No video track found in source asset")

        // Test exportSessionCreationFailed error
        let sessionError = ExportError.exportSessionCreationFailed
        XCTAssertEqual(sessionError.localizedDescription, "Failed to create export session")

        // Test exportFailed error
        let exportFailedError = ExportError.exportFailed("Encoding error")
        XCTAssertTrue(exportFailedError.localizedDescription.contains("Encoding error"))

        // Test outputFileEmpty error
        let emptyError = ExportError.outputFileEmpty
        XCTAssertEqual(emptyError.localizedDescription, "Output file is empty or was not created")

        // Test insufficientDiskSpace error
        let diskError = ExportError.insufficientDiskSpace
        XCTAssertEqual(diskError.localizedDescription, "Insufficient disk space for export")

        // Test audioSyncDrift error
        let driftError = ExportError.audioSyncDrift(0.15) // 150ms
        XCTAssertTrue(driftError.localizedDescription.contains("150"))
    }

    // MARK: - Export Options Equality Tests

    func testExportOptionsEquality() {
        let options1 = ExportOptions.default
        let options2 = ExportOptions(burnCaptions: false, includeCursorHighlight: true, outputFilename: nil)
        let options3 = ExportOptions(burnCaptions: true, includeCursorHighlight: false, outputFilename: "test.mp4")

        XCTAssertEqual(options1, options2)
        XCTAssertNotEqual(options1, options3)
    }

    // MARK: - Export Preset Equality Tests

    func testExportPresetEquality() {
        let preset1 = ExportPreset.web1080h264
        let preset2 = ExportPreset.web1080h264
        let preset3 = ExportPreset.high1080hevc

        XCTAssertEqual(preset1, preset2)
        XCTAssertNotEqual(preset1, preset3)
    }

    // MARK: - Export Error Equality Tests

    func testExportErrorEquality() {
        let error1 = ExportError.sourceFileNotFound("test.mov")
        let error2 = ExportError.sourceFileNotFound("test.mov")
        let error3 = ExportError.sourceFileNotFound("other.mov")
        let error4 = ExportError.noSegments

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
        XCTAssertNotEqual(error1, error4)
    }

    // MARK: - Integration Tests

    func testExportWithNoSegments() async throws {
        // Create a project with no segments
        let projectId = ProjectId()
        let project = createTestProject(
            projectId: projectId,
            segments: []
        )

        try await projectStore.saveProject(project)

        // Attempt export - should fail with noSegments error
        do {
            _ = try await exportEngine.export(projectId: projectId, preset: .web1080h264)
            XCTFail("Export should have failed with noSegments error")
        } catch ExportError.noSegments {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExportWithMissingSourceFile() async throws {
        // Create a project with segments but missing source file
        let projectId = ProjectId()
        let segment = Project.Timeline.Segment(
            id: UUID().uuidString,
            sourceIn: 0,
            sourceOut: 10,
            timelineIn: 0,
            speed: 1.0
        )
        let project = createTestProject(
            projectId: projectId,
            segments: [segment]
        )

        try await projectStore.saveProject(project)

        // Don't create source file - it should fail validation

        // Attempt export - should fail with sourceFileNotFound error
        do {
            _ = try await exportEngine.export(projectId: projectId, preset: .web1080h264)
            XCTFail("Export should have failed with sourceFileNotFound error")
        } catch ExportError.sourceFileNotFound {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExportWithOptions() async throws {
        // Create a project with segments
        let projectId = ProjectId()
        let segment = Project.Timeline.Segment(
            id: UUID().uuidString,
            sourceIn: 0,
            sourceOut: 10,
            timelineIn: 0,
            speed: 1.0
        )
        let project = createTestProject(
            projectId: projectId,
            segments: [segment]
        )

        try await projectStore.saveProject(project)

        // Test export with custom options
        let options = ExportOptions(
            burnCaptions: true,
            includeCursorHighlight: false,
            outputFilename: "custom_export.mp4"
        )

        // Note: This will fail at export stage because we don't have actual video files
        // but it should pass validation and job creation
        let jobId = try await exportEngine.export(
            projectId: projectId,
            preset: .web1080h264,
            options: options
        )

        // Verify job was created
        let job = await jobQueue.getJob(jobId: jobId)
        XCTAssertNotNil(job)
        XCTAssertEqual(job?.type, .export)
        XCTAssertEqual(job?.projectId, projectId)

        // Wait for job to fail (expected due to missing source files)
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        let finalStatus = await jobQueue.getJobStatus(jobId: jobId)
        XCTAssertNotNil(finalStatus)
    }

    func testExportWithDifferentPresets() async throws {
        // Create a project with segments
        let projectId = ProjectId()
        let segment = Project.Timeline.Segment(
            id: UUID().uuidString,
            sourceIn: 0,
            sourceOut: 10,
            timelineIn: 0,
            speed: 1.0
        )
        let project = createTestProject(
            projectId: projectId,
            segments: [segment]
        )

        try await projectStore.saveProject(project)

        // Test export with different presets
        let presets: [ExportPreset] = [
            .web1080h264,
            .high1080hevc,
            .portrait1080h264
        ]

        for preset in presets {
            let jobId = try await exportEngine.export(
                projectId: projectId,
                preset: preset
            )

            // Verify job was created
            let job = await jobQueue.getJob(jobId: jobId)
            XCTAssertNotNil(job)
            XCTAssertEqual(job?.type, .export)
        }
    }

    func testExportWithMultipleSegments() async throws {
        // Create a project with multiple segments
        let projectId = ProjectId()
        let segments = [
            Project.Timeline.Segment(
                id: UUID().uuidString,
                sourceIn: 0,
                sourceOut: 10,
                timelineIn: 0,
                speed: 1.0
            ),
            Project.Timeline.Segment(
                id: UUID().uuidString,
                sourceIn: 15,
                sourceOut: 25,
                timelineIn: 10,
                speed: 1.0
            ),
            Project.Timeline.Segment(
                id: UUID().uuidString,
                sourceIn: 30,
                sourceOut: 45,
                timelineIn: 20,
                speed: 2.0 // 2x speed
            )
        ]
        let project = createTestProject(
            projectId: projectId,
            segments: segments
        )

        try await projectStore.saveProject(project)

        // Test export with multiple segments
        let jobId = try await exportEngine.export(
            projectId: projectId,
            preset: .web1080h264
        )

        // Verify job was created
        let job = await jobQueue.getJob(jobId: jobId)
        XCTAssertNotNil(job)
        XCTAssertEqual(job?.type, .export)
    }

    func testExportCancellation() async throws {
        // Create a project with segments
        let projectId = ProjectId()
        let segment = Project.Timeline.Segment(
            id: UUID().uuidString,
            sourceIn: 0,
            sourceOut: 10,
            timelineIn: 0,
            speed: 1.0
        )
        let project = createTestProject(
            projectId: projectId,
            segments: [segment]
        )

        try await projectStore.saveProject(project)

        // Start export
        let jobId = try await exportEngine.export(
            projectId: projectId,
            preset: .web1080h264
        )

        // Cancel the job immediately
        try await jobQueue.cancelJob(jobId: jobId)

        // Verify job was canceled
        let jobStatus = await jobQueue.getJobStatus(jobId: jobId)
        XCTAssertEqual(jobStatus, .canceled)
    }

    func testExportProgressTracking() async throws {
        // Create a project with segments
        let projectId = ProjectId()
        let segment = Project.Timeline.Segment(
            id: UUID().uuidString,
            sourceIn: 0,
            sourceOut: 10,
            timelineIn: 0,
            speed: 1.0
        )
        let project = createTestProject(
            projectId: projectId,
            segments: [segment]
        )

        try await projectStore.saveProject(project)

        // Start export
        let jobId = try await exportEngine.export(
            projectId: projectId,
            preset: .web1080h264
        )

        // Subscribe to progress updates
        let progressStream = await jobQueue.subscribeToJob(jobId: jobId)

        // Collect progress updates
        var progressUpdates: [Double] = []
        for await _ in progressStream {
            if let status = await jobQueue.getJobStatus(jobId: jobId) {
                progressUpdates.append(status.progress)
                if status.progress >= 0.1 || status == .failed || status == .canceled {
                    break
                }
            }
        }

        // Verify we got some progress updates
        XCTAssertFalse(progressUpdates.isEmpty)
    }

    // MARK: - Helper Methods

    private func createTestProject(
        projectId: ProjectId,
        segments: [Project.Timeline.Segment]
    ) -> Project {
        // Calculate timeline duration from segments
        let duration = segments.reduce(0.0) { max($0, $1.timelineIn + ($1.sourceOut - $1.sourceIn) / $1.speed) }

        return Project(
            schemaVersion: 1,
            projectId: projectId,
            name: "Test Project",
            tags: [],
            createdAt: Date(),
            updatedAt: Date(),
            sources: Project.Sources(
                syncReference: "screen",
                screen: Project.Sources.MediaTrack(
                    path: "sources/screen.mov",
                    fps: 60.0,
                    size: Project.Sources.Size(w: 2880, h: 1800),
                    syncOffsetMs: 0,
                    sha256: "test_sha256",
                    sizeBytes: 524288000
                ),
                camera: nil,
                audio: nil,
                telemetry: nil
            ),
            timeline: Project.Timeline(
                duration: duration,
                segments: segments
            ),
            canvas: Project.Canvas(
                format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                background: Project.Canvas.Background(type: "solid", value: "#0B0B0D", fitMode: "fill"),
                layout: Project.Canvas.Layout(type: "pip", camera: nil)
            ),
            overlays: [],
            captions: nil
        )
    }

    // MARK: - Performance Tests

    func testExportPresetCreationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = ExportPreset.web1080h264
                _ = ExportPreset.high1080hevc
                _ = ExportPreset.portrait1080h264
            }
        }
    }

    func testExportOptionsCreationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = ExportOptions.default
                _ = ExportOptions(burnCaptions: true, includeCursorHighlight: false, outputFilename: "test.mp4")
            }
        }
    }
}
