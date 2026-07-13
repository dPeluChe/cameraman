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
}
