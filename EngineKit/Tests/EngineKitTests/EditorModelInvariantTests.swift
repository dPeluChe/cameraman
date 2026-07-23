import XCTest
@testable import EngineKit

final class EditorModelInvariantTests: XCTestCase {
    func testLockedTrackRejectsEveryContentMutation() async throws {
        let fixture = makeProject(locked: true)
        let editor = EditorModel(project: fixture.project)
        let adjustment = try XCTUnwrap(fixture.clip.adjustments?.first)

        assertTrackLocked(await editor.updateClip(
            clipId: fixture.clip.id,
            inTrackId: fixture.lockedTrackId,
            timelineIn: 2
        ), trackId: fixture.lockedTrackId)
        assertTrackLocked(await editor.splitClip(
            clipId: fixture.clip.id,
            inTrackId: fixture.lockedTrackId,
            at: 2
        ), trackId: fixture.lockedTrackId)
        assertTrackLocked(await editor.moveClip(
            clipId: fixture.clip.id,
            fromTrackId: fixture.lockedTrackId,
            toTrackId: fixture.unlockedTrackId
        ), trackId: fixture.lockedTrackId)
        assertTrackLocked(await editor.addAdjustment(
            Project.Adjustment(kind: .sepia),
            toClipId: fixture.clip.id,
            inTrackId: fixture.lockedTrackId
        ), trackId: fixture.lockedTrackId)
        assertTrackLocked(await editor.updateAdjustment(
            adjustment,
            inClipId: fixture.clip.id,
            trackId: fixture.lockedTrackId
        ), trackId: fixture.lockedTrackId)
        assertTrackLocked(await editor.removeAdjustment(
            adjustment.id,
            fromClipId: fixture.clip.id,
            inTrackId: fixture.lockedTrackId
        ), trackId: fixture.lockedTrackId)
        assertTrackLocked(await editor.clearAdjustments(
            clipId: fixture.clip.id,
            inTrackId: fixture.lockedTrackId
        ), trackId: fixture.lockedTrackId)
        assertTrackLocked(await editor.setClipAudioMuted(
            clipId: fixture.clip.id,
            inTrackId: fixture.lockedTrackId,
            muted: true
        ), trackId: fixture.lockedTrackId)
        assertTrackLocked(await editor.moveVideoTrack(
            trackId: fixture.lockedTrackId,
            up: false
        ), trackId: fixture.lockedTrackId)
        assertTrackLocked(await editor.removeTrack(
            trackId: fixture.lockedTrackId
        ), trackId: fixture.lockedTrackId)

        let unchanged = await editor.getProject()
        XCTAssertEqual(unchanged, fixture.project)
    }

    func testMoveClipRejectsLockedDestination() async {
        let fixture = makeProject(locked: true)
        let editor = EditorModel(project: fixture.project)
        let sourceClip = fixture.project.timeline.tracks
            .first { $0.id == fixture.unlockedTrackId }!.clips[0]

        assertTrackLocked(await editor.moveClip(
            clipId: sourceClip.id,
            fromTrackId: fixture.unlockedTrackId,
            toTrackId: fixture.lockedTrackId
        ), trackId: fixture.lockedTrackId)
    }

    func testInvalidClipValuesAreRejectedWithoutMutation() async {
        let fixture = makeProject(locked: false)
        let editor = EditorModel(project: fixture.project)
        let sourceClip = fixture.project.timeline.tracks
            .first { $0.id == fixture.unlockedTrackId }!.clips[0]

        assertInvalidClip(await editor.addClip(
            Project.TimelineClip(
                timelineIn: -.infinity,
                content: .image(Project.ImageClipRef(path: "image.png", duration: 2))
            ),
            toTrackId: fixture.unlockedTrackId
        ))
        assertInvalidClip(await editor.updateClip(
            clipId: sourceClip.id,
            inTrackId: fixture.unlockedTrackId,
            speed: 0
        ))
        assertInvalidClip(await editor.moveClip(
            clipId: sourceClip.id,
            fromTrackId: fixture.unlockedTrackId,
            toTrackId: fixture.unlockedTrackId,
            newTimelineIn: -1
        ))
        assertInvalidClip(await editor.setTrackVolume(
            trackId: fixture.unlockedTrackId,
            volume: .nan
        ))
        assertInvalidClip(await editor.importVideoClip(
            path: "video.mov",
            duration: 0,
            at: 0
        ))

        let unchanged = await editor.getProject()
        XCTAssertEqual(unchanged, fixture.project)
    }

    func testValidClipCandidateIsApplied() async {
        let fixture = makeProject(locked: false)
        let editor = EditorModel(project: fixture.project)
        let sourceClip = fixture.project.timeline.tracks
            .first { $0.id == fixture.unlockedTrackId }!.clips[0]

        let result = await editor.updateClip(
            clipId: sourceClip.id,
            inTrackId: fixture.unlockedTrackId,
            timelineIn: 2,
            speed: 2,
            volume: 0.5,
            opacity: 0.75,
            position: Project.MediaPosition(x: 0.1, y: 0.1, w: 0.5, h: 0.5)
        )

        guard let project = result.getProject(),
              let updated = project.timeline.tracks
                .first(where: { $0.id == fixture.unlockedTrackId })?.clips
                .first(where: { $0.id == sourceClip.id }) else {
            return XCTFail("Expected updated clip")
        }
        XCTAssertEqual(updated.timelineIn, 2)
        XCTAssertEqual(updated.speed, 2)
        XCTAssertEqual(updated.volume, 0.5)
        XCTAssertEqual(updated.opacity, 0.75)
    }

    func testInvalidAdjustmentsAndConvenienceClipsDoNotMutateProject() async throws {
        let fixture = makeProject(locked: false)
        let editor = EditorModel(project: fixture.project)
        let adjustment = try XCTUnwrap(fixture.clip.adjustments?.first)

        assertInvalidClip(await editor.addAdjustment(
            Project.Adjustment(kind: .sepia, parameters: ["intensity": 2]),
            toClipId: fixture.clip.id,
            inTrackId: fixture.lockedTrackId
        ))
        var invalidUpdate = adjustment
        invalidUpdate.end = 20
        assertInvalidClip(await editor.updateAdjustment(
            invalidUpdate,
            inClipId: fixture.clip.id,
            trackId: fixture.lockedTrackId
        ))
        assertInvalidClip(await editor.addAdjustment(
            Project.Adjustment(kind: .audioPitch, target: .frame, parameters: ["cents": .nan]),
            toClipId: fixture.clip.id,
            inTrackId: fixture.lockedTrackId
        ))
        assertInvalidClip(await editor.addImageClip(path: "", duration: 2, at: 0))
        assertInvalidClip(await editor.addAudioClip(path: "audio.wav", duration: -1, at: 0))
        assertInvalidClip(await editor.addColorClip(duration: .infinity, at: 0))

        let unchanged = await editor.getProject()
        XCTAssertEqual(unchanged, fixture.project)
    }

    func testValidAdjustmentIsApplied() async {
        let fixture = makeProject(locked: false)
        let editor = EditorModel(project: fixture.project)
        let adjustment = Project.Adjustment(
            kind: .vignette,
            parameters: ["intensity": 0.7, "radius": 1.5],
            start: 1,
            end: 4
        )

        let result = await editor.addAdjustment(
            adjustment,
            toClipId: fixture.clip.id,
            inTrackId: fixture.lockedTrackId
        )

        guard let project = result.getProject(),
              let clip = project.timeline.tracks
                .first(where: { $0.id == fixture.lockedTrackId })?.clips.first else {
            return XCTFail("Expected adjusted clip")
        }
        XCTAssertTrue(clip.adjustments?.contains(adjustment) == true)
    }

    func testInvalidOverlayMediaAndRangeDoNotMutateProject() async {
        let fixture = makeProject(locked: false)
        let editor = EditorModel(project: fixture.project)
        let overlay = makeOverlay(scale: 0)
        let mediaItem = Project.MediaItem(
            type: .image,
            path: "image.png",
            name: "Image",
            timelineIn: 0,
            duration: 2
        )

        assertInvalidClip(await editor.addOverlay(
            projectId: fixture.project.projectId,
            overlay: overlay
        ))
        assertInvalidClip(await editor.addMediaItem(Project.MediaItem(
            type: .image,
            path: "image.png",
            name: "Invalid",
            timelineIn: 0,
            duration: .nan
        )))
        _ = await editor.addMediaItem(mediaItem)
        let afterValidAdd = await editor.getProject()
        assertInvalidClip(await editor.updateMediaItem(id: mediaItem.id, opacity: 2))
        guard case .failure(.invalidRange) = await editor.deleteRange(from: -1, to: 1) else {
            return XCTFail("Expected invalidRange")
        }
        let unchanged = await editor.getProject()
        XCTAssertEqual(unchanged, afterValidAdd)
    }

    func testOverlayCandidateValidationPreventsPartialUpdate() async {
        let fixture = makeProject(locked: false)
        var project = fixture.project
        let overlay = makeOverlay()
        project.overlays = [overlay]
        let editor = EditorModel(project: project)

        assertInvalidClip(await editor.updateOverlay(
            projectId: project.projectId,
            overlayId: overlay.id,
            transform: Project.Overlay.Transform(x: .nan, y: 0.5, scale: 1),
            start: 1
        ))
        let unchanged = await editor.getProject()
        XCTAssertEqual(unchanged, project)
    }

    func testInvalidLegacySegmentInputsDoNotMutateProject() async {
        var fixture = makeProject(locked: false)
        let recording = Project.TimelineClip(
            id: "recording",
            timelineIn: 0,
            content: .recording(Project.RecordingClipRef(sourceIn: 0, sourceOut: 5))
        )
        fixture.project.timeline.tracks[0].clips = [recording]
        fixture.project.timeline.duration = 5
        let take = Project.Take(
            name: "Take",
            sources: Project.Sources(screen: Project.Sources.MediaTrack(
                path: "screen.mov",
                fps: 60,
                size: Project.Sources.Size(w: 1920, h: 1080)
            ))
        )
        fixture.project.takes = [take]
        let editor = EditorModel(project: fixture.project)

        assertInvalidClip(await editor.trimOut(segmentId: recording.id, newSourceOut: .infinity))
        assertInvalidClip(await editor.addSegment(
            takeId: take.id, sourceIn: 0, sourceOut: .infinity, timelineIn: 0
        ))
        let unchanged = await editor.getProject()
        XCTAssertEqual(unchanged, fixture.project)
    }

    func testDeleteRangePreservesClipAdjustments() async {
        let fixture = makeProject(locked: false)
        let editor = EditorModel(project: fixture.project)

        let result = await editor.deleteRange(from: 1, to: 2)

        guard let project = result.getProject(),
              let clips = project.timeline.tracks
                .first(where: { $0.id == fixture.lockedTrackId })?.clips else {
            return XCTFail("Expected range deletion result")
        }
        XCTAssertEqual(clips.count, 2)
        XCTAssertTrue(clips.allSatisfy { $0.adjustments == fixture.clip.adjustments })
    }

    private func assertTrackLocked(
        _ result: EditorResult,
        trackId: UUID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.trackLocked(let id)) = result else {
            return XCTFail("Expected trackLocked, got \(result)", file: file, line: line)
        }
        XCTAssertEqual(id, trackId.uuidString, file: file, line: line)
    }

    private func assertInvalidClip(
        _ result: EditorResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(.invalidClipContent) = result else {
            return XCTFail("Expected invalidClipContent, got \(result)", file: file, line: line)
        }
    }

    private func makeProject(locked: Bool) -> (
        project: Project,
        clip: Project.TimelineClip,
        lockedTrackId: UUID,
        unlockedTrackId: UUID
    ) {
        let adjustment = Project.Adjustment(kind: .sepia, parameters: ["intensity": 0.5])
        let clip = Project.TimelineClip(
            id: "locked-clip",
            timelineIn: 0,
            content: .video(Project.VideoClipRef(path: "assets/video.mov", sourceOut: 5)),
            adjustments: [adjustment]
        )
        let sourceClip = Project.TimelineClip(
            id: "source-clip",
            timelineIn: 0,
            content: .video(Project.VideoClipRef(path: "assets/source.mov", sourceOut: 5))
        )
        let lockedTrack = Project.TimelineTrack(
            name: "Locked",
            type: .video,
            clips: [clip],
            isLocked: locked
        )
        let unlockedTrack = Project.TimelineTrack(
            name: "Unlocked",
            type: .video,
            clips: [sourceClip]
        )
        let primaryTrack = Project.TimelineTrack(
            id: Project.TimelineTrack.primaryTrackId,
            name: "Recording",
            type: .primary
        )
        let timeline = Project.Timeline(
            duration: 5,
            tracks: [primaryTrack, lockedTrack, unlockedTrack]
        )
        let canvas = Project.Canvas(
            format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
            background: Project.Canvas.Background(type: "solid", value: "#000000"),
            layout: Project.Canvas.Layout(type: "fullscreen")
        )
        let project = Project(
            projectId: UUID(),
            name: "Invariant Test",
            timeline: timeline,
            canvas: canvas
        )
        return (project, clip, lockedTrack.id, unlockedTrack.id)
    }

    private func makeOverlay(scale: Double = 1) -> Project.Overlay {
        Project.Overlay(
            id: UUID(),
            type: .text,
            start: 0,
            end: 2,
            transform: Project.Overlay.Transform(x: 0.5, y: 0.5, scale: scale),
            style: Project.Overlay.Style(
                stroke: "#FFFFFF",
                strokeWidth: 0,
                shadow: false,
                text: "Title"
            ),
            animation: .fadeIn
        )
    }
}
