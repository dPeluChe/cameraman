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
    func testLoadProjectSetsAspectRatioAndPlayer() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewPlayerViewModelTests_\(UUID().uuidString)", isDirectory: true)
        let sourcesDirectory = tempDirectory.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)

        let screenURL = sourcesDirectory.appendingPathComponent("screen.mov")
        FileManager.default.createFile(atPath: screenURL.path, contents: Data())

        let project = makeProject(screenSize: Project.Sources.Size(w: 1920, h: 1080))
        let viewModel = PreviewPlayerViewModel()

        viewModel.load(project: project, projectDirectory: tempDirectory)

        XCTAssertNotNil(viewModel.player)
        XCTAssertNil(viewModel.loadError)
        XCTAssertEqual(viewModel.aspectRatio, 16.0 / 9.0, accuracy: 0.01)

        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testLoadProjectMissingSourceSetsError() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewPlayerViewModelTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let project = makeProject(screenSize: Project.Sources.Size(w: 1280, h: 720))
        let viewModel = PreviewPlayerViewModel()

        viewModel.load(project: project, projectDirectory: tempDirectory)

        XCTAssertNil(viewModel.player)
        XCTAssertNotNil(viewModel.loadError)
        XCTAssertEqual(viewModel.aspectRatio, 16.0 / 9.0, accuracy: 0.01)

        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testLoadProjectSetsTimelineDuration() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewPlayerViewModelTests_\(UUID().uuidString)", isDirectory: true)
        let sourcesDirectory = tempDirectory.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)

        let screenURL = sourcesDirectory.appendingPathComponent("screen.mov")
        FileManager.default.createFile(atPath: screenURL.path, contents: Data())

        let project = makeProject(screenSize: Project.Sources.Size(w: 1920, h: 1080))
        let viewModel = PreviewPlayerViewModel()

        viewModel.load(project: project, projectDirectory: tempDirectory)

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
