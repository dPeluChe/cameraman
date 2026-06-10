//
//  ProjectStoreMergeTests.swift
//  EngineKitTests
//
//  Tests for ProjectStore.mergeProjects: timeline concatenation with offset,
//  media copying, legacy take pinning, and collision handling.
//

import XCTest
@testable import EngineKit

@available(macOS 13.0, *)
final class ProjectStoreMergeTests: XCTestCase {
    var tempDirectory: URL!
    var sut: ProjectStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EngineKitMergeTests_\(UUID().uuidString)", isDirectory: true)
        sut = ProjectStore(baseDirectory: tempDirectory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeCanvas() -> Project.Canvas {
        Project.Canvas(
            format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
            background: Project.Canvas.Background(type: "solid", value: "#0B0B0D", fitMode: nil),
            layout: Project.Canvas.Layout(type: "pip", camera: nil)
        )
    }

    private func makeSources(screenFile: String) -> Project.Sources {
        Project.Sources(
            screen: Project.Sources.MediaTrack(
                path: "sources/\(screenFile)",
                fps: 60,
                size: Project.Sources.Size(w: 1920, h: 1080)
            )
        )
    }

    /// Write a project to disk with one take, one primary clip of `duration`,
    /// and a dummy source file named `screenFile`.
    @discardableResult
    private func makeProject(
        name: String,
        duration: TimeInterval,
        screenFile: String,
        takeId: UUID = UUID(),
        legacyNilClipTakeId: Bool = false, // true = clip stores takeId nil ("first take", legacy)
        chapters: [Project.Chapter] = [],
        overlays: [Project.Overlay] = [],
        tags: [String] = []
    ) async throws -> ProjectId {
        let projectId = ProjectId()
        let dir = tempDirectory.appendingPathComponent(projectId.uuidString, isDirectory: true)
        try await sut.createProjectDirectoryStructure(at: dir)
        // Dummy media file
        let sourcePath = dir.appendingPathComponent("sources/\(screenFile)")
        try Data("fake-video".utf8).write(to: sourcePath)

        let resolvedClipTakeId: UUID? = legacyNilClipTakeId ? nil : takeId

        let clip = Project.TimelineClip(
            timelineIn: 0,
            content: .recording(Project.RecordingClipRef(
                takeId: resolvedClipTakeId,
                sourceIn: 0,
                sourceOut: duration
            ))
        )
        let project = Project(
            projectId: projectId,
            name: name,
            takes: [Project.Take(id: takeId, name: "Take 1", sources: makeSources(screenFile: screenFile))],
            timeline: Project.Timeline(
                duration: duration,
                tracks: [Project.TimelineTrack(id: Project.TimelineTrack.primaryTrackId, type: .primary, clips: [clip])]
            ),
            canvas: makeCanvas(),
            overlays: overlays,
            chapters: chapters,
            tags: tags
        )
        try await sut.saveProject(project)
        return projectId
    }

    // MARK: - Tests

    func testMerge_appendsSecondTimelineAfterFirst() async throws {
        let chapterB = Project.Chapter(title: "Intro B", startTime: 1, endTime: 3)
        let overlayB = Project.Overlay(
            id: UUID(), type: .rect, start: 2, end: 4,
            transform: .init(), style: .init(stroke: "#FFFFFF", strokeWidth: 2, shadow: false), animation: nil
        )

        let idA = try await makeProject(name: "A", duration: 10, screenFile: "aaaa_screen.mov", tags: ["demo"])
        let idB = try await makeProject(
            name: "B", duration: 5, screenFile: "bbbb_screen.mov",
            chapters: [chapterB], overlays: [overlayB], tags: ["beta"]
        )

        let mergedId = try await sut.mergeProjects(idA, idB)
        let merged = try await sut.loadProject(projectId: mergedId)

        XCTAssertEqual(merged.name, "A + B")
        XCTAssertEqual(merged.timeline.duration, 15, accuracy: 0.001)
        XCTAssertEqual(merged.takes.count, 2)

        // Primary track has both clips, B's shifted by A's duration
        let primaryClips = merged.timeline.primaryTrack?.clips ?? []
        XCTAssertEqual(primaryClips.count, 2)
        XCTAssertEqual(primaryClips[0].timelineIn, 0, accuracy: 0.001)
        XCTAssertEqual(primaryClips[1].timelineIn, 10, accuracy: 0.001)

        // Time-based metadata shifted
        XCTAssertEqual(merged.chapters.count, 1)
        XCTAssertEqual(merged.chapters[0].startTime, 11, accuracy: 0.001)
        XCTAssertEqual(merged.chapters[0].endTime, 13, accuracy: 0.001)
        XCTAssertEqual(merged.overlays.count, 1)
        XCTAssertEqual(merged.overlays[0].start, 12, accuracy: 0.001)
        XCTAssertEqual(merged.overlays[0].end, 14, accuracy: 0.001)

        XCTAssertEqual(Set(merged.tags), Set(["demo", "beta"]))
    }

    func testMerge_copiesSourceFilesFromBothProjects() async throws {
        let idA = try await makeProject(name: "A", duration: 10, screenFile: "aaaa_screen.mov")
        let idB = try await makeProject(name: "B", duration: 5, screenFile: "bbbb_screen.mov")

        let mergedId = try await sut.mergeProjects(idA, idB)
        let mergedDir = tempDirectory.appendingPathComponent(mergedId.uuidString)

        XCTAssertTrue(FileManager.default.fileExists(atPath: mergedDir.appendingPathComponent("sources/aaaa_screen.mov").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: mergedDir.appendingPathComponent("sources/bbbb_screen.mov").path))

        // Originals untouched
        let dirA = tempDirectory.appendingPathComponent(idA.uuidString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirA.appendingPathComponent("sources/aaaa_screen.mov").path))
    }

    func testMerge_pinsLegacyNilTakeIdsToOwnProject() async throws {
        let takeA = UUID()
        let takeB = UUID()
        // Both projects use legacy clips with takeId == nil ("first take")
        let idA = try await makeProject(name: "A", duration: 10, screenFile: "aaaa_screen.mov", takeId: takeA, legacyNilClipTakeId: true)
        let idB = try await makeProject(name: "B", duration: 5, screenFile: "bbbb_screen.mov", takeId: takeB, legacyNilClipTakeId: true)

        let mergedId = try await sut.mergeProjects(idA, idB)
        let merged = try await sut.loadProject(projectId: mergedId)

        let clips = merged.timeline.primaryTrack?.clips ?? []
        guard clips.count == 2,
              case .recording(let refA) = clips[0].content,
              case .recording(let refB) = clips[1].content else {
            return XCTFail("Expected two recording clips")
        }
        // Each clip must point at ITS OWN project's take, not "first take of merged"
        XCTAssertEqual(refA.takeId, takeA)
        XCTAssertEqual(refB.takeId, takeB)
    }

    func testMerge_sameProject_throws() async throws {
        let idA = try await makeProject(name: "A", duration: 10, screenFile: "aaaa_screen.mov")
        do {
            _ = try await sut.mergeProjects(idA, idA)
            XCTFail("Expected merge with self to throw")
        } catch { /* expected */ }
    }

    func testMerge_filenameCollision_throws() async throws {
        let idA = try await makeProject(name: "A", duration: 10, screenFile: "screen.mov")
        let idB = try await makeProject(name: "B", duration: 5, screenFile: "screen.mov")
        do {
            _ = try await sut.mergeProjects(idA, idB)
            XCTFail("Expected filename collision to throw")
        } catch { /* expected */ }
    }
}
