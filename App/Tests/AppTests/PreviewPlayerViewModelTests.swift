//
//  PreviewPlayerViewModelTests.swift
//  AppTests
//
//  Created by Ralphy on 2026-01-20.
//

import AVFoundation
import XCTest
@testable import App
@testable import EngineKit

@MainActor
final class PreviewPlayerViewModelTests: XCTestCase {
    func testLoadProjectSetsAspectRatioAndEngine() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewPlayerViewModelTests_\(UUID().uuidString)", isDirectory: true)
        let sourcesDirectory = tempDirectory.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)

        let screenURL = sourcesDirectory.appendingPathComponent("screen.mov")
        FileManager.default.createFile(atPath: screenURL.path, contents: Data())

        let project = makeProject(screenSize: Project.Sources.Size(w: 1920, h: 1080))
        let viewModel = PreviewPlayerViewModel()

        viewModel.load(project: project, projectDirectory: tempDirectory)

        // Wait for async load
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        XCTAssertNotNil(viewModel.previewEngine)
        XCTAssertNil(viewModel.loadError)
        XCTAssertEqual(viewModel.aspectRatio, 16.0 / 9.0, accuracy: 0.01)

        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testLoadProjectMissingSourceSetsError() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewPlayerViewModelTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let project = makeProject(screenSize: Project.Sources.Size(w: 1280, h: 720))
        let viewModel = PreviewPlayerViewModel()

        viewModel.load(project: project, projectDirectory: tempDirectory)

        // Wait for async load
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        XCTAssertNil(viewModel.previewEngine)
        XCTAssertNotNil(viewModel.loadError)
        XCTAssertEqual(viewModel.aspectRatio, 16.0 / 9.0, accuracy: 0.01)

        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testLoadProjectSetsTimelineDuration() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewPlayerViewModelTests_\(UUID().uuidString)", isDirectory: true)
        let sourcesDirectory = tempDirectory.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)

        let screenURL = sourcesDirectory.appendingPathComponent("screen.mov")
        FileManager.default.createFile(atPath: screenURL.path, contents: Data())

        let project = makeProject(screenSize: Project.Sources.Size(w: 1920, h: 1080))
        let viewModel = PreviewPlayerViewModel()

        viewModel.load(project: project, projectDirectory: tempDirectory)

        // Wait for async load
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        XCTAssertEqual(viewModel.duration, project.timeline.duration, accuracy: 0.01)

        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testFormatTimeOutputsExpectedStrings() {
        XCTAssertEqual(PreviewPlayerViewModel.formatTime(0), "0:00")
        XCTAssertEqual(PreviewPlayerViewModel.formatTime(65.2), "1:05")
        XCTAssertEqual(PreviewPlayerViewModel.formatTime(3661.9), "1:01:01")
    }

    func testStopPlaybackResetsCurrentTime() {
        let viewModel = PreviewPlayerViewModel()

        viewModel.updateDuration(12)
        viewModel.seek(to: 8)
        viewModel.stopPlayback()

        XCTAssertEqual(viewModel.currentTime, 0, accuracy: 0.01)
        XCTAssertFalse(viewModel.isPlaying)
    }

    func testResetClearsAllState() {
        let viewModel = PreviewPlayerViewModel()

        viewModel.updateDuration(10)
        viewModel.seek(to: 5)
        viewModel.reset()

        XCTAssertNil(viewModel.previewEngine)
        XCTAssertNil(viewModel.currentFrame)
        XCTAssertNil(viewModel.loadError)
        XCTAssertEqual(viewModel.currentTime, 0, accuracy: 0.01)
        XCTAssertEqual(viewModel.duration, 0, accuracy: 0.01)
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertFalse(viewModel.isScrubbing)
        XCTAssertEqual(viewModel.playbackRate, .normal)
    }

    func testToggleVisibilityFlags() {
        let viewModel = PreviewPlayerViewModel()

        XCTAssertTrue(viewModel.showOverlays)
        XCTAssertTrue(viewModel.showLayout)
        XCTAssertTrue(viewModel.showZoom)
        XCTAssertTrue(viewModel.showCaptions)

        viewModel.showOverlays = false
        viewModel.showLayout = false
        viewModel.showZoom = false
        viewModel.showCaptions = false

        XCTAssertFalse(viewModel.showOverlays)
        XCTAssertFalse(viewModel.showLayout)
        XCTAssertFalse(viewModel.showZoom)
        XCTAssertFalse(viewModel.showCaptions)
    }

    func testSetScrubbing() {
        let viewModel = PreviewPlayerViewModel()

        XCTAssertFalse(viewModel.isScrubbing)
        viewModel.setScrubbing(true)
        XCTAssertTrue(viewModel.isScrubbing)
        viewModel.setScrubbing(false)
        XCTAssertFalse(viewModel.isScrubbing)
    }

    func testPlaybackRateSelection() {
        let viewModel = PreviewPlayerViewModel()

        XCTAssertEqual(viewModel.playbackRate, .normal)

        viewModel.setPlaybackRate(.half)
        XCTAssertEqual(viewModel.playbackRate, .half)

        viewModel.setPlaybackRate(.double)
        XCTAssertEqual(viewModel.playbackRate, .double)

        viewModel.setPlaybackRate(.normal)
        XCTAssertEqual(viewModel.playbackRate, .normal)
    }

    func testClampTime() {
        let viewModel = PreviewPlayerViewModel()

        viewModel.updateDuration(10)

        viewModel.seek(to: 5)
        XCTAssertEqual(viewModel.currentTime, 5, accuracy: 0.01)

        viewModel.seek(to: -5)
        XCTAssertEqual(viewModel.currentTime, 0, accuracy: 0.01)

        viewModel.seek(to: 15)
        XCTAssertEqual(viewModel.currentTime, 10, accuracy: 0.01)
    }

    func testAspectRatioForProject() {
        let project16x9 = makeProject(screenSize: Project.Sources.Size(w: 1920, h: 1080))
        let ratio16x9 = PreviewPlayerViewModel.aspectRatio(for: project16x9)
        XCTAssertEqual(ratio16x9, 16.0 / 9.0, accuracy: 0.01)

        let project9x16 = makeProject(screenSize: Project.Sources.Size(w: 1080, h: 1920))
        let ratio9x16 = PreviewPlayerViewModel.aspectRatio(for: project9x16)
        XCTAssertEqual(ratio9x16, 9.0 / 16.0, accuracy: 0.01)

        let project1x1 = makeProject(screenSize: Project.Sources.Size(w: 1080, h: 1080))
        let ratio1x1 = PreviewPlayerViewModel.aspectRatio(for: project1x1)
        XCTAssertEqual(ratio1x1, 1.0, accuracy: 0.01)
    }

    private func makeProject(screenSize: Project.Sources.Size) -> Project {
        let segment = Project.Timeline.Segment(
            id: "seg-1",
            sourceIn: 0.0,
            sourceOut: 5.0,
            timelineIn: 0.0,
            speed: 1.0
        )

        let timeline = Project.Timeline(duration: 5.0, segments: [segment])

        let sources = Project.Sources(
            syncReference: "screen",
            screen: Project.Sources.MediaTrack(
                path: "sources/screen.mov",
                fps: 60.0,
                size: screenSize,
                syncOffsetMs: 0,
                sha256: "test",
                sizeBytes: 0
            ),
            camera: nil,
            audio: nil,
            telemetry: nil
        )

        let canvas = Project.Canvas(
            format: Project.Canvas.Format(aspect: "16:9", w: screenSize.w, h: screenSize.h),
            background: Project.Canvas.Background(type: "solid", value: "#000000", fitMode: nil),
            layout: Project.Canvas.Layout(type: "full", camera: nil)
        )

        return Project(
            schemaVersion: 1,
            projectId: UUID(),
            name: "Preview Test",
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
}
