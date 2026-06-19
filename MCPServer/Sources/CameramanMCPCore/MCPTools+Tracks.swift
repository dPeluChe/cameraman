//
//  MCPTools+Tracks.swift
//  cameraman-mcp
//
//  Track-level editing: add/remove tracks, reorder video tracks (z-order) and
//  set track properties (muted / volume / locked) in one tool.
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
        let project = try await mutate(args) { await $0.addTrack(type: type, name: name) }
        return try summary("Added \(typeRaw) track", project)
    }

    func removeTrack(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let project = try await mutate(args) { await $0.removeTrack(trackId: trackId) }
        return try summary("Removed track \(trackId)", project)
    }

    func moveVideoTrack(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let up = try args.bool("up")
        let project = try await mutate(args) { await $0.moveVideoTrack(trackId: trackId, up: up) }
        return try summary("Moved track \(trackId) \(up ? "up" : "down")", project)
    }

    /// Set any of a track's properties (muted / volume / locked) in one call.
    func setTrack(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let muted = args.optBool("muted")
        let volume = args.optNum("volume")
        let locked = args.optBool("locked")
        guard muted != nil || volume != nil || locked != nil else {
            throw MCPToolError("Pass at least one of: muted, volume, locked.")
        }
        let project = try await mutate(args) { editor in
            var result: EditorResult?
            if let muted { result = await editor.setTrackMuted(trackId: trackId, muted: muted) }
            if let volume { result = await editor.setTrackVolume(trackId: trackId, volume: volume) }
            if let locked { result = await editor.setTrackLocked(trackId: trackId, locked: locked) }
            return result ?? .failure(.trackNotFound(trackId.uuidString))
        }
        return try summary("Updated track \(trackId)", project)
    }
}
