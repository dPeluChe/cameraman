//
//  PreviewEngineTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

@available(macOS 13.0, *)
final class PreviewEngineTests: XCTestCase {

    var previewEngine: PreviewEngine!
    var mockProject: Project!

    override func setUp() async throws {
        try await super.setUp()

        previewEngine = PreviewEngine()

        // Create a mock project for testing
        mockProject = createMockProject()
    }

    override func tearDown() async throws {
        previewEngine = nil
        mockProject = nil

        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func createMockProject() -> Project {
        let screenTrack = Project.Sources.MediaTrack(
            path: "/tmp/test_screen.mov",
            fps: 60.0,
            size: Project.Sources.Size(w: 1920, h: 1080),
            syncOffsetMs: 0,
            sha256: "abc123",
            sizeBytes: 1024000
        )

        let segments = [
            Project.Timeline.Segment(
                id: "segment-1",
                sourceIn: 0,
                sourceOut: 5,
                timelineIn: 0,
                speed: 1.0
            ),
            Project.Timeline.Segment(
                id: "segment-2",
                sourceIn: 5,
                sourceOut: 10,
                timelineIn: 5,
                speed: 1.0
            )
        ]

        let timeline = Project.Timeline(duration: 10, segments: segments)

        let canvas = Project.Canvas(
            format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
            background: Project.Canvas.Background(type: "color", value: "#000000", fitMode: nil),
            layout: Project.Canvas.Layout(type: "fullscreen", camera: nil)
        )

        let sources = Project.Sources(
            syncReference: "screen",
            screen: screenTrack,
            camera: nil,
            audio: nil,
            telemetry: nil
        )

        return Project(
            schemaVersion: 1,
            projectId: UUID(),
            name: "Test Project",
            tags: [],
            createdAt: Date(),
            updatedAt: Date(),
            sources: sources,
            timeline: timeline,
            canvas: canvas,
            overlays: [],
            captions: nil
        )
    }

    // MARK: - Initialization Tests

    func testInitializationWithDefaultConfiguration() {
        let engine = PreviewEngine()
        XCTAssertNotNil(engine)
    }

    func testInitializationWithCustomConfiguration() {
        let config = PreviewEngine.Configuration(
            useProxy: false,
            proxyWidth: 1920,
            proxyHeight: 1080,
            hardwareAcceleration: true
        )
        let engine = PreviewEngine(configuration: config)
        XCTAssertNotNil(engine)
    }

    func testConfigurationDefaultValues() {
        let config = PreviewEngine.Configuration.`default`
        XCTAssertTrue(config.useProxy)
        XCTAssertEqual(config.proxyWidth, 1280)
        XCTAssertEqual(config.proxyHeight, 720)
        XCTAssertTrue(config.hardwareAcceleration)
    }

    func testConfigurationHighQuality() {
        let config = PreviewEngine.Configuration.highQuality
        XCTAssertFalse(config.useProxy)
        XCTAssertEqual(config.proxyWidth, 1280)
        XCTAssertEqual(config.proxyHeight, 720)
        XCTAssertTrue(config.hardwareAcceleration)
    }

    // MARK: - Project Loading Tests

    func testLoadProjectSuccessfully() async throws {
        try await previewEngine.loadProject(mockProject)

        let session = await previewEngine.getSession()
        XCTAssertEqual(session.state, .stopped)
        XCTAssertEqual(session.currentTime, 0)
        XCTAssertEqual(session.duration, 10)
    }

    func testLoadProjectWithNoSegments() async {
        var emptyProject = createMockProject()
        emptyProject.timeline.segments = []

        do {
            try await previewEngine.loadProject(emptyProject)
            XCTFail("Should have thrown PreviewError.noSegments")
        } catch let error as PreviewEngine.PreviewErrornoSegments {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testUnloadProject() async throws {
        try await previewEngine.loadProject(mockProject)
        await previewEngine.unloadProject()

        let session = await previewEngine.getSession()
        XCTAssertEqual(session.state, .stopped)
        XCTAssertEqual(session.currentTime, 0)
        XCTAssertEqual(session.duration, 0)
    }

    // MARK: - Playback Control Tests

    func testPlay() async throws {
        try await previewEngine.loadProject(mockProject)
        try await previewEngine.play()

        let session = await previewEngine.getSession()
        XCTAssertEqual(session.state, .playing)
        XCTAssertTrue(await previewEngine.isPlaying())
    }

    func testPlayWithoutProject() async {
        do {
            try await previewEngine.play()
            XCTFail("Should have thrown PreviewError.noProjectLoaded")
        } catch let error as PreviewEngine.PreviewErrornoProjectLoaded {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testPause() async throws {
        try await previewEngine.loadProject(mockProject)
        try await previewEngine.play()
        try await previewEngine.pause()

        let session = await previewEngine.getSession()
        XCTAssertEqual(session.state, .paused)
        XCTAssertTrue(await previewEngine.isPaused())
    }

    func testPauseWithoutProject() async {
        do {
            try await previewEngine.pause()
            XCTFail("Should have thrown PreviewError.noProjectLoaded")
        } catch let error as PreviewEngine.PreviewErrornoProjectLoaded {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testStop() async throws {
        try await previewEngine.loadProject(mockProject)
        try await previewEngine.play()
        try await previewEngine.stop()

        let session = await previewEngine.getSession()
        XCTAssertEqual(session.state, .stopped)
        XCTAssertEqual(session.currentTime, 0)
        XCTAssertTrue(await previewEngine.isStopped())
    }

    func testStopWithoutProject() async {
        do {
            try await previewEngine.stop()
            XCTFail("Should have thrown PreviewError.noProjectLoaded")
        } catch let error as PreviewEngine.PreviewErrornoProjectLoaded {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testSeek() async throws {
        try await previewEngine.loadProject(mockProject)
        try await previewEngine.seek(to: 5.0)

        let session = await previewEngine.getSession()
        XCTAssertEqual(session.currentTime, 5.0)
    }

    func testSeekWithoutProject() async {
        do {
            try await previewEngine.seek(to: 5.0)
            XCTFail("Should have thrown PreviewError.noProjectLoaded")
        } catch let error as PreviewEngine.PreviewErrornoProjectLoaded {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testSeekToInvalidTimeNegative() async throws {
        try await previewEngine.loadProject(mockProject)

        do {
            try await previewEngine.seek(to: -1.0)
            XCTFail("Should have thrown PreviewError.invalidTime")
        } catch PreviewEngine.PreviewError.invalidTime {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testSeekToInvalidTimeTooLarge() async throws {
        try await previewEngine.loadProject(mockProject)

        do {
            try await previewEngine.seek(to: 100.0)
            XCTFail("Should have thrown PreviewError.invalidTime")
        } catch PreviewEngine.PreviewError.invalidTime {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testSeekToStart() async throws {
        try await previewEngine.loadProject(mockProject)
        try await previewEngine.seek(to: 5.0)
        try await previewEngine.seek(to: 0)

        XCTAssertEqual(await previewEngine.getCurrentTime(), 0)
    }

    func testSeekToEnd() async throws {
        try await previewEngine.loadProject(mockProject)
        try await previewEngine.seek(to: 10)

        XCTAssertEqual(await previewEngine.getCurrentTime(), 10)
    }

    // MARK: - Playback Rate Tests

    func testSetPlaybackRateNormal() async throws {
        try await previewEngine.loadProject(mockProject)
        try await previewEngine.setPlaybackRate(1.0)

        let session = await previewEngine.getSession()
        XCTAssertEqual(session.playbackRate, 1.0)
    }

    func testSetPlaybackRateDouble() async throws {
        try await previewEngine.loadProject(mockProject)
        try await previewEngine.setPlaybackRate(2.0)

        let session = await previewEngine.getSession()
        XCTAssertEqual(session.playbackRate, 2.0)
    }

    func testSetPlaybackRateHalf() async throws {
        try await previewEngine.loadProject(mockProject)
        try await previewEngine.setPlaybackRate(0.5)

        let session = await previewEngine.getSession()
        XCTAssertEqual(session.playbackRate, 0.5)
    }

    func testSetPlaybackRateWithoutProject() async {
        do {
            try await previewEngine.setPlaybackRate(2.0)
            XCTFail("Should have thrown PreviewError.noProjectLoaded")
        } catch let error as PreviewEngine.PreviewErrornoProjectLoaded {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testSetPlaybackRateTooLow() async throws {
        try await previewEngine.loadProject(mockProject)

        do {
            try await previewEngine.setPlaybackRate(0)
            XCTFail("Should have thrown PreviewError.playbackFailed")
        } catch let error as PreviewEngine.PreviewErrorplaybackFailed {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testSetPlaybackRateTooHigh() async throws {
        try await previewEngine.loadProject(mockProject)

        do {
            try await previewEngine.setPlaybackRate(5.0)
            XCTFail("Should have thrown PreviewError.playbackFailed")
        } catch let error as PreviewEngine.PreviewErrorplaybackFailed {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Looping Tests

    func testEnableLooping() async throws {
        try await previewEngine.loadProject(mockProject)
        await previewEngine.setLooping(true)

        let session = await previewEngine.getSession()
        XCTAssertTrue(session.isLooping)
    }

    func testDisableLooping() async throws {
        try await previewEngine.loadProject(mockProject)
        await previewEngine.setLooping(true)
        await previewEngine.setLooping(false)

        let session = await previewEngine.getSession()
        XCTAssertFalse(session.isLooping)
    }

    // MARK: - State Query Tests

    func testGetSession() async throws {
        try await previewEngine.loadProject(mockProject)

        let session = await previewEngine.getSession()
        XCTAssertEqual(session.state, .stopped)
        XCTAssertEqual(session.currentTime, 0)
        XCTAssertEqual(session.duration, 10)
        XCTAssertEqual(session.playbackRate, 1.0)
        XCTAssertFalse(session.isLooping)
    }

    func testGetCurrentTime() async throws {
        try await previewEngine.loadProject(mockProject)
        XCTAssertEqual(await previewEngine.getCurrentTime(), 0)
    }

    func testGetDuration() async throws {
        try await previewEngine.loadProject(mockProject)
        XCTAssertEqual(await previewEngine.getDuration(), 10)
    }

    func testGetPlaybackState() async throws {
        try await previewEngine.loadProject(mockProject)
        XCTAssertEqual(await previewEngine.getPlaybackState(), .stopped)
    }

    func testIsPlaying() async throws {
        try await previewEngine.loadProject(mockProject)
        XCTAssertFalse(await previewEngine.isPlaying())

        try await previewEngine.play()
        XCTAssertTrue(await previewEngine.isPlaying())
    }

    func testIsPaused() async throws {
        try await previewEngine.loadProject(mockProject)
        XCTAssertFalse(await previewEngine.isPaused())

        try await previewEngine.play()
        XCTAssertFalse(await previewEngine.isPaused())

        try await previewEngine.pause()
        XCTAssertTrue(await previewEngine.isPaused())
    }

    func testIsStopped() async throws {
        try await previewEngine.loadProject(mockProject)
        XCTAssertTrue(await previewEngine.isStopped())

        try await previewEngine.play()
        XCTAssertFalse(await previewEngine.isStopped())

        try await previewEngine.stop()
        XCTAssertTrue(await previewEngine.isStopped())
    }

    // MARK: - Error Description Tests

    func testErrorDescriptions() {
        XCTAssertEqual(
            PreviewError.noProjectLoaded.localizedDescription,
            "No project loaded for preview"
        )

        XCTAssertEqual(
            PreviewError.projectLoadFailed("test reason").localizedDescription,
            "Failed to load project: test reason"
        )

        XCTAssertEqual(
            PreviewError.playbackFailed("test reason").localizedDescription,
            "Playback failed: test reason"
        )

        XCTAssertEqual(
            PreviewError.seekFailed("test reason").localizedDescription,
            "Seek failed: test reason"
        )

        XCTAssertEqual(
            PreviewError.invalidTime(5.0).localizedDescription,
            "Invalid time: 5.0s"
        )

        XCTAssertEqual(
            PreviewError.noSegments.localizedDescription,
            "Project has no segments to preview"
        )

        XCTAssertEqual(
            PreviewError.mediaFileNotFound("/tmp/test.mov").localizedDescription,
            "Media file not found: /tmp/test.mov"
        )
    }

    // MARK: - PlaybackState Tests

    func testPlaybackStateEquality() {
        XCTAssertEqual(PreviewEngine.PlaybackState.stopped, .stopped)
        XCTAssertEqual(PreviewEngine.PlaybackState.playing, .playing)
        XCTAssertEqual(PreviewEngine.PlaybackState.paused, .paused)

        XCTAssertNotEqual(PreviewEngine.PlaybackState.playing, .paused)
        XCTAssertNotEqual(PreviewEngine.PlaybackState.stopped, .playing)
    }

    // MARK: - PreviewSession Tests

    func testPreviewSessionInitialization() {
        let session = PreviewEngine.PreviewSession(
            state: .playing,
            currentTime: 5.0,
            duration: 10.0,
            playbackRate: 1.5,
            isLooping: true
        )

        XCTAssertEqual(session.state, .playing)
        XCTAssertEqual(session.currentTime, 5.0)
        XCTAssertEqual(session.duration, 10.0)
        XCTAssertEqual(session.playbackRate, 1.5)
        XCTAssertTrue(session.isLooping)
    }

    // MARK: - Multi-Segment Project Tests

    func testLoadProjectWithMultipleSegments() async throws {
        let segments = [
            Project.Timeline.Segment(id: "seg1", sourceIn: 0, sourceOut: 3, timelineIn: 0, speed: 1.0),
            Project.Timeline.Segment(id: "seg2", sourceIn: 3, sourceOut: 6, timelineIn: 3, speed: 1.0),
            Project.Timeline.Segment(id: "seg3", sourceIn: 6, sourceOut: 10, timelineIn: 6, speed: 1.0)
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 10, segments: segments)

        try await previewEngine.loadProject(project)

        let session = await previewEngine.getSession()
        XCTAssertEqual(session.duration, 10)
    }

    func testLoadProjectWithSpeedChanges() async throws {
        let segments = [
            Project.Timeline.Segment(id: "seg1", sourceIn: 0, sourceOut: 5, timelineIn: 0, speed: 2.0),
            Project.Timeline.Segment(id: "seg2", sourceIn: 5, sourceOut: 10, timelineIn: 2.5, speed: 1.0)
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 7.5, segments: segments)

        try await previewEngine.loadProject(project)

        let session = await previewEngine.getSession()
        XCTAssertEqual(session.duration, 7.5)
    }

    // MARK: - Performance Tests

    func testPerformanceLoadProject() {
        measure {
            Task {
                let engine = PreviewEngine()
                try? await engine.loadProject(mockProject)
            }
        }
    }

    func testPerformanceSeek() async throws {
        try await previewEngine.loadProject(mockProject)

        measure {
            Task {
                try? await previewEngine.seek(to: 5.0)
            }
        }
    }

    func testPerformanceGetSession() async throws {
        try await previewEngine.loadProject(mockProject)

        measure {
            _ = await previewEngine.getSession()
        }
    }

    // MARK: - Overlay Rendering Tests

    func testGetActiveOverlaysWithoutProject() async {
        let overlays = await previewEngine.getActiveOverlays(at: 5.0)
        XCTAssertTrue(overlays.isEmpty)
    }

    func testGetActiveOverlaysWithProject() async throws {
        var project = createMockProject()
        project.overlays = [
            createMockOverlay(type: .arrow, start: 0, end: 5),
            createMockOverlay(type: .rect, start: 5, end: 10)
        ]

        try await previewEngine.loadProject(project)

        // Get active overlays at t=2.5 (should be only arrow)
        let overlaysAt2_5 = await previewEngine.getActiveOverlays(at: 2.5)
        XCTAssertEqual(overlaysAt2_5.count, 1)
        XCTAssertEqual(overlaysAt2_5.first?.type, .arrow)

        // Get active overlays at t=7.5 (should be only rect)
        let overlaysAt7_5 = await previewEngine.getActiveOverlays(at: 7.5)
        XCTAssertEqual(overlaysAt7_5.count, 1)
        XCTAssertEqual(overlaysAt7_5.first?.type, .rect)
    }

    func testGetActiveOverlaysAtBoundaries() async throws {
        var project = createMockProject()
        project.overlays = [
            createMockOverlay(type: .arrow, start: 2, end: 5)
        ]

        try await previewEngine.loadProject(project)

        // At exact start time
        let overlaysAtStart = await previewEngine.getActiveOverlays(at: 2.0)
        XCTAssertEqual(overlaysAtStart.count, 1)

        // At exact end time
        let overlaysAtEnd = await previewEngine.getActiveOverlays(at: 5.0)
        XCTAssertEqual(overlaysAtEnd.count, 1)

        // Before start time
        let overlaysBefore = await previewEngine.getActiveOverlays(at: 1.9)
        XCTAssertEqual(overlaysBefore.count, 0)

        // After end time
        let overlaysAfter = await previewEngine.getActiveOverlays(at: 5.1)
        XCTAssertEqual(overlaysAfter.count, 0)
    }

    func testGetActiveOverlaysMultiple() async throws {
        var project = createMockProject()
        project.overlays = [
            createMockOverlay(type: .arrow, start: 0, end: 10),
            createMockOverlay(type: .rect, start: 2, end: 5),
            createMockOverlay(type: .line, start: 3, end: 7),
            createMockOverlay(type: .text, start: 0, end: 3)
        ]

        try await previewEngine.loadProject(project)

        // At t=1 (arrow, text)
        let overlaysAt1 = await previewEngine.getActiveOverlays(at: 1.0)
        XCTAssertEqual(overlaysAt1.count, 2)

        // At t=2.5 (arrow, rect, line, text)
        let overlaysAt2_5 = await previewEngine.getActiveOverlays(at: 2.5)
        XCTAssertEqual(overlaysAt2_5.count, 4)

        // At t=4 (arrow, rect, line)
        let overlaysAt4 = await previewEngine.getActiveOverlays(at: 4.0)
        XCTAssertEqual(overlaysAt4.count, 3)

        // At t=8 (arrow, line)
        let overlaysAt8 = await previewEngine.getActiveOverlays(at: 8.0)
        XCTAssertEqual(overlaysAt8.count, 2)
    }

    func testGetActiveOverlaysAllTypes() async throws {
        var project = createMockProject()
        project.overlays = [
            createMockOverlay(type: .arrow, start: 0, end: 10),
            createMockOverlay(type: .rect, start: 0, end: 10),
            createMockOverlay(type: .line, start: 0, end: 10),
            createMockOverlay(type: .text, start: 0, end: 10)
        ]

        try await previewEngine.loadProject(project)

        let overlays = await previewEngine.getActiveOverlays(at: 5.0)
        XCTAssertEqual(overlays.count, 4)

        let types = overlays.map { $0.type }
        XCTAssertTrue(types.contains(.arrow))
        XCTAssertTrue(types.contains(.rect))
        XCTAssertTrue(types.contains(.line))
        XCTAssertTrue(types.contains(.text))
    }

    func testGetActiveOverlaysWithDifferentTransforms() async throws {
        var project = createMockProject()
        project.overlays = [
            createMockOverlay(
                type: .arrow,
                start: 0,
                end: 10,
                transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0)
            ),
            createMockOverlay(
                type: .rect,
                start: 0,
                end: 10,
                transform: Project.Overlay.Transform(x: 0.75, y: 0.25, scale: 1.5, rotation: 45)
            )
        ]

        try await previewEngine.loadProject(project)

        let overlays = await previewEngine.getActiveOverlays(at: 5.0)
        XCTAssertEqual(overlays.count, 2)

        XCTAssertEqual(overlays[0].transform.x, 0.5)
        XCTAssertEqual(overlays[0].transform.y, 0.5)
        XCTAssertEqual(overlays[0].transform.scale, 1.0)
        XCTAssertEqual(overlays[0].transform.rotation, 0)

        XCTAssertEqual(overlays[1].transform.x, 0.75)
        XCTAssertEqual(overlays[1].transform.y, 0.25)
        XCTAssertEqual(overlays[1].transform.scale, 1.5)
        XCTAssertEqual(overlays[1].transform.rotation, 45)
    }

    func testGetActiveOverlaysWithDifferentStyles() async throws {
        var project = createMockProject()
        project.overlays = [
            createMockOverlay(
                type: .arrow,
                start: 0,
                end: 10,
                style: Project.Overlay.Style(
                    stroke: "#FF0000",
                    strokeWidth: 8,
                    shadow: true,
                    font: nil,
                    size: nil,
                    color: nil,
                    bg: nil,
                    text: nil
                )
            ),
            createMockOverlay(
                type: .text,
                start: 0,
                end: 10,
                style: Project.Overlay.Style(
                    stroke: "#FFFFFF",
                    strokeWidth: 2,
                    shadow: false,
                    font: "Helvetica",
                    size: 24,
                    color: "#000000",
                    bg: "#FFFFFF80",
                    text: "Test Text"
                )
            )
        ]

        try await previewEngine.loadProject(project)

        let overlays = await previewEngine.getActiveOverlays(at: 5.0)
        XCTAssertEqual(overlays.count, 2)

        XCTAssertEqual(overlays[0].style.stroke, "#FF0000")
        XCTAssertEqual(overlays[0].style.strokeWidth, 8)
        XCTAssertTrue(overlays[0].style.shadow)

        XCTAssertEqual(overlays[1].style.text, "Test Text")
        XCTAssertEqual(overlays[1].style.font, "Helvetica")
        XCTAssertEqual(overlays[1].style.size, 24)
        XCTAssertFalse(overlays[1].style.shadow)
    }

    func testGetActiveOverlaysEmptyProject() async throws {
        var project = createMockProject()
        project.overlays = []

        try await previewEngine.loadProject(project)

        let overlays = await previewEngine.getActiveOverlays(at: 5.0)
        XCTAssertTrue(overlays.isEmpty)
    }

    // MARK: - Helper Methods for Overlay Tests

    private func createMockOverlay(
        type: Project.Overlay.OverlayType,
        start: TimeInterval,
        end: TimeInterval,
        transform: Project.Overlay.Transform? = nil,
        style: Project.Overlay.Style? = nil
    ) -> Project.Overlay {
        let defaultTransform = Project.Overlay.Transform(x: 0.5, y: 0.5, scale: 1.0, rotation: 0)

        let defaultStyle: Project.Overlay.Style
        switch type {
        case .arrow, .rect, .line:
            defaultStyle = Project.Overlay.Style(
                stroke: "#FFFFFF",
                strokeWidth: 6,
                shadow: false,
                font: nil,
                size: nil,
                color: nil,
                bg: nil,
                text: nil
            )
        case .text:
            defaultStyle = Project.Overlay.Style(
                stroke: "#FFFFFF",
                strokeWidth: 2,
                shadow: false,
                font: "Helvetica",
                size: 24,
                color: "#FFFFFF",
                bg: "#00000080",
                text: "Sample Text"
            )
        }

        return Project.Overlay(
            id: UUID(),
            type: type,
            start: start,
            end: end,
            transform: transform ?? defaultTransform,
            style: style ?? defaultStyle
        )
    }
}
