//
//  AdjustmentTests.swift
//  EngineKitTests
//
//  Covers the extensible adjustment ("effect") model: Codable behaviour,
//  backward-compatibility, render-config flattening, and EditorModel operations.
//

import XCTest
@testable import EngineKit

final class AdjustmentTests: XCTestCase {

    // MARK: - Helpers

    private func makeProject() -> Project {
        let timeline = Project.Timeline(
            duration: 30.0,
            segments: [
                Project.Timeline.Segment(id: "seg-1", sourceIn: 0, sourceOut: 10, timelineIn: 0, speed: 1.0),
                Project.Timeline.Segment(id: "seg-2", sourceIn: 10, sourceOut: 20, timelineIn: 10, speed: 1.0)
            ]
        )
        let sources = Project.Sources(
            syncReference: "screen",
            screen: Project.Sources.MediaTrack(
                path: "sources/screen.mov", fps: 60, size: Project.Sources.Size(w: 1920, h: 1080),
                syncOffsetMs: 0, sha256: "abc", sizeBytes: 1
            ),
            camera: nil, audio: nil, telemetry: nil
        )
        let canvas = Project.Canvas(
            format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
            background: Project.Canvas.Background(type: "solid", value: "#000000", fitMode: nil),
            layout: Project.Canvas.Layout(type: "pip", camera: nil)
        )
        return Project(projectId: UUID(), name: "Test", sources: sources, timeline: timeline, canvas: canvas)
    }

    // MARK: - Codable

    func testAdjustmentKindEncodesAsBareString() throws {
        let adjustment = Project.Adjustment(kind: .sepia, target: .camera, parameters: ["intensity": 0.8])
        let data = try JSONEncoder().encode(adjustment)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"kind\":\"sepia\""), "kind should encode as a bare string, got: \(json)")

        let decoded = try JSONDecoder().decode(Project.Adjustment.self, from: data)
        XCTAssertEqual(decoded.kind, .sepia)
        XCTAssertEqual(decoded.target, .camera)
        XCTAssertEqual(decoded.parameters["intensity"], 0.8)
    }

    func testUnknownKindRoundTrips() throws {
        let custom = Project.AdjustmentKind(rawValue: "myCustomFilter")
        let adjustment = Project.Adjustment(kind: custom, target: .frame)
        let data = try JSONEncoder().encode(adjustment)
        let decoded = try JSONDecoder().decode(Project.Adjustment.self, from: data)
        XCTAssertEqual(decoded.kind.rawValue, "myCustomFilter")
    }

    func testClipOmitsAdjustmentsKeyWhenNil() throws {
        // Backward-compat: a clip without effects must not write the key, and
        // older JSON missing the key must decode to nil (not fail).
        let clip = Project.TimelineClip(
            timelineIn: 0,
            content: .color(Project.ColorClipRef(hexColor: "#FFFFFF", duration: 2))
        )
        let data = try JSONEncoder().encode(clip)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("adjustments"), "nil adjustments must be omitted: \(json)")

        let decoded = try JSONDecoder().decode(Project.TimelineClip.self, from: data)
        XCTAssertNil(decoded.adjustments)
    }

    // MARK: - Flattening to render configs

    func testAdjustmentConfigsUseAbsoluteTimelineRange() async throws {
        let editor = EditorModel(project: makeProject())
        let project0 = await editor.getProject()
        let trackId = project0.timeline.primaryTrack!.id
        let clipId = project0.timeline.primaryTrack!.clips.first(where: { $0.id == "seg-2" })!.id

        let adjustment = Project.Adjustment(kind: .sepia, target: .camera, parameters: ["intensity": 1.0])
        let result = await editor.addAdjustment(adjustment, toClipId: clipId, inTrackId: trackId)
        let project = result.getProject()!

        let configs = project.adjustmentConfigs
        XCTAssertEqual(configs.count, 1)
        XCTAssertEqual(configs[0].kind, "sepia")
        XCTAssertEqual(configs[0].target, .camera)
        // seg-2 starts at t=10 and lasts 10s → absolute window 10…20
        XCTAssertEqual(configs[0].start, 10, accuracy: 0.001)
        XCTAssertEqual(configs[0].end, 20, accuracy: 0.001)
        XCTAssertTrue(configs[0].isActive(at: 15))
        XCTAssertFalse(configs[0].isActive(at: 5))
        XCTAssertTrue(project.hasVisualAdjustments)
    }

    func testAudioAdjustmentRoutesToMicLane() async throws {
        let editor = EditorModel(project: makeProject())
        let project0 = await editor.getProject()
        let trackId = project0.timeline.primaryTrack!.id
        let clipId = project0.timeline.primaryTrack!.clips.first!.id

        let pitch = Project.Adjustment(kind: .audioPitch, target: .audio, parameters: ["semitones": -3])
        let result = await editor.addAdjustment(pitch, toClipId: clipId, inTrackId: trackId)
        let project = result.getProject()!

        // Audio adjustments are not visual.
        XCTAssertTrue(project.adjustmentConfigs.isEmpty)
        let specs = project.audioAdjustmentSpecs
        XCTAssertEqual(specs.count, 1)
        XCTAssertEqual(specs[0].lane, .mic)
        XCTAssertEqual(specs[0].kind, "audioPitch")
    }

    func testRemoveAdjustmentClearsConfig() async throws {
        let editor = EditorModel(project: makeProject())
        let project0 = await editor.getProject()
        let trackId = project0.timeline.primaryTrack!.id
        let clipId = project0.timeline.primaryTrack!.clips.first!.id

        let adjustment = Project.Adjustment(kind: .monochrome, target: .background)
        _ = await editor.addAdjustment(adjustment, toClipId: clipId, inTrackId: trackId)
        let afterRemove = await editor.removeAdjustment(adjustment.id, fromClipId: clipId, inTrackId: trackId)
        let project = afterRemove.getProject()!

        XCTAssertFalse(project.hasVisualAdjustments)
        XCTAssertTrue(project.adjustmentConfigs.isEmpty)
    }

    func testSplitInheritsAdjustments() async throws {
        let editor = EditorModel(project: makeProject())
        let project0 = await editor.getProject()
        let trackId = project0.timeline.primaryTrack!.id
        let clipId = project0.timeline.primaryTrack!.clips.first!.id

        let adjustment = Project.Adjustment(kind: .sepia, target: .frame)
        _ = await editor.addAdjustment(adjustment, toClipId: clipId, inTrackId: trackId)
        let splitResult = await editor.splitClip(clipId: clipId, inTrackId: trackId, at: 5)
        let project = splitResult.getProject()!

        let primaryClips = project.timeline.primaryTrack!.clips
        // The original seg-1 (0…10) is now two clips, both carrying the effect.
        let halves = primaryClips.filter { ($0.adjustments?.isEmpty == false) }
        XCTAssertEqual(halves.count, 2)
    }

    // MARK: - Cutting a clip keeps effects where they belong

    private func slice(_ start: Double?, _ end: Double?, from: Double, to: Double, keep: Bool = true) -> [Project.Adjustment]? {
        let a = Project.Adjustment(kind: .gaussianBlur, target: .frame, parameters: ["radius": 8], start: start, end: end)
        return Project.Adjustment.slicing([a], clipDuration: 10, from: from, to: to, keepIDs: keep)
    }

    func testWholeClipEffectStaysWholeClipOnBothHalvesWithDistinctIds() async throws {
        let editor = EditorModel(project: makeProject())
        let p0 = await editor.getProject()
        let trackId = p0.timeline.primaryTrack!.id, clipId = p0.timeline.primaryTrack!.clips.first!.id
        let adj = Project.Adjustment(kind: .sepia, target: .frame)
        _ = await editor.addAdjustment(adj, toClipId: clipId, inTrackId: trackId)
        let halves = await editor.splitClip(clipId: clipId, inTrackId: trackId, at: 5).getProject()!
            .timeline.primaryTrack!.clips.prefix(2)
        let ids = halves.compactMap { $0.adjustments?.first?.id }
        XCTAssertEqual(ids.count, 2)
        XCTAssertNotEqual(ids[0], ids[1], "two clips must not share an effect's identity")
        XCTAssertEqual(ids[0], adj.id, "the half that continues the original keeps its id")
        for half in halves {
            XCTAssertNil(half.adjustments?.first?.start)
            XCTAssertNil(half.adjustments?.first?.end)
        }
    }

    func testTimedEffectIsRebasedOntoTheSecondHalfOfASplit() async throws {
        let editor = EditorModel(project: makeProject())
        let p0 = await editor.getProject()
        let trackId = p0.timeline.primaryTrack!.id, clipId = p0.timeline.primaryTrack!.clips.first!.id
        // A blur from 6s to 9s of a 10s clip, then a split at 5s.
        let adj = Project.Adjustment(kind: .gaussianBlur, target: .frame, parameters: ["radius": 8], start: 6, end: 9)
        _ = await editor.addAdjustment(adj, toClipId: clipId, inTrackId: trackId)
        let clips = await editor.splitClip(clipId: clipId, inTrackId: trackId, at: 5).getProject()!
            .timeline.primaryTrack!.clips
        XCTAssertNil(clips[0].adjustments, "the blur starts after the cut, so the first half has none")
        let second = try XCTUnwrap(clips[1].adjustments?.first)
        XCTAssertEqual(second.start ?? -1, 1, accuracy: 0.0001, "6s in the old clip is 1s into the second half")
        XCTAssertEqual(second.end ?? -1, 4, accuracy: 0.0001)
    }

    func testEffectStraddlingTheCutIsClampedOnEachSide() {
        let first = slice(3, 8, from: 0, to: 5)
        XCTAssertEqual(first?.first?.start ?? -1, 3, accuracy: 0.0001)
        XCTAssertNil(first?.first?.end, "it runs to the end of the first piece")
        let second = slice(3, 8, from: 5, to: 10, keep: false)
        XCTAssertNil(second?.first?.start, "it is already active at the start of the second piece")
        XCTAssertEqual(second?.first?.end ?? -1, 3, accuracy: 0.0001)
    }

    func testRangeDeleteRebasesTheEffectOfTheClipAfterTheGap() async throws {
        let editor = EditorModel(project: makeProject())
        let p0 = await editor.getProject()
        let trackId = p0.timeline.primaryTrack!.id, clipId = p0.timeline.primaryTrack!.clips.first!.id
        let adj = Project.Adjustment(kind: .gaussianBlur, target: .frame, parameters: ["radius": 8], start: 5, end: 9)
        _ = await editor.addAdjustment(adj, toClipId: clipId, inTrackId: trackId)
        // Delete 4..6 inside the first clip (0..10): the part before keeps nothing, the part after starts at old 6s.
        let result = await editor.deleteRange(from: 4, to: 6)
        let clips = try XCTUnwrap(result.getProject()?.timeline.primaryTrack?.clips)
        XCTAssertNil(clips[0].adjustments, "the blur (5-9) lies after the part that is kept before the gap")
        let after = try XCTUnwrap(clips[1].adjustments?.first)
        XCTAssertNil(after.start, "5s is inside the deleted range, so it is active from the start of what remains")
        XCTAssertEqual(after.end ?? -1, 3, accuracy: 0.0001, "9s in the old clip is 3s after the cut at 6s")
    }

    func testNoEffectsStayNil() {
        XCTAssertNil(Project.Adjustment.slicing(nil, clipDuration: 10, from: 0, to: 5, keepIDs: true))
        XCTAssertNil(Project.Adjustment.slicing([], clipDuration: 10, from: 0, to: 5, keepIDs: true))
    }
}
