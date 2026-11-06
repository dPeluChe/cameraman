import XCTest
@testable import EngineKit

final class MusicPlacementTests: XCTestCase {
    private let music = RenderedMusic(file: URL(fileURLWithPath: "/project/assets/music-0a1b2c3d.m4a"), seconds: 10)

    private let project = Project(
        projectId: UUID(), name: "music", timeline: Project.Timeline(duration: 30, tracks: []),
        canvas: Project.Canvas(format: Project.Canvas.Format(aspect: "16:9", w: 1920, h: 1080),
                               background: Project.Canvas.Background(type: "solid", value: "#000000", fitMode: nil),
                               layout: Project.Canvas.Layout(type: "pip", camera: nil)))

    private func clips(_ editor: EditorModel) async -> [Project.TimelineClip] {
        await editor.projectRef.timeline.tracks.first { $0.name == MusicSource.trackName }?.clips ?? []
    }

    func testANewMusicTrackDucksAndTheNextPieceSharesIt() async throws {
        let editor = EditorModel(project: project)
        _ = await editor.addMusic(music, at: 0)
        _ = await editor.addMusic(music, at: 10)

        let tracks = await editor.projectRef.timeline.tracks.filter { $0.name == MusicSource.trackName }
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].duckingLevel, MusicSource.defaultDucking)
        XCTAssertEqual(tracks[0].clips.map(\.volume), [MusicSource.defaultVolume, MusicSource.defaultVolume])
    }

    func testOverlappingMusicGoesOnANewTrack() async throws {
        let editor = EditorModel(project: project)
        _ = await editor.addMusic(music, at: 0)
        _ = await editor.addMusic(music, at: 5)
        let count = await editor.projectRef.timeline.tracks.filter { $0.name == MusicSource.trackName }.count
        XCTAssertEqual(count, 2)
    }

    func testReplacingKeepsTheClipAndItsVolume() async throws {
        let editor = EditorModel(project: project)
        _ = await editor.addMusic(music, at: 3, volume: 0.4)
        let added = await clips(editor)
        let clip = try XCTUnwrap(added.first)
        let tracks = await editor.projectRef.timeline.tracks
        let trackId = try XCTUnwrap(tracks.first { $0.name == MusicSource.trackName }?.id)

        let longer = RenderedMusic(file: URL(fileURLWithPath: "/project/assets/music-1b2c3d4e.m4a"), seconds: 20)
        _ = await editor.replaceMusic(clipId: clip.id, inTrackId: trackId, with: longer)

        let after = await clips(editor)
        let replaced = try XCTUnwrap(after.first)
        XCTAssertEqual(replaced.id, clip.id)
        XCTAssertEqual(replaced.timelineIn, 3)
        XCTAssertEqual(replaced.volume, 0.4)
        XCTAssertEqual(replaced.duration, 20)
        guard case .audio(let ref) = replaced.content else { return XCTFail("not audio") }
        XCTAssertEqual(ref.path, "assets/music-1b2c3d4e.m4a")
    }
}
