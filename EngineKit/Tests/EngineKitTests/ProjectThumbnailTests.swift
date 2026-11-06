import XCTest
@testable import EngineKit

final class ProjectThumbnailTests: XCTestCase {
    private func project(_ tracks: [Project.TimelineTrack]) -> Project {
        Project(projectId: UUID(), name: "thumbnail", timeline: Project.Timeline(duration: 30, tracks: tracks),
                canvas: Project.Canvas(format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                                       background: Project.Canvas.Background(type: "solid", value: "#000000", fitMode: nil),
                                       layout: Project.Canvas.Layout(type: "pip", camera: nil)))
    }

    func testAnImportedVideoIsUsedAMomentIn() throws {
        let clip = Project.TimelineClip(timelineIn: 0, content: .video(Project.VideoClipRef(path: "assets/a.mov", sourceIn: 4, sourceOut: 8)))
        let source = try XCTUnwrap(project([Project.TimelineTrack(name: "B-roll", type: .video, clips: [clip])]).thumbnailSource())
        XCTAssertEqual(source.path, "assets/a.mov")
        XCTAssertEqual(source.time, 4.4, accuracy: 0.001)
    }

    func testMotionsAndAudioAreNotFootage() {
        let motion = Project.TimelineClip(timelineIn: 0, content: .video(Project.VideoClipRef(path: "assets/motion-0a1b2c3d.mov", sourceOut: 4)))
        let music = Project.TimelineClip(timelineIn: 0, content: .audio(Project.AudioClipRef(path: "assets/music-0a1b2c3d.m4a", duration: 4)))
        XCTAssertNil(project([
            Project.TimelineTrack(name: "Motion", type: .video, clips: [motion]),
            Project.TimelineTrack(name: "Music", type: .audio, clips: [music]),
        ]).thumbnailSource())
    }
}
