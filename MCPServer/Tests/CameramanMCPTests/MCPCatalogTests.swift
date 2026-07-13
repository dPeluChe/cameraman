//
//  MCPCatalogTests.swift
//  CameramanMCPTests
//
//  Validates the tool catalog is well-formed (every tool advertises a name,
//  description and an object inputSchema with a `required` list).
//

import XCTest
@testable import CameramanMCPCore

final class MCPCatalogTests: XCTestCase {

    func testCatalogExposesExpectedTools() {
        let names = Set(MCPTools.catalog.compactMap { $0["name"] as? String })
        let expected: Set<String> = [
            "list_projects", "get_project",
            "create_empty_project", "start_recording", "stop_recording",
            "add_clip", "edit_clip", "split_clip", "delete_clip",
            "add_track", "set_track", "move_video_track", "set_clip_audio_muted",
            "add_overlay", "update_overlay", "delete_overlay",
            "add_adjustment", "update_adjustment", "remove_adjustment", "list_adjustments"
        ]
        XCTAssertTrue(expected.isSubset(of: names), "Missing tools: \(expected.subtracting(names))")
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
}
