//
//  MCPMotionTests.swift
//  CameramanMCPTests
//
//  add_motion end to end against a scratch project library. The library is a process-wide
//  singleton read from CAMERAMAN_PROJECTS_DIR on first use, so the variable is set before any
//  test touches it and every test checks it landed in the scratch directory.
//

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
        XCTAssertTrue(names(MCPTools(supportsMotion: true)).contains("add_motion"))
        let tool = try XCTUnwrap(MCPTools.catalog.first { $0["name"] as? String == "add_motion" })
        XCTAssertEqual((tool["inputSchema"] as? [String: Any])?["required"] as? [String], ["projectId", "at"])
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
        let tools = MCPTools(supportsMotion: true)
        let (id, directory) = try await makeProject(tools)
        let result = try await tools.execute(name: "add_motion", arguments: [
            "projectId": id.uuidString, "at": 1.0, "template": "lower_third", "title": "Ana Ruiz", "subtitle": "CTO",
            "duration": 2.0, "x": 0.0, "y": 0.6, "w": 0.5, "h": 0.3,
        ])
        XCTAssertTrue(result.contains("Added motion"), result)

        let project = try await ProjectLibrary.shared.getProject(projectId: id)
        let track = try XCTUnwrap(project.timeline.tracks.first { $0.name == "Motion" })
        XCTAssertEqual(track.type, .video)
        let clip = try XCTUnwrap(track.clips.first)
        XCTAssertEqual(clip.timelineIn, 1.0)
        XCTAssertEqual(clip.timelineOut, 3.0, accuracy: 0.05)
        XCTAssertEqual(clip.position, Project.MediaPosition(x: 0, y: 0.6, w: 0.5, h: 0.3))
        guard case .video(let ref) = clip.content else { return XCTFail("expected a video clip") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(ref.path).path))
    }

    func testRejectsBadInputWithoutLeavingFiles() async throws {
        let tools = MCPTools(supportsMotion: true)
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
        XCTAssertTrue(MCPTools.motionSize(for: .init(aspect: "16:9", w: 3840, h: 2160)) == (1920, 1080))
        XCTAssertTrue(MCPTools.motionSize(for: .init(aspect: "9:16", w: 1080, h: 1920)) == (1080, 1920))
        let odd = MCPTools.motionSize(for: .init(aspect: "1:1", w: 1001, h: 1001))
        XCTAssertEqual(odd.width % 2, 0)
        XCTAssertEqual(odd.height % 2, 0)
    }
}
