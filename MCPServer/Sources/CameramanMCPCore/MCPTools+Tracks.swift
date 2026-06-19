//
//  MCPTools+Tracks.swift
//  cameraman-mcp
//
//  Track-level editing: add/remove tracks, reorder video tracks (z-order) and
//  lock/unlock a track. (Mute/volume already live in MCPTools.swift.)
//

import Foundation
import EngineKit

extension MCPTools {

    func addTrack(_ args: [String: Any]) async throws -> String {
        let typeRaw = try args.str("type")
        guard let type = Project.TrackType(rawValue: typeRaw) else {
            throw MCPToolError("Unknown track type '\(typeRaw)'. Use: primary, video, audio.")
        }
        let name = args.optStr("name") ?? ""
        let project = try await mutate(args) { editor in
            await editor.addTrack(type: type, name: name)
        }
        return try summary("Added \(typeRaw) track", project)
    }

    func removeTrack(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let project = try await mutate(args) { editor in
            await editor.removeTrack(trackId: trackId)
        }
        return try summary("Removed track \(trackId)", project)
    }

    func moveVideoTrack(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let up = try args.bool("up")
        let project = try await mutate(args) { editor in
            await editor.moveVideoTrack(trackId: trackId, up: up)
        }
        return try summary("Moved track \(trackId) \(up ? "up" : "down")", project)
    }

    func setTrackLocked(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let locked = try args.bool("locked")
        let project = try await mutate(args) { editor in
            await editor.setTrackLocked(trackId: trackId, locked: locked)
        }
        return try summary("Track \(trackId) locked=\(locked)", project)
    }
}
