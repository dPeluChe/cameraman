//
//  MCPTools+Clips.swift
//  cameraman-mcp
//
//  Symmetric clip editing: reposition (move_clip), retime (update_clip:
//  speed/volume/opacity), trim source in/out (trim_clip), ripple-delete a range
//  (delete_range), and adjustment update/clear. All go through EditorModel so
//  they behave exactly like the GUI's edits.
//

import Foundation
import EngineKit

extension MCPTools {

    // MARK: - Move / reposition

    func moveClip(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let clipId = try args.str("clipId")
        let toTimelineIn = args.optNum("toTimelineIn")
        let toTrackId = args.optUUID("toTrackId")

        let project = try await mutate(args) { editor in
            if let dest = toTrackId, dest != trackId {
                return await editor.moveClip(clipId: clipId, fromTrackId: trackId,
                                             toTrackId: dest, newTimelineIn: toTimelineIn)
            }
            return await editor.updateClip(clipId: clipId, inTrackId: trackId, timelineIn: toTimelineIn)
        }
        return try summary("Moved clip \(clipId)", project)
    }

    // MARK: - Retime / volume / opacity

    func updateClip(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let clipId = try args.str("clipId")
        let speed = args.optNum("speed")
        let volume = args.optNum("volume")
        let opacity = args.optNum("opacity")
        guard speed != nil || volume != nil || opacity != nil else {
            throw MCPToolError("Pass at least one of: speed, volume, opacity.")
        }
        let project = try await mutate(args) { editor in
            await editor.updateClip(clipId: clipId, inTrackId: trackId,
                                    speed: speed, volume: volume, opacity: opacity)
        }
        return try summary("Updated clip \(clipId)", project)
    }

    // MARK: - Trim source window

    func trimClip(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let clipId = try args.str("clipId")
        let sourceIn = args.optNum("sourceIn")
        let sourceOut = args.optNum("sourceOut")
        guard sourceIn != nil || sourceOut != nil else {
            throw MCPToolError("Pass sourceIn and/or sourceOut (seconds).")
        }
        // Read current content, recompute the source window, then apply via updateClip.
        let current = try await loadProject(args)
        guard let track = current.timeline.tracks.first(where: { $0.id == trackId }),
              let clip = track.clips.first(where: { $0.id == clipId }) else {
            throw MCPToolError("Clip \(clipId) not found on track \(trackId)")
        }
        let newContent = Self.trimmedContent(clip.content, sourceIn: sourceIn, sourceOut: sourceOut)

        let project = try await mutate(args) { editor in
            await editor.updateClip(clipId: clipId, inTrackId: trackId, content: newContent)
        }
        return try summary("Trimmed clip \(clipId)", project)
    }

    /// Apply a new source in/out to a clip's content. For video/recording these
    /// are source-relative seconds; for audio, sourceOut sets duration; for
    /// image/color (no source window) sourceOut sets the on-screen duration.
    private static func trimmedContent(_ content: Project.ClipContent,
                                       sourceIn: Double?, sourceOut: Double?) -> Project.ClipContent {
        switch content {
        case .video(var ref):
            if let i = sourceIn { ref.sourceIn = i }
            if let o = sourceOut { ref.sourceOut = o }
            return .video(ref)
        case .recording(var ref):
            if let i = sourceIn { ref.sourceIn = i }
            if let o = sourceOut { ref.sourceOut = o }
            return .recording(ref)
        case .audio(var ref):
            if let i = sourceIn { ref.sourceIn = i }
            if let o = sourceOut { ref.duration = max(0, o - ref.sourceIn) }
            return .audio(ref)
        case .image(var ref):
            if let o = sourceOut { ref.duration = o }
            return .image(ref)
        case .color(var ref):
            if let o = sourceOut { ref.duration = o }
            return .color(ref)
        }
    }

    // MARK: - Ripple delete

    func deleteRange(_ args: [String: Any]) async throws -> String {
        let from = try args.num("from")
        let to = try args.num("to")
        let project = try await mutate(args) { editor in
            await editor.deleteRange(from: from, to: to)
        }
        return try summary("Deleted range \(from)–\(to)s (ripple)", project)
    }

    // MARK: - Adjustments

    func updateAdjustment(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let clipId = try args.str("clipId")
        let adjustmentId = try args.uuid("adjustmentId")

        let current = try await loadProject(args)
        guard let track = current.timeline.tracks.first(where: { $0.id == trackId }),
              let clip = track.clips.first(where: { $0.id == clipId }),
              let existing = (clip.adjustments ?? []).first(where: { $0.id == adjustmentId }) else {
            throw MCPToolError("Adjustment \(adjustmentId) not found on clip \(clipId)")
        }

        let kind = args.optStr("kind").map(Project.AdjustmentKind.init(rawValue:)) ?? existing.kind
        let target = args.optStr("target").flatMap(Project.AdjustmentTarget.init(rawValue:)) ?? existing.target
        let parameters = (args["parameters"] as? [String: Any]) != nil ? args.doubleDict("parameters") : existing.parameters
        let enabled = args.optBool("enabled") ?? existing.enabled
        let start = args.optNum("start") ?? existing.start
        let end = args.optNum("end") ?? existing.end

        let updated = Project.Adjustment(id: adjustmentId, kind: kind, target: target,
                                         parameters: parameters, enabled: enabled, start: start, end: end)
        let project = try await mutate(args) { editor in
            await editor.updateAdjustment(updated, inClipId: clipId, trackId: trackId)
        }
        return try summary("Updated adjustment \(adjustmentId)", project)
    }

    func clearAdjustments(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let clipId = try args.str("clipId")
        let project = try await mutate(args) { editor in
            await editor.clearAdjustments(clipId: clipId, inTrackId: trackId)
        }
        return try summary("Cleared adjustments on clip \(clipId)", project)
    }
}
