//
//  MCPMotionTests.swift
//  CameramanMCPTests
//
//  add_motion end to end against a scratch project library. The library is a process-wide
//  singleton read from CAMERAMAN_PROJECTS_DIR on first use, so the variable is set before any
//  test touches it and every test checks it landed in the scratch directory.
//

import AVFoundation
import ImageIO
import XCTest
@testable import CameramanMCPCore
import EngineKit

final class MCPMotionTests: XCTestCase {
    private static let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("mcp-motion-\(UUID().uuidString)", isDirectory: true)

    override class func setUp() {
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        setenv("CAMERAMAN_PROJECTS_DIR", scratch.path, 1)
    }

    override class func tearDown() { try? FileManager.default.removeItem(at: scratch) }

    private func makeProject(_ tools: MCPTools) async throws -> (id: UUID, directory: URL) {
        let text = try await tools.execute(name: "create_empty_project", arguments: ["name": "motion"])
        let id = try XCTUnwrap(UUID(uuidString: String(text.split(separator: " ").last ?? "")))
        let directory = try await ProjectLibrary.shared.getProjectDirectory(projectId: id)
        guard directory.path.hasPrefix(Self.scratch.resolvingSymlinksInPath().path) || directory.path.hasPrefix(Self.scratch.path) else {
            try? await ProjectLibrary.shared.deleteProject(projectId: id)
            XCTFail("the library is not the scratch one: \(directory.path)")
            throw CancellationError()
        }
        return (id, directory)
    }

    func testSideBySideStoresTheSpellingTheEngineReadsAndTakesASide() async throws {
        let tools = MCPTools()
        let (id, _) = try await makeProject(tools)

        _ = try await tools.execute(name: "set_canvas_layout", arguments: [
            "projectId": id.uuidString, "type": "side_by_side", "cameraSide": "left"
        ])

        let layout = try await ProjectLibrary.shared.getProject(projectId: id).canvas.layout
        XCTAssertTrue(layout.isSideBySide)
        XCTAssertTrue(layout.isCameraOnLeft)
        XCTAssertNoThrow(try CanvasLayout.validateLayout(layout, hasCamera: true))
    }

    func testAddMotionIsAdvertisedOnlyWhereItCanRun() throws {
        let names = { (tools: MCPTools) in Set(tools.listedCatalog.compactMap { $0["name"] as? String }) }
        XCTAssertFalse(names(MCPTools()).contains("add_motion"), "the CLI cannot render, so it must not offer the tool")
        XCTAssertTrue(names(MCPTools(supportsRendering: true)).contains("add_motion"))
        let tool = try XCTUnwrap(MCPTools.catalog.first { $0["name"] as? String == "add_motion" })
        XCTAssertEqual((tool["inputSchema"] as? [String: Any])?["required"] as? [String], ["projectId", "at"])
    }

    func testPlacementNeedsAllFourValues() throws {
        XCTAssertNil(try MCPTools.placement([:]))
        XCTAssertEqual(try MCPTools.placement(["x": -0.2, "y": 0, "w": 1, "h": 1])?.x, -0.2)
        XCTAssertThrowsError(try MCPTools.placement(["x": 0.1]))
    }

    func testStandaloneServerExplainsItCannotRender() async {
        let tools = MCPTools()
        do {
            _ = try await tools.execute(name: "add_motion", arguments: ["projectId": UUID().uuidString, "at": 0, "template": "title", "title": "x"])
            XCTFail("the CLI has no window server")
        } catch let error as MCPToolError {
            XCTAssertTrue(error.message.contains("inside the Cameraman app"), error.message)
        } catch { XCTFail("\(error)") }
    }

    func testAddsATemplateAsAClipOnItsOwnTrack() async throws {
        let tools = MCPTools(supportsRendering: true)
        let (id, directory) = try await makeProject(tools)
        let result = try await tools.execute(name: "add_motion", arguments: [
            "projectId": id.uuidString, "at": 1.0, "template": "lower_third", "title": "Ana Ruiz", "subtitle": "CTO",
            "duration": 2.0, "x": 0.0, "y": 0.6, "w": 0.5, "h": 0.3,
        ])
        XCTAssertTrue(result.contains("Added motion"), result)

        let project = try await ProjectLibrary.shared.getProject(projectId: id)
        let track = try XCTUnwrap(project.timeline.tracks.first { $0.name == "Motion" })
        XCTAssertEqual(track.type, .video)
        XCTAssertEqual(track.belowCamera, true, "a card must not cover the presenter")
        let clip = try XCTUnwrap(track.clips.first)
        XCTAssertEqual(clip.timelineIn, 1.0)
        XCTAssertEqual(clip.timelineOut, 3.0, accuracy: 0.05)
        XCTAssertEqual(clip.position, Project.MediaPosition(x: 0, y: 0.6, w: 0.5, h: 0.3))
        guard case .video(let ref) = clip.content else { return XCTFail("expected a video clip") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(ref.path).path))
    }

    func testMotionsShareATrackUnlessTheyOverlap() async throws {
        let tools = MCPTools(supportsRendering: true)
        let (id, _) = try await makeProject(tools)
        func add(at: Double) async throws -> [String: Any] {
            let reply = try await tools.execute(name: "add_motion", arguments: [
                "projectId": id.uuidString, "at": at, "template": "title", "title": "Hola", "duration": 2.0,
            ])
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        }
        let first = try await add(at: 0)
        let second = try await add(at: 3)
        let third = try await add(at: 1)
        XCTAssertEqual(first["trackId"] as? String, second["trackId"] as? String, "no overlap, same row")
        XCTAssertNotEqual(first["trackId"] as? String, third["trackId"] as? String, "overlap, new row")
        XCTAssertNotNil(third["clipId"] as? String)

        let area = try XCTUnwrap(first["visibleArea"] as? [String: Double])
        XCTAssertLessThan(try XCTUnwrap(area["w"]), 1, "a title does not fill the canvas")
        XCTAssertGreaterThan(try XCTUnwrap(area["w"]), 0)
    }

    func testPreviewFrameReturnsAnImageOfTheComposite() async throws {
        let tools = MCPTools(supportsRendering: true)
        let (id, _) = try await makeProject(tools)
        _ = try await tools.execute(name: "add_motion", arguments: [
            "projectId": id.uuidString, "at": 0, "template": "title", "title": "Hola", "duration": 2.0,
        ])
        let content = try await tools.content(name: "preview_frame", arguments: [
            "projectId": id.uuidString, "at": 1.0, "maxWidth": 640,
        ])
        XCTAssertEqual(content.first?["type"] as? String, "image")
        XCTAssertEqual(content.first?["mimeType"] as? String, "image/jpeg")
        let data = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(content.first?["data"] as? String)))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThanOrEqual(image.width, 640)

        do {
            _ = try await tools.content(name: "preview_frame", arguments: ["projectId": id.uuidString, "at": 99.0])
            XCTFail("past the end")
        } catch is MCPToolError {}
    }

    func testUpdateKeepsTimeAndPlacementAndChangesOnlyWhatWasPassed() async throws {
        let tools = MCPTools(supportsRendering: true)
        let (id, directory) = try await makeProject(tools)
        let reply = try await tools.execute(name: "add_motion", arguments: [
            "projectId": id.uuidString, "at": 1.0, "template": "lower_third", "title": "Ana", "subtitle": "CTO",
            "duration": 2.0, "x": 0.0, "y": 0.6, "w": 0.5, "h": 0.3,
        ])
        let added = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        let target: [String: Any] = ["projectId": id.uuidString, "trackId": try XCTUnwrap(added["trackId"]), "clipId": try XCTUnwrap(added["clipId"])]

        _ = try await tools.execute(name: "update_motion", arguments: target.merging(["title": "Ana Ruiz", "duration": 3.0]) { $1 })

        let project = try await ProjectLibrary.shared.getProject(projectId: id)
        let clip = try XCTUnwrap(project.timeline.tracks.first { $0.name == "Motion" }?.clips.first)
        XCTAssertEqual(clip.timelineIn, 1.0)
        XCTAssertEqual(clip.timelineOut, 4.0, accuracy: 0.05)
        XCTAssertEqual(clip.position, Project.MediaPosition(x: 0, y: 0.6, w: 0.5, h: 0.3))
        guard case .video(let ref) = clip.content else { return XCTFail("expected a video clip") }
        let source = try XCTUnwrap(MotionSource.load(for: directory.appendingPathComponent(ref.path)))
        XCTAssertEqual(source.title, "Ana Ruiz")
        XCTAssertEqual(source.subtitle, "CTO", "what was not passed is kept")
        XCTAssertEqual(source.template, "lower_third")
    }

    func testUpdateCannotRunIntoTheNextClip() async throws {
        let tools = MCPTools(supportsRendering: true)
        let (id, _) = try await makeProject(tools)
        func add(at: Double) async throws -> [String: Any] {
            let reply = try await tools.execute(name: "add_motion", arguments: [
                "projectId": id.uuidString, "at": at, "template": "title", "title": "Hola", "duration": 2.0,
            ])
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        }
        let first = try await add(at: 0)
        _ = try await add(at: 2.5)
        do {
            _ = try await tools.execute(name: "update_motion", arguments: [
                "projectId": id.uuidString, "trackId": try XCTUnwrap(first["trackId"]), "clipId": try XCTUnwrap(first["clipId"]), "duration": 4.0,
            ])
            XCTFail("it would overlap")
        } catch let error as MCPToolError {
            XCTAssertTrue(error.message.contains("next clip"), error.message)
        }
    }

    func testUnusedMotionsGoOnlyWhenOldEnough() async throws {
        let tools = MCPTools(supportsRendering: true)
        let (id, directory) = try await makeProject(tools)
        _ = try await tools.execute(name: "add_motion", arguments: [
            "projectId": id.uuidString, "at": 0, "template": "title", "title": "Hola", "duration": 2.0,
        ])
        let assets = directory.appendingPathComponent("assets")
        let unused = assets.appendingPathComponent("motion-0a1b2c3d.mov")
        try Data().write(to: unused)
        try Data().write(to: MotionSource.sidecar(of: unused))
        try Data().write(to: assets.appendingPathComponent("motion-intro.mov"))
        let project = try await ProjectLibrary.shared.getProject(projectId: id)

        XCTAssertEqual(RenderedAssets.removeUnused(in: project, directory: directory), 0, "it may still be rendering")
        XCTAssertEqual(RenderedAssets.removeUnused(in: project, directory: directory, now: Date().addingTimeInterval(7200)), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: unused.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: MotionSource.sidecar(of: unused).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: assets.appendingPathComponent("motion-intro.mov").path), "an import, not a render")
    }

    func testRejectsBadInputWithoutLeavingFiles() async throws {
        let tools = MCPTools(supportsRendering: true)
        let (id, directory) = try await makeProject(tools)
        let bad: [[String: Any]] = [
            ["template": "confetti"],
            ["template": "bar_chart", "labels": ["a"], "values": [1, 2]],
            ["template": "title", "title": "x", "x": 0.1, "y": 0.1, "w": 0.5],
            ["template": "title", "title": "x", "x": 0.1],
            ["template": "title", "title": "x", "html": "<html></html>"],
            ["html": "<html><body>static</body></html>"],
        ]
        for extra in bad {
            var args: [String: Any] = ["projectId": id.uuidString, "at": 0.0]
            args.merge(extra) { $1 }
            do {
                _ = try await tools.execute(name: "add_motion", arguments: args)
                XCTFail("should reject \(extra)")
            } catch {
                let message = (error as? MCPToolError)?.message ?? error.localizedDescription
                XCTAssertFalse(message.isEmpty, "rejection of \(extra) must explain itself")
            }
        }
        let assets = (try? FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("assets").path)) ?? []
        XCTAssertTrue(assets.isEmpty, "failed renders must not leave files: \(assets)")
        let project = try await ProjectLibrary.shared.getProject(projectId: id)
        XCTAssertTrue(project.timeline.tracks.allSatisfy { $0.name != "Motion" })
    }

    func testMotionSizeIsCappedAndEven() {
        XCTAssertTrue(MCPTools.motionSize(for: .init(aspect: "16:9", w: 3840, h: 2160)) == (2560, 1440))
        XCTAssertTrue(MCPTools.motionSize(for: .init(aspect: "2586:1080", w: 2586, h: 1080)) == (2560, 1068))
        XCTAssertTrue(MCPTools.motionSize(for: .init(aspect: "9:16", w: 1080, h: 1920)) == (1080, 1920))
        let odd = MCPTools.motionSize(for: .init(aspect: "1:1", w: 1001, h: 1001))
        XCTAssertEqual(odd.width % 2, 0)
        XCTAssertEqual(odd.height % 2, 0)
    }

    // MARK: - Music

    func testMusicTracksAcrossClipsAndUpdatesInPlace() async throws {
        let tools = MCPTools(supportsRendering: true)
        let (id, directory) = try await makeProject(tools)
        let args: [String: Any] = ["projectId": id.uuidString, "style": "ambient", "duration": 3.0]
        _ = try await tools.execute(name: "add_music", arguments: args.merging(["at": 0, "volume": 0.3]) { $1 })
        _ = try await tools.execute(name: "add_music", arguments: args.merging(["at": 5]) { $1 })

        var project = try await ProjectLibrary.shared.getProject(projectId: id)
        let tracks = project.timeline.tracks.filter { $0.name == "Music" }
        XCTAssertEqual(tracks.count, 1, "clips that fit share the Music track")
        let track = try XCTUnwrap(tracks.first)
        XCTAssertEqual(track.type, .audio)
        XCTAssertEqual(track.clips.count, 2)
        let first = try XCTUnwrap(track.clips.first { $0.timelineIn == 0 })
        XCTAssertEqual(first.volume, 0.3)
        guard case .audio(let before) = first.content else { return XCTFail("audio clip") }

        _ = try await tools.execute(name: "update_music", arguments: [
            "projectId": id.uuidString, "trackId": track.id.uuidString, "clipId": first.id, "seed": 9, "duration": 4.0,
        ])
        project = try await ProjectLibrary.shared.getProject(projectId: id)
        let updated = try XCTUnwrap(project.timeline.tracks.first { $0.id == track.id }?.clips.first { $0.id == first.id })
        XCTAssertEqual(updated.volume, 0.3, "keeps its level")
        XCTAssertEqual(updated.duration, 4, accuracy: 0.01)
        guard case .audio(let after) = updated.content else { return XCTFail("audio clip") }
        XCTAssertNotEqual(after.path, before.path)
        let source = try XCTUnwrap(MusicSource.load(for: directory.appendingPathComponent(after.path)))
        XCTAssertEqual(source.score, .style(.ambient))
        XCTAssertEqual(source.options.seed, 9)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(before.path).path), "kept for undo")
    }

    func testMusicDefaultsToTheRestOfTheTimelineAndNeedsAScore() async throws {
        let tools = MCPTools(supportsRendering: true)
        let (id, _) = try await makeProject(tools)
        _ = try await tools.execute(name: "add_motion", arguments: [
            "projectId": id.uuidString, "at": 0, "template": "title", "title": "x", "duration": 3.0,
        ])
        do {
            _ = try await tools.execute(name: "add_music", arguments: ["projectId": id.uuidString])
            XCTFail("no score")
        } catch let error as MCPToolError { XCTAssertTrue(error.message.contains("style"), error.message) }
        _ = try await tools.execute(name: "add_music", arguments: ["projectId": id.uuidString, "style": "lofi", "at": 1])
        let project = try await ProjectLibrary.shared.getProject(projectId: id)
        let clip = try XCTUnwrap(project.timeline.tracks.first { $0.name == "Music" }?.clips.first)
        XCTAssertEqual(clip.duration, 2, accuracy: 0.05)
    }

    func testANewMusicTrackDucksAndAVolumeTheEditorRefusesIsCaught() async throws {
        let tools = MCPTools(supportsRendering: true)
        let (id, _) = try await makeProject(tools)
        do {
            _ = try await tools.execute(name: "add_music", arguments: ["projectId": id.uuidString, "style": "ambient", "duration": 2.0, "volume": 1.5])
            XCTFail("over 1")
        } catch let error as MCPToolError { XCTAssertTrue(error.message.contains("volume"), error.message) }

        let reply = try await tools.execute(name: "add_music", arguments: ["projectId": id.uuidString, "style": "ambient", "duration": 2.0])
        let added = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        XCTAssertEqual(added["speechDucking"] as? Bool, false, "no transcript yet")
        var project = try await ProjectLibrary.shared.getProject(projectId: id)
        let track = try XCTUnwrap(project.timeline.tracks.first { $0.name == "Music" })
        XCTAssertEqual(track.duckingLevel, 0.5)

        _ = try await tools.execute(name: "set_track", arguments: ["projectId": id.uuidString, "trackId": track.id.uuidString, "ducking": 1])
        project = try await ProjectLibrary.shared.getProject(projectId: id)
        XCTAssertNil(project.timeline.tracks.first { $0.id == track.id }?.duckingLevel, "1 turns it off")
    }

    func testAnExportWithNoMuteStateKeepsTheMusicVolume() async throws {
        let tools = MCPTools(supportsRendering: true)
        let (id, directory) = try await makeProject(tools)
        _ = try await tools.execute(name: "add_motion", arguments: ["projectId": id.uuidString, "at": 0.0, "template": "title", "title": "x", "duration": 3.0])
        _ = try await tools.execute(name: "add_music", arguments: ["projectId": id.uuidString, "style": "lofi", "duration": 3.0, "volume": 0.1, "seed": 3])
        let reply = try await tools.execute(name: "export_project", arguments: ["projectId": id.uuidString, "filename": "mix.mp4"])
        let job = try XCTUnwrap((try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])?["jobId"] as? String)
        for _ in 0..<120 {
            let status = try await tools.execute(name: "get_job_status", arguments: ["jobId": job])
            if status.contains("\"success\"") { break }
            XCTAssertFalse(status.contains("\"failed\""), status)
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        let assets = directory.appendingPathComponent("assets")
        let music = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil).first { $0.pathExtension == "m4a" })
        let source = try audioPeak(of: music)
        let exported = try audioPeak(of: directory.appendingPathComponent("renders/mix.mp4"))
        XCTAssertGreaterThan(exported, 0)
        XCTAssertEqual(exported / source, 0.1, accuracy: 0.03, "the mix is what applies the clip volume")
    }

    private func audioPeak(of url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return UnsafeBufferPointer(start: buffer.floatChannelData?[0], count: Int(buffer.frameLength)).reduce(0) { max($0, abs($1)) }
    }

    func testUnusedMusicGoesLikeUnusedMotions() async throws {
        let tools = MCPTools(supportsRendering: true)
        let (id, directory) = try await makeProject(tools)
        _ = try await tools.execute(name: "add_music", arguments: ["projectId": id.uuidString, "style": "tech", "duration": 2.0])
        let assets = directory.appendingPathComponent("assets")
        let unused = assets.appendingPathComponent("music-0a1b2c3d.m4a")
        try Data().write(to: unused)
        let project = try await ProjectLibrary.shared.getProject(projectId: id)
        XCTAssertEqual(RenderedAssets.removeUnused(in: project, directory: directory, now: Date().addingTimeInterval(7200)), 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: assets.path).filter { $0.hasSuffix(".m4a") }.count, 1, "the used one stays")
    }
}
