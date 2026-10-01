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
}
