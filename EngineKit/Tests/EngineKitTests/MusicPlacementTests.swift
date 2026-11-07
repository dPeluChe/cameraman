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

    func testAPieceFitsThePictureNotTheMusicAlreadyThere() {
        let picture = Project.TimelineClip(timelineIn: 0, content: .color(Project.ColorClipRef(hexColor: "#000000", duration: 20)))
        let longMusic = Project.TimelineClip(timelineIn: 0, content: .audio(Project.AudioClipRef(path: "a.m4a", duration: 90)))
        let timeline = Project.Timeline(duration: 90, tracks: [
            Project.TimelineTrack(name: "Card", type: .video, clips: [picture]),
            Project.TimelineTrack(name: "Music", type: .audio, clips: [longMusic]),
        ])
        XCTAssertEqual(MusicSource.fittedDuration(from: 5, in: timeline), 15)
        XCTAssertNil(MusicSource.fittedDuration(from: 25, in: timeline))
        XCTAssertEqual(MusicSource.fittedDuration(from: 0, in: Project.Timeline(duration: 2000, tracks: [])), 2000)
    }

    func testALongVideoIsSplitIntoEqualPiecesWithinTheLimit() {
        XCTAssertEqual(MusicSource.sections(of: 90), [90])
        XCTAssertEqual(MusicSource.sections(of: MusicRenderer.maxDuration), [MusicRenderer.maxDuration])
        let long = MusicSource.sections(of: 1500)
        XCTAssertEqual(long.count, 3)
        XCTAssertEqual(long.reduce(0, +), 1500, accuracy: 0.001)
        XCTAssertTrue(long.allSatisfy { $0 == 500 })
    }

    func testPiecesGoBackToBackOnOneTrackOrNotAtAll() async throws {
        let editor = EditorModel(project: project)
        let first = RenderedMusic(file: URL(fileURLWithPath: "/project/assets/music-00000001.m4a"), seconds: 10)
        let second = RenderedMusic(file: URL(fileURLWithPath: "/project/assets/music-00000002.m4a"), seconds: 10)
        let result = await editor.addMusic([first, second], at: 5)
        XCTAssertNotNil(result.getProject())
        let placed = await clips(editor)
        XCTAssertEqual(placed.map(\.timelineIn), [5, 15])

        let refused = EditorModel(project: project)
        let broken = RenderedMusic(file: URL(fileURLWithPath: "/project/assets/music-00000003.m4a"), seconds: 0)
        let failure = await refused.addMusic([first, broken], at: 0)
        XCTAssertNil(failure.getProject())
        let musicTracks = await refused.projectRef.timeline.tracks.filter { $0.name == MusicSource.trackName }
        XCTAssertTrue(musicTracks.isEmpty, "A refused piece undoes the ones before it, track included")
    }

    func testPiecesAreOnlyGeneratedMusic() {
        let generated = Project.TimelineClip(timelineIn: 0, content: .audio(Project.AudioClipRef(path: music.path, duration: 10)))
        let imported = Project.TimelineClip(timelineIn: 0, content: .audio(Project.AudioClipRef(path: "assets/music-intro.m4a", duration: 10)))
        let timeline = Project.Timeline(duration: 10, tracks: [
            Project.TimelineTrack(name: "Music", type: .audio, clips: [generated]),
            Project.TimelineTrack(name: "Voiceover", type: .audio, clips: [imported]),
        ])
        XCTAssertEqual(timeline.musicPieces.map(\.clip.id), [generated.id])
    }

    func testVolumeAndDuckingAreAudioLevelsAndNewMusicIsNot() async throws {
        let editor = EditorModel(project: project)
        _ = await editor.addMusic(music, at: 0)
        let before = await editor.projectRef
        let clip = try XCTUnwrap(before.timeline.musicPieces.first)

        _ = await editor.updateClip(clipId: clip.clip.id, inTrackId: clip.track.id, volume: 0.6)
        _ = await editor.setTrackDucking(trackId: clip.track.id, level: 0.8)
        let levels = await editor.projectRef
        XCTAssertNotEqual(before, levels)
        XCTAssertEqual(before.ignoringAudioLevels, levels.ignoringAudioLevels)

        let other = RenderedMusic(file: URL(fileURLWithPath: "/project/assets/music-1b2c3d4e.m4a"), seconds: 10)
        _ = await editor.replaceMusic(clipId: clip.clip.id, inTrackId: clip.track.id, with: other)
        let replaced = await editor.projectRef
        XCTAssertNotEqual(before.ignoringAudioLevels, replaced.ignoringAudioLevels)
    }

    func testABadDuckingIsRefused() async {
        let editor = EditorModel(project: project)
        let result = await editor.addMusic(music, at: 0, ducking: 1.5)
        XCTAssertNil(result.getProject())
    }

    func testAPieceCanGoBackToTheOneItReplacedAndReturn() async throws {
        let directory = try temporaryProject()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try piece("0a1b2c3d", seconds: 10, in: directory), second = try piece("1b2c3d4e", seconds: 12, in: directory)
        let editor = EditorModel(project: project)
        _ = await editor.addMusic(first, at: 0)
        let added = await clips(editor)
        let clip = try XCTUnwrap(added.first)
        let current = await editor.projectRef
        let track = try XCTUnwrap(current.timeline.tracks.first { $0.name == MusicSource.trackName })
        var swap = await editor.swapMusicWithPrevious(clipId: clip.id, inTrackId: track.id, in: directory)
        XCTAssertNil(swap.getProject())

        _ = await editor.replaceMusic(clipId: clip.id, inTrackId: track.id, with: second)
        swap = await editor.swapMusicWithPrevious(clipId: clip.id, inTrackId: track.id, in: directory)
        XCTAssertNotNil(swap.getProject())
        var moved = await clips(editor)
        var now = try XCTUnwrap(moved.first)
        XCTAssertEqual(RenderedAssets.renderedPath(of: now, as: .music), first.path)
        XCTAssertEqual(now.duration, 10)
        XCTAssertEqual(now.volume, MusicSource.defaultVolume)

        _ = await editor.swapMusicWithPrevious(clipId: clip.id, inTrackId: track.id, in: directory)
        moved = await clips(editor)
        now = try XCTUnwrap(moved.first)
        XCTAssertEqual(RenderedAssets.renderedPath(of: now, as: .music), second.path)
        XCTAssertEqual(now.duration, 12)
    }

    func testOnlyThePreviousPieceSurvivesCleanup() async throws {
        let directory = try temporaryProject()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pieces = try ["0a1b2c3d", "1b2c3d4e", "2c3d4e5f"].map { try piece($0, seconds: 10, in: directory) }
        let editor = EditorModel(project: project)
        _ = await editor.addMusic(pieces[0], at: 0)
        let added = await clips(editor)
        let clip = try XCTUnwrap(added.first)
        let current = await editor.projectRef
        let track = try XCTUnwrap(current.timeline.tracks.first { $0.name == MusicSource.trackName })
        for next in pieces.dropFirst() { _ = await editor.replaceMusic(clipId: clip.id, inTrackId: track.id, with: next) }

        let final = await editor.projectRef
        RenderedAssets.removeUnused(in: final, directory: directory, now: Date().addingTimeInterval(7200))
        let left = pieces.map { FileManager.default.fileExists(atPath: $0.file.path) }
        XCTAssertEqual(left, [false, true, true])
    }

    private func temporaryProject() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("assets"), withIntermediateDirectories: true)
        return directory
    }

    private func piece(_ name: String, seconds: TimeInterval, in directory: URL) throws -> RenderedMusic {
        let file = directory.appendingPathComponent("assets/music-\(name).m4a")
        try Data().write(to: file)
        try MusicSource(score: .style(.lofi), options: MusicRenderOptions(duration: seconds)).save(for: file)
        return RenderedMusic(file: file, seconds: seconds)
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
