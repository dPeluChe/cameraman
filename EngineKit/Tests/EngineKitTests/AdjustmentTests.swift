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
}
