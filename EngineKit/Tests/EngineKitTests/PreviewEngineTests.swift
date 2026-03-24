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
            projectId: UUID(),
            name: "Test Project",
            sources: sources,
            timeline: timeline,
            canvas: canvas
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
        } catch PreviewEngine.PreviewError.noSegments {
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
        let isPlaying = await previewEngine.isPlaying()
        XCTAssertTrue(isPlaying)
    }

    func testPlayWithoutProject() async {
        do {
            try await previewEngine.play()
            XCTFail("Should have thrown PreviewError.noProjectLoaded")
        } catch PreviewEngine.PreviewError.noProjectLoaded {
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
        let isPaused = await previewEngine.isPaused()
        XCTAssertTrue(isPaused)
    }

    func testPauseWithoutProject() async {
        do {
            try await previewEngine.pause()
            XCTFail("Should have thrown PreviewError.noProjectLoaded")
        } catch PreviewEngine.PreviewError.noProjectLoaded {
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
        let isStopped_0 = await previewEngine.isStopped()
        XCTAssertTrue(isStopped_0)
    }

    func testStopWithoutProject() async {
        do {
            try await previewEngine.stop()
            XCTFail("Should have thrown PreviewError.noProjectLoaded")
        } catch PreviewEngine.PreviewError.noProjectLoaded {
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
        } catch PreviewEngine.PreviewError.noProjectLoaded {
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

        let getCurrentTime_0 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_0, 0)
    }

    func testSeekToEnd() async throws {
        try await previewEngine.loadProject(mockProject)
        try await previewEngine.seek(to: 10)

        let getCurrentTime_0 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_0, 10)
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
        } catch PreviewEngine.PreviewError.noProjectLoaded {
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
        } catch PreviewEngine.PreviewError.playbackFailed {
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
        } catch PreviewEngine.PreviewError.playbackFailed {
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
        let getCurrentTime_0 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_0, 0)
    }

    func testGetDuration() async throws {
        try await previewEngine.loadProject(mockProject)
        let getDuration_0 = await previewEngine.getDuration()
        XCTAssertEqual(getDuration_0, 10)
    }

    func testGetPlaybackState() async throws {
        try await previewEngine.loadProject(mockProject)
        let getPlaybackState_0 = await previewEngine.getPlaybackState()
        XCTAssertEqual(getPlaybackState_0, .stopped)
    }

    func testIsPlaying() async throws {
        try await previewEngine.loadProject(mockProject)
        let isPlaying_0 = await previewEngine.isPlaying()
        XCTAssertFalse(isPlaying_0)

        try await previewEngine.play()
        let isPlaying_1 = await previewEngine.isPlaying()
        XCTAssertTrue(isPlaying_1)
    }

    func testIsPaused() async throws {
        try await previewEngine.loadProject(mockProject)
        let isPaused_0 = await previewEngine.isPaused()
        XCTAssertFalse(isPaused_0)

        try await previewEngine.play()
        let isPaused_1 = await previewEngine.isPaused()
        XCTAssertFalse(isPaused_1)

        try await previewEngine.pause()
        let isPaused_2 = await previewEngine.isPaused()
        XCTAssertTrue(isPaused_2)
    }

    func testIsStopped() async throws {
        try await previewEngine.loadProject(mockProject)
        let isStopped_0 = await previewEngine.isStopped()
        XCTAssertTrue(isStopped_0)

        try await previewEngine.play()
        let isStopped_1 = await previewEngine.isStopped()
        XCTAssertFalse(isStopped_1)

        try await previewEngine.stop()
        let isStopped_2 = await previewEngine.isStopped()
        XCTAssertTrue(isStopped_2)
    }

    // MARK: - Error Description Tests

    func testErrorDescriptions() {
        XCTAssertEqual(
            PreviewEngine.PreviewError.noProjectLoaded.localizedDescription,
            "No project loaded for preview"
        )

        XCTAssertEqual(
            PreviewEngine.PreviewError.projectLoadFailed("test reason").localizedDescription,
            "Failed to load project: test reason"
        )

        XCTAssertEqual(
            PreviewEngine.PreviewError.playbackFailed("test reason").localizedDescription,
            "Playback failed: test reason"
        )

        XCTAssertEqual(
            PreviewEngine.PreviewError.seekFailed("test reason").localizedDescription,
            "Seek failed: test reason"
        )

        XCTAssertEqual(
            PreviewEngine.PreviewError.invalidTime(5.0).localizedDescription,
            "Invalid time: 5.0s"
        )

        XCTAssertEqual(
            PreviewEngine.PreviewError.noSegments.localizedDescription,
            "Project has no segments to preview"
        )

        XCTAssertEqual(
            PreviewEngine.PreviewError.mediaFileNotFound("/tmp/test.mov").localizedDescription,
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

        // Measure performance of getSession calls
        let start = Date()
        for _ in 0..<1000 {
            _ = await previewEngine.getSession()
        }
        let duration = Date().timeIntervalSince(start)

        // Should complete 1000 calls in reasonable time (< 0.1 seconds)
        XCTAssertLessThan(duration, 0.1, "getSession calls should be very fast")
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
            style: style ?? defaultStyle,
            animation: nil
        )
    }

    // MARK: - Proxy Generation Tests

    func testGenerateProxiesWithoutProject() async {
        do {
            _ = try await previewEngine.generateProxies(projectDirectory: "/tmp")
            XCTFail("Should have thrown PreviewError.noProjectLoaded")
        } catch PreviewEngine.PreviewError.noProjectLoaded {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testHasProxiesWithoutProject() async {
        let hasProxies = await previewEngine.hasProxies()
        XCTAssertFalse(hasProxies)
    }

    func testHasProxiesWithoutProjectDirectory() async throws {
        try await previewEngine.loadProject(mockProject)
        let hasProxies = await previewEngine.hasProxies()
        XCTAssertFalse(hasProxies)
    }

    func testHasProxiesWithProjectDirectory() async throws {
        let tempDir = NSTemporaryDirectory()
        let projectDir = (tempDir as NSString).appendingPathComponent("TestProject_\(UUID().uuidString)")

        // Create proxies directory and screen proxy file
        let proxiesDir = (projectDir as NSString).appendingPathComponent("proxies")
        try? FileManager.default.createDirectory(atPath: proxiesDir, withIntermediateDirectories: true, attributes: nil)
        let screenProxyPath = (proxiesDir as NSString).appendingPathComponent("screen_proxy.mov")
        FileManager.default.createFile(atPath: screenProxyPath, contents: Data())

        try await previewEngine.loadProject(mockProject, projectDirectory: projectDir)
        let hasProxies = await previewEngine.hasProxies()
        XCTAssertTrue(hasProxies)

        // Clean up
        try? FileManager.default.removeItem(atPath: projectDir)
    }

    func testGetProxyPathWithoutProjectDirectory() async throws {
        try await previewEngine.loadProject(mockProject)
        let proxyPath = await previewEngine.getProxyPath(for: "screen")
        XCTAssertNil(proxyPath)
    }

    func testGetProxyPathWithProjectDirectory() async throws {
        let tempDir = NSTemporaryDirectory()
        let projectDir = (tempDir as NSString).appendingPathComponent("TestProject_\(UUID().uuidString)")

        // Create proxies directory and screen proxy file
        let proxiesDir = (projectDir as NSString).appendingPathComponent("proxies")
        try? FileManager.default.createDirectory(atPath: proxiesDir, withIntermediateDirectories: true, attributes: nil)
        let screenProxyPath = (proxiesDir as NSString).appendingPathComponent("screen_proxy.mov")
        FileManager.default.createFile(atPath: screenProxyPath, contents: Data())

        try await previewEngine.loadProject(mockProject, projectDirectory: projectDir)
        let proxyPath = await previewEngine.getProxyPath(for: "screen")
        XCTAssertNotNil(proxyPath)
        XCTAssertEqual(proxyPath, screenProxyPath)

        // Clean up
        try? FileManager.default.removeItem(atPath: projectDir)
    }

    func testGetProxyPathForCamera() async throws {
        let tempDir = NSTemporaryDirectory()
        let projectDir = (tempDir as NSString).appendingPathComponent("TestProject_\(UUID().uuidString)")

        // Create proxies directory and camera proxy file
        let proxiesDir = (projectDir as NSString).appendingPathComponent("proxies")
        try? FileManager.default.createDirectory(atPath: proxiesDir, withIntermediateDirectories: true, attributes: nil)
        let cameraProxyPath = (proxiesDir as NSString).appendingPathComponent("camera_proxy.mov")
        FileManager.default.createFile(atPath: cameraProxyPath, contents: Data())

        try await previewEngine.loadProject(mockProject, projectDirectory: projectDir)
        let proxyPath = await previewEngine.getProxyPath(for: "camera")
        XCTAssertNotNil(proxyPath)
        XCTAssertEqual(proxyPath, cameraProxyPath)

        // Clean up
        try? FileManager.default.removeItem(atPath: projectDir)
    }

    func testDeleteProxiesWithoutProjectDirectory() async throws {
        try await previewEngine.loadProject(mockProject)

        do {
            try await previewEngine.deleteProxies()
            XCTFail("Should have thrown PreviewError.noProjectLoaded")
        } catch PreviewEngine.PreviewError.noProjectLoaded {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testDeleteProxiesSuccessfully() async throws {
        let tempDir = NSTemporaryDirectory()
        let projectDir = (tempDir as NSString).appendingPathComponent("TestProject_\(UUID().uuidString)")

        // Create proxies directory and screen proxy file
        let proxiesDir = (projectDir as NSString).appendingPathComponent("proxies")
        try? FileManager.default.createDirectory(atPath: proxiesDir, withIntermediateDirectories: true, attributes: nil)
        let screenProxyPath = (proxiesDir as NSString).appendingPathComponent("screen_proxy.mov")
        FileManager.default.createFile(atPath: screenProxyPath, contents: Data())

        try await previewEngine.loadProject(mockProject, projectDirectory: projectDir)

        // Verify proxies exist
        let hasProxies_0 = await previewEngine.hasProxies()
        XCTAssertTrue(hasProxies_0)

        // Delete proxies
        try await previewEngine.deleteProxies()

        // Verify proxies are deleted
        let hasProxies_1 = await previewEngine.hasProxies()
        XCTAssertFalse(hasProxies_1)

        // Clean up
        try? FileManager.default.removeItem(atPath: projectDir)
    }

    func testLoadProjectWithProjectDirectory() async throws {
        let tempDir = NSTemporaryDirectory()
        let projectDir = (tempDir as NSString).appendingPathComponent("TestProject_\(UUID().uuidString)")

        try await previewEngine.loadProject(mockProject, projectDirectory: projectDir)

        // Verify project directory is stored
        let session = await previewEngine.getSession()
        // We can't directly access projectDirectory, but we can verify it works via hasProxies
        let hasProxies_0 = await previewEngine.hasProxies()
        XCTAssertFalse(hasProxies_0)

        // Clean up
        try? FileManager.default.removeItem(atPath: projectDir)
    }

    func testUnloadProjectClearsProjectDirectory() async throws {
        let tempDir = NSTemporaryDirectory()
        let projectDir = (tempDir as NSString).appendingPathComponent("TestProject_\(UUID().uuidString)")

        try await previewEngine.loadProject(mockProject, projectDirectory: projectDir)
        await previewEngine.unloadProject()

        // After unloading, hasProxies should return false
        let hasProxies_0 = await previewEngine.hasProxies()
        XCTAssertFalse(hasProxies_0)

        // Clean up
        try? FileManager.default.removeItem(atPath: projectDir)
    }

    // MARK: - Seek Accuracy Tests (Épica L, Task 4)

    func testSeekAccuracyAtMultiplePositions() async throws {
        try await previewEngine.loadProject(mockProject)

        // Test seeks at various positions throughout the timeline
        let testPositions: [TimeInterval] = [0, 1.0, 2.5, 5.0, 7.5, 9.0, 10.0]
        let tolerance: TimeInterval = 0.01 // 10ms tolerance for seek accuracy

        for targetTime in testPositions {
            try await previewEngine.seek(to: targetTime)
            let actualTime = await previewEngine.getCurrentTime()

            // Verify seek accuracy within tolerance
            XCTAssertEqual(
                actualTime,
                targetTime,
                accuracy: tolerance,
                "Seek to \(targetTime)s resulted in \(actualTime)s, which is outside tolerance of \(tolerance)s"
            )
        }
    }

    func testSeekAccuracyAtBoundaries() async throws {
        try await previewEngine.loadProject(mockProject)

        // Test seek to exact start
        try await previewEngine.seek(to: 0)
        let getCurrentTime_0 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_0, 0, accuracy: 0.001)

        // Test seek to exact end
        try await previewEngine.seek(to: 10.0)
        let getCurrentTime_1 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_1, 10.0, accuracy: 0.001)

        // Test seek to middle
        try await previewEngine.seek(to: 5.0)
        let getCurrentTime_2 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_2, 5.0, accuracy: 0.001)
    }

    func testSeekAccuracyWithFractionalSeconds() async throws {
        try await previewEngine.loadProject(mockProject)

        // Test seeks with fractional seconds
        let fractionalTimes: [TimeInterval] = [0.123, 1.456, 2.789, 5.234, 8.901]
        let tolerance: TimeInterval = 0.001 // 1ms tolerance for fractional seeks

        for targetTime in fractionalTimes {
            try await previewEngine.seek(to: targetTime)
            let actualTime = await previewEngine.getCurrentTime()

            XCTAssertEqual(
                actualTime,
                targetTime,
                accuracy: tolerance,
                "Seek to \(targetTime)s resulted in \(actualTime)s, which is outside tolerance of \(tolerance)s"
            )
        }
    }

    func testSeekAccuracyAfterPlayback() async throws {
        try await previewEngine.loadProject(mockProject)

        // Start playback
        try await previewEngine.play()
        try await Task.sleep(nanoseconds: 100_000_000) // Sleep 100ms
        try await previewEngine.pause()

        // Seek to a specific time and verify accuracy
        try await previewEngine.seek(to: 3.5)
        let getCurrentTime_0 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_0, 3.5, accuracy: 0.01)

        // Resume playback and seek again
        try await previewEngine.play()
        try await Task.sleep(nanoseconds: 100_000_000) // Sleep 100ms
        try await previewEngine.pause()
        try await previewEngine.seek(to: 7.8)
        let getCurrentTime_1 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_1, 7.8, accuracy: 0.01)
    }

    func testSeekAccuracyMultipleSequentials() async throws {
        try await previewEngine.loadProject(mockProject)

        // Perform multiple sequential seeks and verify each one
        let seekSequence: [TimeInterval] = [1.0, 3.0, 2.0, 5.0, 4.0, 7.0, 6.0, 9.0]
        let tolerance: TimeInterval = 0.01

        for targetTime in seekSequence {
            try await previewEngine.seek(to: targetTime)
            let actualTime = await previewEngine.getCurrentTime()

            XCTAssertEqual(
                actualTime,
                targetTime,
                accuracy: tolerance,
                "Sequential seek to \(targetTime)s resulted in \(actualTime)s"
            )
        }
    }

    func testSeekAccuracyAtSegmentBoundaries() async throws {
        // Create project with clear segment boundaries
        let segments = [
            Project.Timeline.Segment(id: "seg1", sourceIn: 0, sourceOut: 3, timelineIn: 0, speed: 1.0),
            Project.Timeline.Segment(id: "seg2", sourceIn: 3, sourceOut: 6, timelineIn: 3, speed: 1.0),
            Project.Timeline.Segment(id: "seg3", sourceIn: 6, sourceOut: 10, timelineIn: 6, speed: 1.0)
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 10, segments: segments)

        try await previewEngine.loadProject(project)

        // Test seeks at segment boundaries
        let boundaryTimes: [TimeInterval] = [0, 3.0, 6.0, 10.0]
        let tolerance: TimeInterval = 0.001

        for targetTime in boundaryTimes {
            try await previewEngine.seek(to: targetTime)
            let actualTime = await previewEngine.getCurrentTime()

            XCTAssertEqual(
                actualTime,
                targetTime,
                accuracy: tolerance,
                "Seek to segment boundary at \(targetTime)s resulted in \(actualTime)s"
            )
        }
    }

    // MARK: - Playback with Edits Applied Tests (Épica L, Task 4)

    func testPlaybackWithTrimInApplied() async throws {
        // Create project with trimmed segment (first 2 seconds removed)
        let segments = [
            Project.Timeline.Segment(
                id: "seg1",
                sourceIn: 2.0,  // Trimmed in: starts at 2s in source
                sourceOut: 8.0,
                timelineIn: 0,
                speed: 1.0
            )
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 6, segments: segments)

        try await previewEngine.loadProject(project)

        // Verify timeline duration reflects the trim (8 - 2 = 6 seconds)
        let getDuration_0 = await previewEngine.getDuration()
        XCTAssertEqual(getDuration_0, 6.0)

        // Seek to timeline position 0 should correspond to source position 2.0
        try await previewEngine.seek(to: 0)
        let getCurrentTime_1 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_1, 0)

        // Seek to timeline position 3 should correspond to source position 5.0 (2 + 3)
        try await previewEngine.seek(to: 3.0)
        let getCurrentTime_2 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_2, 3.0)
    }

    func testPlaybackWithTrimOutApplied() async throws {
        // Create project with trimmed segment (last 2 seconds removed)
        let segments = [
            Project.Timeline.Segment(
                id: "seg1",
                sourceIn: 0,
                sourceOut: 8.0,  // Trimmed out: ends at 8s in source (instead of 10s)
                timelineIn: 0,
                speed: 1.0
            )
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 8, segments: segments)

        try await previewEngine.loadProject(project)

        // Verify timeline duration reflects the trim
        let getDuration_0 = await previewEngine.getDuration()
        XCTAssertEqual(getDuration_0, 8.0)

        // Verify we can seek to the end of the trimmed segment
        try await previewEngine.seek(to: 8.0)
        let getCurrentTime_1 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_1, 8.0)
    }

    func testPlaybackWithTrimsInAndOutApplied() async throws {
        // Create project with both trims (first 1s and last 2s removed)
        let segments = [
            Project.Timeline.Segment(
                id: "seg1",
                sourceIn: 1.0,  // Trim in
                sourceOut: 8.0,  // Trim out
                timelineIn: 0,
                speed: 1.0
            )
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 7, segments: segments)

        try await previewEngine.loadProject(project)

        // Verify timeline duration reflects both trims (8 - 1 = 7 seconds)
        let getDuration_0 = await previewEngine.getDuration()
        XCTAssertEqual(getDuration_0, 7.0)

        // Test seek accuracy with trimmed segment
        try await previewEngine.seek(to: 3.5)
        let getCurrentTime_1 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_1, 3.5, accuracy: 0.01)
    }

    func testPlaybackWithMultipleSegmentsAfterCut() async throws {
        // Create project with cut (two segments)
        let segments = [
            Project.Timeline.Segment(
                id: "seg1",
                sourceIn: 0,
                sourceOut: 4.0,
                timelineIn: 0,
                speed: 1.0
            ),
            Project.Timeline.Segment(
                id: "seg2",
                sourceIn: 6.0,  // Gap: 4-6 seconds removed
                sourceOut: 10.0,
                timelineIn: 4.0,
                speed: 1.0
            )
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 8, segments: segments)

        try await previewEngine.loadProject(project)

        // Verify timeline duration reflects the cut (4 + 4 = 8 seconds, gap removed)
        let getDuration_0 = await previewEngine.getDuration()
        XCTAssertEqual(getDuration_0, 8.0)

        // Verify we can seek within first segment
        try await previewEngine.seek(to: 2.0)
        let getCurrentTime_1 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_1, 2.0)

        // Verify we can seek within second segment
        try await previewEngine.seek(to: 6.0)
        let getCurrentTime_2 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_2, 6.0)

        // Verify we can seek to the boundary between segments
        try await previewEngine.seek(to: 4.0)
        let getCurrentTime_3 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_3, 4.0)
    }

    func testPlaybackWithSpeedChangeSlowMotion() async throws {
        // Create project with slow motion segment (0.5x speed)
        let segments = [
            Project.Timeline.Segment(
                id: "seg1",
                sourceIn: 0,
                sourceOut: 5.0,
                timelineIn: 0,
                speed: 0.5  // Slow motion: 5s source = 10s timeline
            )
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 10, segments: segments)

        try await previewEngine.loadProject(project)

        // Verify timeline duration reflects speed change (5 / 0.5 = 10 seconds)
        let getDuration_0 = await previewEngine.getDuration()
        XCTAssertEqual(getDuration_0, 10.0)

        // Verify seek accuracy with speed change
        try await previewEngine.seek(to: 5.0)
        let getCurrentTime_1 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_1, 5.0, accuracy: 0.01)
    }

    func testPlaybackWithSpeedChangeFastForward() async throws {
        // Create project with fast forward segment (2x speed)
        let segments = [
            Project.Timeline.Segment(
                id: "seg1",
                sourceIn: 0,
                sourceOut: 10.0,
                timelineIn: 0,
                speed: 2.0  // Fast forward: 10s source = 5s timeline
            )
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 5, segments: segments)

        try await previewEngine.loadProject(project)

        // Verify timeline duration reflects speed change (10 / 2 = 5 seconds)
        let getDuration_0 = await previewEngine.getDuration()
        XCTAssertEqual(getDuration_0, 5.0)

        // Verify seek accuracy with speed change
        try await previewEngine.seek(to: 2.5)
        let getCurrentTime_1 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_1, 2.5, accuracy: 0.01)
    }

    func testPlaybackWithMixedEdits() async throws {
        // Create project with trims, cuts, and speed changes
        let segments = [
            Project.Timeline.Segment(
                id: "seg1",
                sourceIn: 1.0,  // Trim in
                sourceOut: 4.0,  // Trim out (3s duration)
                timelineIn: 0,
                speed: 1.0
            ),
            Project.Timeline.Segment(
                id: "seg2",
                sourceIn: 4.0,
                sourceOut: 7.0,  // 3s source
                timelineIn: 3.0,
                speed: 2.0  // Fast forward: 3s source = 1.5s timeline
            ),
            Project.Timeline.Segment(
                id: "seg3",
                sourceIn: 8.0,  // Gap: 7-8 seconds removed
                sourceOut: 10.0,  // 2s duration
                timelineIn: 4.5,
                speed: 0.5  // Slow motion: 2s source = 4s timeline
            )
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 8.5, segments: segments)

        try await previewEngine.loadProject(project)

        // Verify timeline duration: 3 + 1.5 + 4 = 8.5 seconds
        let getDuration_0 = await previewEngine.getDuration()
        XCTAssertEqual(getDuration_0, 8.5, accuracy: 0.01)

        // Verify seek accuracy in first segment
        try await previewEngine.seek(to: 1.5)
        let getCurrentTime_1 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_1, 1.5, accuracy: 0.01)

        // Verify seek accuracy in second segment (fast forward)
        try await previewEngine.seek(to: 3.75)
        let getCurrentTime_2 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_2, 3.75, accuracy: 0.01)

        // Verify seek accuracy in third segment (slow motion)
        try await previewEngine.seek(to: 6.5)
        let getCurrentTime_3 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_3, 6.5, accuracy: 0.01)

        // Verify seek to end
        try await previewEngine.seek(to: 8.5)
        let getCurrentTime_4 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_4, 8.5, accuracy: 0.01)
    }

    func testPlaybackWithComplexSegmentStructure() async throws {
        // Create project with 5 segments and various edits
        let segments = [
            Project.Timeline.Segment(id: "s1", sourceIn: 0, sourceOut: 2, timelineIn: 0, speed: 1.0),
            Project.Timeline.Segment(id: "s2", sourceIn: 2, sourceOut: 4, timelineIn: 2, speed: 0.5),  // Slow
            Project.Timeline.Segment(id: "s3", sourceIn: 4, sourceOut: 6, timelineIn: 6, speed: 2.0),  // Fast
            Project.Timeline.Segment(id: "s4", sourceIn: 6, sourceOut: 8, timelineIn: 7, speed: 1.0),
            Project.Timeline.Segment(id: "s5", sourceIn: 8, sourceOut: 10, timelineIn: 9, speed: 1.0)
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 11, segments: segments)

        try await previewEngine.loadProject(project)

        // Verify duration: 2 + 4 + 1 + 2 + 2 = 11 seconds
        let getDuration_0 = await previewEngine.getDuration()
        XCTAssertEqual(getDuration_0, 11, accuracy: 0.01)

        // Test seeks across all segments
        let testPositions: [TimeInterval] = [0, 1, 3, 6.5, 8, 10, 11]
        for pos in testPositions {
            try await previewEngine.seek(to: pos)
            let getCurrentTime_1 = await previewEngine.getCurrentTime()
            XCTAssertEqual(getCurrentTime_1, pos, accuracy: 0.01)
        }
    }

    func testPlaybackStateWithEditsApplied() async throws {
        // Create project with cuts
        let segments = [
            Project.Timeline.Segment(id: "s1", sourceIn: 0, sourceOut: 3, timelineIn: 0, speed: 1.0),
            Project.Timeline.Segment(id: "s2", sourceIn: 5, sourceOut: 8, timelineIn: 3, speed: 1.5)
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 5, segments: segments)

        try await previewEngine.loadProject(project)

        // Verify initial state
        let getPlaybackState_0 = await previewEngine.getPlaybackState()
        XCTAssertEqual(getPlaybackState_0, .stopped)
        let getCurrentTime_1 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_1, 0)

        // Play and verify state
        try await previewEngine.play()
        let getPlaybackState_2 = await previewEngine.getPlaybackState()
        XCTAssertEqual(getPlaybackState_2, .playing)

        // Pause and verify state
        try await previewEngine.pause()
        let getPlaybackState_3 = await previewEngine.getPlaybackState()
        XCTAssertEqual(getPlaybackState_3, .paused)

        // Seek and verify state remains paused
        try await previewEngine.seek(to: 2.5)
        let getPlaybackState_4 = await previewEngine.getPlaybackState()
        XCTAssertEqual(getPlaybackState_4, .paused)
        let getCurrentTime_5 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_5, 2.5, accuracy: 0.01)

        // Stop and verify state
        try await previewEngine.stop()
        let getPlaybackState_6 = await previewEngine.getPlaybackState()
        XCTAssertEqual(getPlaybackState_6, .stopped)
        let getCurrentTime_7 = await previewEngine.getCurrentTime()
        XCTAssertEqual(getCurrentTime_7, 0)
    }

    func testPlaybackWithEditsAndOverlays() async throws {
        // Create project with edits and overlays
        let segments = [
            Project.Timeline.Segment(id: "s1", sourceIn: 0, sourceOut: 5, timelineIn: 0, speed: 1.0),
            Project.Timeline.Segment(id: "s2", sourceIn: 7, sourceOut: 10, timelineIn: 5, speed: 2.0)
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 6.5, segments: segments)
        project.overlays = [
            createMockOverlay(type: .arrow, start: 0, end: 3),
            createMockOverlay(type: .rect, start: 4, end: 6)
        ]

        try await previewEngine.loadProject(project)

        // Verify overlays at different timeline positions
        let overlaysAt1 = await previewEngine.getActiveOverlays(at: 1.0)
        XCTAssertEqual(overlaysAt1.count, 1) // Only arrow
        XCTAssertEqual(overlaysAt1.first?.type, .arrow)

        let overlaysAt5 = await previewEngine.getActiveOverlays(at: 5.0)
        XCTAssertEqual(overlaysAt5.count, 1) // Only rect
        XCTAssertEqual(overlaysAt5.first?.type, .rect)
    }

    func testSeekAccuracyWithSpeedChanges() async throws {
        // Test seek accuracy across segments with different speeds
        let segments = [
            Project.Timeline.Segment(id: "s1", sourceIn: 0, sourceOut: 5, timelineIn: 0, speed: 0.5),  // 10s timeline
            Project.Timeline.Segment(id: "s2", sourceIn: 5, sourceOut: 10, timelineIn: 10, speed: 2.0)  // 2.5s timeline
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 12.5, segments: segments)

        try await previewEngine.loadProject(project)

        // Test seeks at various positions
        let testPositions: [TimeInterval] = [0, 2.5, 5.0, 7.5, 10.0, 11.25, 12.5]
        let tolerance: TimeInterval = 0.01

        for targetTime in testPositions {
            try await previewEngine.seek(to: targetTime)
            let actualTime = await previewEngine.getCurrentTime()

            XCTAssertEqual(
                actualTime,
                targetTime,
                accuracy: tolerance,
                "Seek to \(targetTime)s with speed changes resulted in \(actualTime)s"
            )
        }
    }

    // MARK: - Integration Tests for Edits (Épica L, Task 4)

    func testIntegrationTrimAndSeek() async throws {
        // Test that trimmed segments can be sought accurately
        let segments = [
            Project.Timeline.Segment(
                id: "seg1",
                sourceIn: 2.5,  // Trim in at 2.5s
                sourceOut: 7.5,  // Trim out at 7.5s
                timelineIn: 0,
                speed: 1.0
            )
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 5, segments: segments)

        try await previewEngine.loadProject(project)

        // Verify we can seek anywhere within the trimmed segment
        for targetTime in stride(from: 0, through: 5, by: 0.5) {
            try await previewEngine.seek(to: targetTime)
            let getCurrentTime_0 = await previewEngine.getCurrentTime()
            XCTAssertEqual(getCurrentTime_0, targetTime, accuracy: 0.01)
        }
    }

    func testIntegrationCutAndSeek() async throws {
        // Test that cut segments can be sought accurately
        let segments = [
            Project.Timeline.Segment(id: "s1", sourceIn: 0, sourceOut: 3, timelineIn: 0, speed: 1.0),
            Project.Timeline.Segment(id: "s2", sourceIn: 5, sourceOut: 8, timelineIn: 3, speed: 1.0),  // Gap at 3-5s
            Project.Timeline.Segment(id: "s3", sourceIn: 8, sourceOut: 10, timelineIn: 6, speed: 1.0)
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 8, segments: segments)

        try await previewEngine.loadProject(project)

        // Verify we can seek across all segments
        for targetTime in [0, 1.5, 3, 4.5, 6, 7, 8] {
            try await previewEngine.seek(to: targetTime)
            let getCurrentTime_0 = await previewEngine.getCurrentTime()
            XCTAssertEqual(getCurrentTime_0, targetTime, accuracy: 0.01)
        }
    }

    func testIntegrationSpeedChangeAndSeek() async throws {
        // Test that speed changes don't affect seek accuracy
        let segments = [
            Project.Timeline.Segment(id: "s1", sourceIn: 0, sourceOut: 10, timelineIn: 0, speed: 0.5),  // 20s timeline
            Project.Timeline.Segment(id: "s2", sourceIn: 10, sourceOut: 15, timelineIn: 20, speed: 2.0),  // 2.5s timeline
            Project.Timeline.Segment(id: "s3", sourceIn: 15, sourceOut: 20, timelineIn: 22.5, speed: 1.0)  // 5s timeline
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 27.5, segments: segments)

        try await previewEngine.loadProject(project)

        // Verify seeks work across all speed changes
        let testPositions: [TimeInterval] = [0, 5, 10, 15, 20, 21.25, 22.5, 25, 27.5]
        for targetTime in testPositions {
            try await previewEngine.seek(to: targetTime)
            let getCurrentTime_0 = await previewEngine.getCurrentTime()
            XCTAssertEqual(getCurrentTime_0, targetTime, accuracy: 0.01)
        }
    }

    func testIntegrationAllEditsCombined() async throws {
        // Test all edit types combined: trims, cuts, speed changes
        let segments = [
            Project.Timeline.Segment(id: "s1", sourceIn: 1, sourceOut: 4, timelineIn: 0, speed: 1.0),  // Trimmed
            Project.Timeline.Segment(id: "s2", sourceIn: 4, sourceOut: 6, timelineIn: 3, speed: 0.5),  // Slow
            Project.Timeline.Segment(id: "s3", sourceIn: 8, sourceOut: 12, timelineIn: 7, speed: 2.0),  // Cut + fast
            Project.Timeline.Segment(id: "s4", sourceIn: 12, sourceOut: 15, timelineIn: 9, speed: 1.0)
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 12, segments: segments)

        try await previewEngine.loadProject(project)

        // Verify duration calculation: 3 + 4 + 2 + 3 = 12 seconds
        let getDuration_0 = await previewEngine.getDuration()
        XCTAssertEqual(getDuration_0, 12, accuracy: 0.01)

        // Verify seek accuracy across all edits
        let testPositions: [TimeInterval] = [0, 1.5, 3, 5, 7, 8, 9, 10.5, 12]
        for targetTime in testPositions {
            try await previewEngine.seek(to: targetTime)
            let actualTime = await previewEngine.getCurrentTime()

            XCTAssertEqual(
                actualTime,
                targetTime,
                accuracy: 0.01,
                "Seek to \(targetTime)s with combined edits resulted in \(actualTime)s"
            )
        }
    }

    // MARK: - Performance Tests for Edits (Épica L, Task 4)

    func testPerformanceSeekWithEdits() async throws {
        // Create project with complex edits
        let segments = [
            Project.Timeline.Segment(id: "s1", sourceIn: 0, sourceOut: 3, timelineIn: 0, speed: 1.0),
            Project.Timeline.Segment(id: "s2", sourceIn: 3, sourceOut: 5, timelineIn: 3, speed: 0.5),
            Project.Timeline.Segment(id: "s3", sourceIn: 7, sourceOut: 10, timelineIn: 7, speed: 2.0),
            Project.Timeline.Segment(id: "s4", sourceIn: 10, sourceOut: 12, timelineIn: 8.5, speed: 1.0)
        ]

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: 10.5, segments: segments)

        try await previewEngine.loadProject(project)

        // Measure seek performance with edits applied
        measure {
            Task {
                for i in 0..<100 {
                    let time = Double(i) / 10.0  // 0, 0.1, 0.2, ..., 9.9
                    try? await previewEngine.seek(to: time)
                }
            }
        }
    }

    func testPerformanceLoadProjectWithComplexEdits() {
        // Create project with many segments and edits
        var segments: [Project.Timeline.Segment] = []
        var currentTime: TimeInterval = 0
        var sourceTime: TimeInterval = 0

        for i in 0..<20 {
            let duration = Double.random(in: 1...3)
            let speed = Double.random(in: 0.5...2.0)

            segments.append(Project.Timeline.Segment(
                id: "s\(i)",
                sourceIn: sourceTime,
                sourceOut: sourceTime + duration,
                timelineIn: currentTime,
                speed: speed
            ))

            let timelineDuration = duration / speed
            currentTime += timelineDuration
            sourceTime += duration + Double.random(in: 0...1)  // Random gaps
        }

        var project = createMockProject()
        project.timeline = Project.Timeline(duration: currentTime, segments: segments)

        // Measure project loading performance
        measure {
            Task {
                let engine = PreviewEngine()
                try? await engine.loadProject(project)
            }
        }
    }

    // MARK: - Zoom Rendering Tests
    // NOTE: These tests are disabled because PreviewEngine does not yet implement
    // zoom plan methods (loadZoomPlan, getZoomPlan, clearZoomPlan, isZoomEnabled,
    // setZoomEnabled, getZoomLevel, getZoomFocusPoint). Re-enable when implemented.

    /*
    func testLoadZoomPlan() async throws {
        let zoomPlan = createMockZoomPlan()
        await previewEngine.loadZoomPlan(zoomPlan)

        let loadedPlan = await previewEngine.getZoomPlan()
        XCTAssertNotNil(loadedPlan)
        XCTAssertEqual(loadedPlan?.keyframes.count, zoomPlan.keyframes.count)
    }

    func testClearZoomPlan() async throws {
        let zoomPlan = createMockZoomPlan()
        await previewEngine.loadZoomPlan(zoomPlan)

        await previewEngine.clearZoomPlan()

        let loadedPlan = await previewEngine.getZoomPlan()
        XCTAssertNil(loadedPlan)
    }

    func testZoomEnabledByDefault() async {
        let engine = PreviewEngine()
        let isEnabled = await engine.isZoomEnabled()
        XCTAssertTrue(isEnabled)
    }

    func testSetZoomEnabled() async {
        await previewEngine.setZoomEnabled(false)
        var isEnabled = await previewEngine.isZoomEnabled()
        XCTAssertFalse(isEnabled)

        await previewEngine.setZoomEnabled(true)
        isEnabled = await previewEngine.isZoomEnabled()
        XCTAssertTrue(isEnabled)
    }

    func testGetZoomLevelAtSpecificTime() async throws {
        let zoomPlan = createMockZoomPlan()
        await previewEngine.loadZoomPlan(zoomPlan)

        // Test at zoom-in keyframe time (5.0s)
        let zoomLevelAtZoomIn = await previewEngine.getZoomLevel(at: 5.0)
        XCTAssertEqual(zoomLevelAtZoomIn, 2.5, accuracy: 0.01)

        // Test at hold time (7.0s)
        let zoomLevelAtHold = await previewEngine.getZoomLevel(at: 7.0)
        XCTAssertEqual(zoomLevelAtHold, 2.5, accuracy: 0.01)

        // Test after zoom-out (12.0s)
        let zoomLevelAfterZoomOut = await previewEngine.getZoomLevel(at: 12.0)
        XCTAssertEqual(zoomLevelAfterZoomOut, 1.0, accuracy: 0.01)
    }

    func testGetZoomLevelWhenZoomDisabled() async throws {
        let zoomPlan = createMockZoomPlan()
        await previewEngine.loadZoomPlan(zoomPlan)
        await previewEngine.setZoomEnabled(false)

        let zoomLevel = await previewEngine.getZoomLevel(at: 5.0)
        XCTAssertEqual(zoomLevel, 1.0, accuracy: 0.01)
    }

    func testGetZoomLevelWhenNoZoomPlan() async {
        let zoomLevel = await previewEngine.getZoomLevel(at: 5.0)
        XCTAssertEqual(zoomLevel, 1.0, accuracy: 0.01)
    }

    func testGetZoomFocusPointAtSpecificTime() async throws {
        let zoomPlan = createMockZoomPlan()
        await previewEngine.loadZoomPlan(zoomPlan)

        // Test at zoom-in time
        let focusPoint = await previewEngine.getZoomFocusPoint(at: 5.0)
        XCTAssertEqual(focusPoint.x, 0.6, accuracy: 0.01)
        XCTAssertEqual(focusPoint.y, 0.4, accuracy: 0.01)
    }

    func testGetZoomFocusPointWhenNoZoomPlan() async {
        let focusPoint = await previewEngine.getZoomFocusPoint(at: 5.0)
        XCTAssertEqual(focusPoint.x, 0.5, accuracy: 0.01)
        XCTAssertEqual(focusPoint.y, 0.5, accuracy: 0.01)
    }

    func testConfigurationWithZoomDisabled() async {
        let config = PreviewEngine.Configuration(zoomEnabled: false)
        let engine = PreviewEngine(configuration: config)

        let isEnabled = await engine.isZoomEnabled()
        XCTAssertFalse(isEnabled)
    }

    func testUnloadProjectClearsZoomPlan() async throws {
        try await previewEngine.loadProject(mockProject)

        let zoomPlan = createMockZoomPlan()
        await previewEngine.loadZoomPlan(zoomPlan)

        var loadedPlan = await previewEngine.getZoomPlan()
        XCTAssertNotNil(loadedPlan)

        await previewEngine.unloadProject()

        loadedPlan = await previewEngine.getZoomPlan()
        XCTAssertNil(loadedPlan)
    }

    func testZoomPlanInterpolation() async throws {
        let zoomPlan = createMockZoomPlan()
        await previewEngine.loadZoomPlan(zoomPlan)

        // Test interpolation between keyframes (zooming in)
        let zoomLevel1 = await previewEngine.getZoomLevel(at: 4.5) // Midway through zoom-in
        XCTAssertTrue(zoomLevel1 > 1.0 && zoomLevel1 < 2.5)

        // Test interpolation during zoom-out
        let zoomLevel2 = await previewEngine.getZoomLevel(at: 9.0) // Midway through zoom-out
        XCTAssertTrue(zoomLevel2 > 1.0 && zoomLevel2 < 2.5)
    }

    func testMultipleZoomEvents() async throws {
        var keyframes: [ZoomPlanGenerator.ZoomKeyframe] = []

        // First zoom event (0-10s)
        keyframes.append(contentsOf: [
            ZoomPlanGenerator.ZoomKeyframe(timestamp: 0, zoomLevel: 1.0, focusX: 0.5, focusY: 0.5, easing: .easeInOut),
            ZoomPlanGenerator.ZoomKeyframe(timestamp: 2, zoomLevel: 2.0, focusX: 0.3, focusY: 0.3, easing: .easeInOut),
            ZoomPlanGenerator.ZoomKeyframe(timestamp: 5, zoomLevel: 2.0, focusX: 0.3, focusY: 0.3, easing: .easeInOut),
            ZoomPlanGenerator.ZoomKeyframe(timestamp: 7, zoomLevel: 1.0, focusX: 0.5, focusY: 0.5, easing: .easeInOut)
        ])

        // Second zoom event (15-25s)
        keyframes.append(contentsOf: [
            ZoomPlanGenerator.ZoomKeyframe(timestamp: 15, zoomLevel: 1.0, focusX: 0.5, focusY: 0.5, easing: .easeInOut),
            ZoomPlanGenerator.ZoomKeyframe(timestamp: 17, zoomLevel: 2.5, focusX: 0.7, focusY: 0.6, easing: .easeInOut),
            ZoomPlanGenerator.ZoomKeyframe(timestamp: 20, zoomLevel: 2.5, focusX: 0.7, focusY: 0.6, easing: .easeInOut),
            ZoomPlanGenerator.ZoomKeyframe(timestamp: 22, zoomLevel: 1.0, focusX: 0.5, focusY: 0.5, easing: .easeInOut)
        ])

        let zoomPlan = ZoomPlanGenerator.ZoomPlan(
            events: [],
            keyframes: keyframes,
            configuration: .default(),
            stats: ZoomPlanGenerator.ZoomPlanStats(
                totalZoomEvents: 2,
                totalKeyframes: 8,
                totalZoomedTime: 14,
                zoomedTimePercentage: 56.0,
                averageZoomLevel: 1.75,
                maximumZoomLevel: 2.5,
                averageTimeBetweenZooms: 5.0,
                zoomsPerMinute: 4.8,
                timeRange: 0...25
            )
        )

        await previewEngine.loadZoomPlan(zoomPlan)

        // Test first zoom event
        let zoomLevel1 = await previewEngine.getZoomLevel(at: 3)
        XCTAssertEqual(zoomLevel1, 2.0, accuracy: 0.1)

        // Test between zoom events (should be 1.0)
        let zoomLevel2 = await previewEngine.getZoomLevel(at: 10)
        XCTAssertEqual(zoomLevel2, 1.0, accuracy: 0.1)

        // Test second zoom event
        let zoomLevel3 = await previewEngine.getZoomLevel(at: 18)
        XCTAssertEqual(zoomLevel3, 2.5, accuracy: 0.1)
    }

    // MARK: - Helper Methods for Zoom Tests

    private func createMockZoomPlan() -> ZoomPlanGenerator.ZoomPlan {
        let keyframes = [
            ZoomPlanGenerator.ZoomKeyframe(
                timestamp: 0,
                zoomLevel: 1.0,
                focusX: 0.5,
                focusY: 0.5,
                easing: .easeInOut
            ),
            ZoomPlanGenerator.ZoomKeyframe(
                timestamp: 5,
                zoomLevel: 2.5,
                focusX: 0.6,
                focusY: 0.4,
                easing: .easeInOut
            ),
            ZoomPlanGenerator.ZoomKeyframe(
                timestamp: 8,
                zoomLevel: 2.5,
                focusX: 0.6,
                focusY: 0.4,
                easing: .easeInOut
            ),
            ZoomPlanGenerator.ZoomKeyframe(
                timestamp: 10,
                zoomLevel: 1.0,
                focusX: 0.5,
                focusY: 0.5,
                easing: .easeInOut
            )
        ]

        let zoomEvent = ZoomPlanGenerator.ZoomEvent(
            zoomInStartTime: 5,
            zoomInEndTime: 5.5,
            holdEndTime: 8,
            zoomOutEndTime: 10,
            targetZoomLevel: 2.5,
            focusX: 0.6,
            focusY: 0.4,
            clickWindowId: UUID(),
            easing: .easeInOut
        )

        return ZoomPlanGenerator.ZoomPlan(
            events: [zoomEvent],
            keyframes: keyframes,
            configuration: .default(),
            stats: ZoomPlanGenerator.ZoomPlanStats(
                totalZoomEvents: 1,
                totalKeyframes: 4,
                totalZoomedTime: 5,
                zoomedTimePercentage: 50.0,
                averageZoomLevel: 1.75,
                maximumZoomLevel: 2.5,
                averageTimeBetweenZooms: 0,
                zoomsPerMinute: 6.0,
                timeRange: 0...10
            )
        )
    }
    */
}
