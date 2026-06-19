//
//  MCPTools+Clips.swift
//  cameraman-mcp
//
//  Clip lifecycle on a track: add_clip (image/video/audio/color in one tool),
//  edit_clip (reposition / cross-track move / retime / trim in one tool),
//  delete_range (ripple), and adjustment update/clear. All go through EditorModel
//  so they behave exactly like the GUI's edits.
//

import Foundation
import EngineKit

extension MCPTools {

    // MARK: - Add (one tool, typed)

    func addClip(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let type = try args.str("type")
        let at = try args.num("at")

        switch type {
        case "image":
            let path = try await stageAsset(try args.str("path"), projectId: projectId)
            let duration = args.optNum("duration") ?? 5.0
            let project = try await mutate(args) { await $0.addImageClip(path: path, duration: duration, at: at) }
            return try summary("Added image clip (\(path)) at \(at)s", project)
        case "video":
            let path = try await stageAsset(try args.str("path"), projectId: projectId)
            let duration = try args.num("duration")
            let project = try await mutate(args) { await $0.importVideoClip(path: path, duration: duration, at: at) }
            return try summary("Added video clip (\(path)) at \(at)s", project)
        case "audio":
            let path = try await stageAsset(try args.str("path"), projectId: projectId)
            let duration = try args.num("duration")
            let sourceIn = args.optNum("sourceIn") ?? 0
            let project = try await mutate(args) { await $0.addAudioClip(path: path, duration: duration, at: at, sourceIn: sourceIn) }
            return try summary("Added audio clip at \(at)s", project)
        case "color":
            let duration = args.optNum("duration") ?? 3.0
            let hexColor = args.optStr("hexColor") ?? "#000000"
            let project = try await mutate(args) { await $0.addColorClip(hexColor: hexColor, duration: duration, at: at) }
            return try summary("Added color clip at \(at)s", project)
        default:
            throw MCPToolError("Unknown clip type '\(type)'. Use: image, video, audio, color.")
        }
    }

    // MARK: - Edit (move / retime / trim in one tool)

    func editClip(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let clipId = try args.str("clipId")
        let toTrackId = args.optUUID("toTrackId")
        let timelineIn = args.optNum("timelineIn")
        let speed = args.optNum("speed")
        let volume = args.optNum("volume")
        let opacity = args.optNum("opacity")
        let sourceIn = args.optNum("sourceIn")
        let sourceOut = args.optNum("sourceOut")
        let crossTrack = toTrackId != nil && toTrackId != trackId
        guard crossTrack || timelineIn != nil || speed != nil || volume != nil
                || opacity != nil || sourceIn != nil || sourceOut != nil else {
            throw MCPToolError("Pass at least one change: timelineIn, toTrackId, speed, volume, opacity, sourceIn, sourceOut.")
        }

        // Trim recomputes the clip's content from its current source window.
        var newContent: Project.ClipContent?
        if sourceIn != nil || sourceOut != nil {
            let clip = try await resolveClip(args).clip
            newContent = Self.trimmedContent(clip.content, sourceIn: sourceIn, sourceOut: sourceOut)
        }

        let project = try await mutate(args) { editor in
            if crossTrack, let dest = toTrackId {
                _ = await editor.moveClip(clipId: clipId, fromTrackId: trackId, toTrackId: dest, newTimelineIn: timelineIn)
                return await editor.updateClip(clipId: clipId, inTrackId: dest,
                                               speed: speed, volume: volume, opacity: opacity, content: newContent)
            }
            return await editor.updateClip(clipId: clipId, inTrackId: trackId, timelineIn: timelineIn,
                                           speed: speed, volume: volume, opacity: opacity, content: newContent)
        }
        return try summary("Edited clip \(clipId)", project)
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
        let project = try await mutate(args) { await $0.deleteRange(from: from, to: to) }
        return try summary("Deleted range \(from)–\(to)s (ripple)", project)
    }

    // MARK: - Adjustments

    func updateAdjustment(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let clipId = try args.str("clipId")
        let adjustmentId = try args.uuid("adjustmentId")

        let clip = try await resolveClip(args).clip
        guard let existing = (clip.adjustments ?? []).first(where: { $0.id == adjustmentId }) else {
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
        let project = try await mutate(args) { await $0.updateAdjustment(updated, inClipId: clipId, trackId: trackId) }
        return try summary("Updated adjustment \(adjustmentId)", project)
    }

    func clearAdjustments(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let clipId = try args.str("clipId")
        let project = try await mutate(args) { await $0.clearAdjustments(clipId: clipId, inTrackId: trackId) }
        return try summary("Cleared adjustments on clip \(clipId)", project)
    }
}
