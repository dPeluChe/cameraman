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
        let audioMuted = args.optBool("audioMuted")
        let position = try Self.placement(args)
        let cameraArg = args["camera"] as? [String: Any]
        let resetCamera = args.optBool("resetCamera") == true
        let crossTrack = toTrackId != nil && toTrackId != trackId
        let wantsUpdate = crossTrack || timelineIn != nil || speed != nil || volume != nil
            || opacity != nil || sourceIn != nil || sourceOut != nil || position != nil
            || cameraArg != nil || resetCamera
        guard wantsUpdate || audioMuted != nil else {
            throw MCPToolError("Pass at least one change: timelineIn, toTrackId, speed, volume, opacity, x/y/w/h, camera, resetCamera, sourceIn, sourceOut, audioMuted.")
        }

        if position != nil {
            guard case .video = try await resolveClip(args).clip.content else {
                throw MCPToolError("x, y, w and h apply to video clips only.")
            }
        }

        // Trim recomputes the clip's content from its current source window.
        var newContent: Project.ClipContent?
        if sourceIn != nil || sourceOut != nil {
            let clip = try await resolveClip(args).clip
            newContent = Self.trimmedContent(clip.content, sourceIn: sourceIn, sourceOut: sourceOut)
        }
        if cameraArg != nil || resetCamera {
            let (project, _, clip) = try await resolveClip(args)
            guard case .recording(var ref) = newContent ?? clip.content else {
                throw MCPToolError("camera applies to recording clips (screen + camera). Place other video with x/y/w/h.")
            }
            guard let layoutCamera = project.canvas.layout.camera else {
                throw MCPToolError("The layout is fullscreen, so the camera is hidden. Call set_canvas_layout with type pip first.")
            }
            ref.cameraPosition = cameraArg.map { Self.cameraPosition(from: $0, keeping: ref.cameraPosition ?? layoutCamera) }
            newContent = .recording(ref)
        }

        let project = try await mutate(args) { editor in
            let track = (crossTrack ? toTrackId : nil) ?? trackId
            var steps: [() async -> EditorResult] = []
            if crossTrack, let dest = toTrackId {
                steps.append { await editor.moveClip(clipId: clipId, fromTrackId: trackId, toTrackId: dest, newTimelineIn: timelineIn) }
            }
            if wantsUpdate {
                steps.append { await editor.updateClip(clipId: clipId, inTrackId: track, timelineIn: crossTrack ? nil : timelineIn,
                                                       speed: speed, volume: volume, opacity: opacity,
                                                       position: position, content: newContent) }
            }
            if let muted = audioMuted {
                steps.append { await editor.setClipAudioMuted(clipId: clipId, inTrackId: track, muted: muted) }
            }
            return await self.runSteps(steps) ?? .failure(.clipNotFound(clipId: clipId, trackId: trackId.uuidString))
        }
        return try summary("Edited clip \(clipId)", project)
    }

    /// Canvas placement from x, y, w, h, which only make sense together.
    static func placement(_ args: [String: Any]) throws -> Project.MediaPosition? {
        let values = ["x", "y", "w", "h"].map { args.optNum($0) }
        guard values.contains(where: { $0 != nil }) else { return nil }
        guard let x = values[0], let y = values[1], let w = values[2], let h = values[3] else {
            throw MCPToolError("Pass x, y, w and h together (fractions of the canvas), or none of them.")
        }
        return Project.MediaPosition(x: x, y: y, w: w, h: h)
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

        if let kindRaw = args.optStr("kind"), !Self.knownAdjustmentKinds.contains(kindRaw) {
            throw MCPToolError("Unknown adjustment kind '\(kindRaw)'. Valid kinds: \(Self.knownAdjustmentKinds.sorted().joined(separator: ", "))")
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
