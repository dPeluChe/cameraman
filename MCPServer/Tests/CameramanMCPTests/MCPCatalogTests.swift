//
//  MCPCatalogTests.swift
//  CameramanMCPTests
//
//  Validates the tool catalog is well-formed (every tool advertises a name,
//  description and an object inputSchema with a `required` list).
//

import XCTest
@testable import CameramanMCPCore
import EngineKit

final class MCPCatalogTests: XCTestCase {

    func testCatalogExposesExpectedTools() {
        let names = Set(MCPTools.catalog.compactMap { $0["name"] as? String })
        let expected: Set<String> = [
            "list_projects", "get_project",
            "create_empty_project", "start_recording", "stop_recording",
            "add_clip", "edit_clip", "split_clip", "delete_clip",
            "add_track", "set_track", "move_video_track",
            "add_overlay", "update_overlay", "delete_overlay",
            "add_adjustment", "update_adjustment", "remove_adjustment",
            "update_project", "get_job_status"
        ]
        XCTAssertTrue(expected.isSubset(of: names), "Missing tools: \(expected.subtracting(names))")
    }

    /// Folded into other tools; they must not creep back as duplicates.
    func testConsolidatedToolsAreGone() {
        let names = Set(MCPTools.catalog.compactMap { $0["name"] as? String })
        let removed: Set<String> = ["search_projects", "rename_project", "set_tags", "list_overlays",
                                    "list_adjustments", "list_jobs", "set_clip_audio_muted"]
        XCTAssertTrue(names.isDisjoint(with: removed), "Duplicates back: \(names.intersection(removed))")
    }

    func testToolNamesAreUnique() {
        let names = MCPTools.catalog.compactMap { $0["name"] as? String }
        XCTAssertEqual(names.count, Set(names).count)
    }

    /// Catalog and dispatcher drifting apart is how dead or unreachable tools appear.
    /// Reads the dispatch switch from source: executing tools here would hit the real
    /// project library (create_empty_project, start_recording).
    func testCatalogMatchesDispatchSwitch() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CameramanMCPCore/MCPTools.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let start = try XCTUnwrap(text.range(of: "func execute(name:"))
        let switchBody = String(text[start.upperBound...])
        let regex = try NSRegularExpression(pattern: #"case "([a-z_]+)":"#)
        var dispatched = Set<String>()
        for match in regex.matches(in: switchBody, range: NSRange(switchBody.startIndex..., in: switchBody)) {
            if let range = Range(match.range(at: 1), in: switchBody) { dispatched.insert(String(switchBody[range])) }
        }
        let cataloged = Set(MCPTools.catalog.compactMap { $0["name"] as? String })
        XCTAssertTrue(cataloged.subtracting(dispatched).isEmpty, "in catalog, not dispatched: \(cataloged.subtracting(dispatched))")
        XCTAssertTrue(dispatched.subtracting(cataloged).isEmpty, "dispatched, not in catalog: \(dispatched.subtracting(cataloged))")
    }

    func testAnnotationsMarkReadOnlyAndDestructive() throws {
        func annotations(_ name: String) throws -> [String: Bool] {
            let tool = try XCTUnwrap(MCPTools.catalog.first { $0["name"] as? String == name })
            return try XCTUnwrap(tool["annotations"] as? [String: Bool])
        }
        XCTAssertEqual(try annotations("get_project")["readOnlyHint"], true)
        XCTAssertEqual(try annotations("delete_project")["destructiveHint"], true)
        XCTAssertNil(try annotations("get_project")["destructiveHint"])
        XCTAssertNil(try annotations("add_clip")["readOnlyHint"])
        XCTAssertEqual(try annotations("add_clip")["destructiveHint"], false) // spec default is true
    }

    func testEveryToolHasObjectSchema() throws {
        for tool in MCPTools.catalog {
            let name = tool["name"] as? String
            XCTAssertNotNil(name)
            XCTAssertNotNil(tool["description"] as? String, "\(name ?? "?") missing description")
            let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any], "\(name ?? "?") missing inputSchema")
            XCTAssertEqual(schema["type"] as? String, "object")
            XCTAssertNotNil(schema["properties"] as? [String: Any])
            XCTAssertNotNil(schema["required"] as? [String])
        }
    }

    func testCatalogIsJSONSerializable() throws {
        // The catalog is sent verbatim over JSON-RPC, so it must serialize.
        let data = try JSONSerialization.data(withJSONObject: ["tools": MCPTools.catalog])
        XCTAssertGreaterThan(data.count, 0)
    }

    /// edit_clip and set_track chain several edits; a later success must not mask an earlier failure.
    func testRunStepsStopsAtFirstFailure() async {
        let tools = MCPTools()
        var laterRan = false
        let result = await tools.runSteps([
            { .failure(.trackNotFound("first")) },
            { laterRan = true; return .failure(.trackNotFound("second")) },
        ])
        XCTAssertEqual(result, .failure(.trackNotFound("first")))
        XCTAssertFalse(laterRan)
        let none = await tools.runSteps([])
        XCTAssertNil(none)
    }

    /// The host freezes its editor on "will change" and reloads on "changed"; the order is the contract.
    func testEditedAnnouncesBeforeAndAfterTheWrite() async throws {
        let log = Log()
        let tools = MCPTools(onProjectChanged: { _ in log.add("changed") },
                             onProjectWillChange: { _ in log.add("will") })
        let id = UUID().uuidString
        _ = try await tools.edited(["projectId": id]) { log.add("write"); return "ok" }
        XCTAssertEqual(log.events, ["will", "write", "changed"])

        // A failing write announces the start but not a change.
        let failing = Log()
        let failTools = MCPTools(onProjectChanged: { _ in failing.add("changed") },
                                 onProjectWillChange: { _ in failing.add("will") })
        _ = try? await failTools.edited(["projectId": id]) { throw MCPToolError("boom") }
        XCTAssertEqual(failing.events, ["will"])
    }

    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ e: String) { lock.lock(); items.append(e); lock.unlock() }
        var events: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }

    func testGetProjectOmitsSubtitlesButReportsTheCount() {
        let project: [String: Any] = ["name": "x", "subtitles": [["t": 1], ["t": 2], ["t": 3]], "overlays": []]
        let trimmed = MCPTools.trimmedProject(project, includeSubtitles: false)
        XCTAssertNil(trimmed["subtitles"])
        XCTAssertEqual(trimmed["subtitleCount"] as? Int, 3)
        XCTAssertNotNil(trimmed["overlays"])

        let full = MCPTools.trimmedProject(project, includeSubtitles: true)
        XCTAssertEqual((full["subtitles"] as? [Any])?.count, 3)
        XCTAssertNil(full["subtitleCount"])
    }

    /// The export preset enum comes from the same table the exporter uses, so a new preset cannot be
    /// valid in the code but missing from the schema.
    func testExportPresetEnumMatchesTheExporterTable() throws {
        let export = try XCTUnwrap(MCPTools.catalog.first { $0["name"] as? String == "export_project" })
        let props = try XCTUnwrap((export["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])
        let listed = try XCTUnwrap((props["preset"] as? [String: Any])?["enum"] as? [String])
        XCTAssertEqual(Set(listed), Set(MCPTools.presetIds))
        XCTAssertTrue(listed.contains("square_1080_h264") && listed.contains("portrait_4x5_1080_h264"))
    }
}
