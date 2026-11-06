import XCTest
@testable import EngineKit

final class ProjectClipNamesTests: XCTestCase {
    private func motion(_ hash: String, at start: TimeInterval) -> Project.TimelineClip {
        Project.TimelineClip(timelineIn: start, content: .video(Project.VideoClipRef(path: "assets/motion-\(hash).mov", sourceOut: 4)))
    }

    func testMotionsAreNumberedInTimelineOrderAcrossTracks() {
        let late = motion("0a1b2c3d", at: 20), early = motion("1b2c3d4e", at: 5)
        let music = Project.TimelineClip(timelineIn: 0, content: .audio(Project.AudioClipRef(path: "assets/music-0a1b2c3d.m4a", duration: 4)))
        let imported = Project.TimelineClip(timelineIn: 0, content: .video(Project.VideoClipRef(path: "assets/broll.mp4", sourceOut: 4)))
        let timeline = Project.Timeline(duration: 30, tracks: [
            Project.TimelineTrack(name: "Motion", type: .video, clips: [late]),
            Project.TimelineTrack(name: "Motion", type: .video, clips: [early]),
            Project.TimelineTrack(name: "B-roll", type: .video, clips: [imported]),
            Project.TimelineTrack(name: "Music", type: .audio, clips: [music]),
        ])
        let names = timeline.clipNames
        XCTAssertEqual(names[early.id], "Motion 1")
        XCTAssertEqual(names[late.id], "Motion 2")
        XCTAssertEqual(names[music.id], "Music")
        XCTAssertEqual(names[imported.id], "broll.mp4")
    }

    func testOnlyVisibleTracksSharingANameGetALetter() {
        let first = Project.TimelineTrack(name: "Motion", type: .video, clips: [motion("0a1b2c3d", at: 0)])
        let second = Project.TimelineTrack(name: "Motion", type: .video, clips: [motion("1b2c3d4e", at: 0)])
        let music = Project.TimelineTrack(name: "Music", type: .audio, clips: [])
        var unnamed = Project.TimelineTrack(name: "Old", type: .video, clips: [])
        unnamed.name = ""
        let timeline = Project.Timeline(duration: 10, tracks: [first, second, music, unnamed])
        XCTAssertEqual(timeline.label(of: first), "Motion A")
        XCTAssertEqual(timeline.label(of: second), "Motion B")
        XCTAssertEqual(timeline.label(of: music), "Music")
        XCTAssertNil(timeline.label(of: unnamed))

        let alone = Project.Timeline(duration: 10, tracks: [Project.TimelineTrack(name: "Motion", type: .video, clips: []), second])
        XCTAssertEqual(alone.label(of: second), "Motion")
    }
}
