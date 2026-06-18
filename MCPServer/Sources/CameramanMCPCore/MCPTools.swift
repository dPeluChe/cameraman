//
//  MCPTools.swift
//  cameraman-mcp
//
//  Tool catalog and dispatch. Every editing tool follows the same shape:
//  load the project via ProjectLibrary, run the operation through EditorModel
//  (the app's own non-destructive editing logic), then persist. This guarantees
//  the MCP edits and the GUI edits behave identically.
//

import Foundation
import EngineKit

/// A tool failure with a human-readable message surfaced back to the model.
struct MCPToolError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

final class MCPTools {

    private let overlayEngine = OverlayEngine()

    /// In-flight recording started via `start_recording`, finalized by
    /// `stop_recording`. Only one recording at a time (the engine enforces this).
    private var activeRecording: (session: Recorder.RecordingSession, outputURL: URL)?

    // MARK: - Dispatch

    func execute(name: String, arguments: [String: Any]) async throws -> String {
        switch name {
        case "list_projects":        return try await listProjects(arguments)
        case "create_empty_project": return try await createEmptyProject(arguments)
        case "start_recording":      return try await startRecording(arguments)
        case "stop_recording":       return try await stopRecording(arguments)
        case "get_project":          return try await getProject(arguments)
        case "split_clip":           return try await splitClip(arguments)
        case "delete_clip":          return try await deleteClip(arguments)
        case "set_track_muted":      return try await setTrackMuted(arguments)
        case "set_track_volume":     return try await setTrackVolume(arguments)
        case "set_clip_audio_muted": return try await setClipAudioMuted(arguments)
        case "add_image_clip":       return try await addImageClip(arguments)
        case "add_video_clip":       return try await addVideoClip(arguments)
        case "add_audio_clip":       return try await addAudioClip(arguments)
        case "add_color_clip":       return try await addColorClip(arguments)
        case "add_text_overlay":     return try await addTextOverlay(arguments)
        case "add_adjustment":       return try await addAdjustment(arguments)
        case "remove_adjustment":    return try await removeAdjustment(arguments)
        case "list_adjustments":     return try await listAdjustments(arguments)
        default:
            throw MCPToolError("Unknown tool: \(name)")
        }
    }

    // MARK: - Projects

    private func listProjects(_ args: [String: Any]) async throws -> String {
        let summaries = try await ProjectLibrary.shared.listProjects()
        return try jsonText(summaries)
    }

    private func getProject(_ args: [String: Any]) async throws -> String {
        let project = try await loadProject(args)
        return try jsonText(project)
    }

    // MARK: - Create / record

    private func createEmptyProject(_ args: [String: Any]) async throws -> String {
        let name = args.optStr("name")
        let tags = (args["tags"] as? [Any])?.compactMap { $0 as? String }
        let projectId = try await ProjectLibrary.shared.createEmptyProject(name: name, tags: tags)
        return "Created empty project \(projectId.uuidString)"
    }

    /// Begin a screen recording of the main display. Returns immediately; call
    /// `stop_recording` to finalize it into a project. Requires Screen Recording
    /// (and Microphone, if requested) permission for the host process.
    private func startRecording(_ args: [String: Any]) async throws -> String {
        guard activeRecording == nil else {
            throw MCPToolError("A recording is already in progress; call stop_recording first")
        }
        let captureSystemAudio = (try? args.bool("captureSystemAudio")) ?? true
        let captureMic = (try? args.bool("captureMicAudio")) ?? false

        let displays = try await SourceSelector.shared.listDisplays()
        guard let display = displays.first else {
            throw MCPToolError("No displays available to record")
        }

        let screenConfig = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: display,
            captureSystemAudio: captureSystemAudio
        )
        let config = Recorder.RecordingConfiguration(
            screenConfig: screenConfig,
            cameraConfig: nil,
            captureMicAudio: captureMic,
            captureTelemetry: true
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameramanMCP", isDirectory: true)
            .appendingPathComponent("recording_\(UUID().uuidString)", isDirectory: true)

        let session = try await Recorder.shared.startRecording(config: config, outputURL: outputURL)
        activeRecording = (session, outputURL)
        return "Recording started (display \(display.id)). Call stop_recording to finish."
    }

    /// Stop the in-flight recording and create a project from it.
    private func stopRecording(_ args: [String: Any]) async throws -> String {
        guard let active = activeRecording else {
            throw MCPToolError("No recording in progress")
        }
        let result = try await Recorder.shared.stopRecording(session: active.session)
        activeRecording = nil

        let name = args.optStr("name")
        let tags = (args["tags"] as? [Any])?.compactMap { $0 as? String }
        let projectId = try await ProjectLibrary.shared.createProject(from: result, name: name, tags: tags)
        return "Recording stopped (\(String(format: "%.1f", result.duration))s) -> project \(projectId.uuidString)"
    }

    // MARK: - Cut / split / delete

    private func splitClip(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let clipId = try args.str("clipId")
        let at = try args.num("atTime")
        let project = try await mutate(args) { editor in
            await editor.splitClip(clipId: clipId, inTrackId: trackId, at: at)
        }
        return try summary("Split clip \(clipId) at \(at)s", project)
    }

    private func deleteClip(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let clipId = try args.str("clipId")
        let project = try await mutate(args) { editor in
            await editor.removeClip(clipId: clipId, fromTrackId: trackId)
        }
        return try summary("Removed clip \(clipId)", project)
    }

    // MARK: - Mute / volume

    private func setTrackMuted(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let muted = try args.bool("muted")
        let project = try await mutate(args) { editor in
            await editor.setTrackMuted(trackId: trackId, muted: muted)
        }
        return try summary("Track \(trackId) muted=\(muted)", project)
    }

    private func setTrackVolume(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let volume = try args.num("volume")
        let project = try await mutate(args) { editor in
            await editor.setTrackVolume(trackId: trackId, volume: volume)
        }
        return try summary("Track \(trackId) volume=\(volume)", project)
    }

    private func setClipAudioMuted(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let clipId = try args.str("clipId")
        let muted = try args.bool("muted")
        let project = try await mutate(args) { editor in
            await editor.setClipAudioMuted(clipId: clipId, inTrackId: trackId, muted: muted)
        }
        return try summary("Clip \(clipId) audioMuted=\(muted)", project)
    }

    // MARK: - Add items

    private func addImageClip(_ args: [String: Any]) async throws -> String {
        let path = try args.str("path")
        let at = try args.num("at")
        let duration = args.optNum("duration") ?? 5.0
        let project = try await mutate(args) { editor in
            await editor.addImageClip(path: path, duration: duration, at: at)
        }
        return try summary("Added image clip at \(at)s", project)
    }

    private func addVideoClip(_ args: [String: Any]) async throws -> String {
        let path = try args.str("path")
        let at = try args.num("at")
        let duration = try args.num("duration")
        let project = try await mutate(args) { editor in
            await editor.importVideoClip(path: path, duration: duration, at: at)
        }
        return try summary("Added video clip at \(at)s", project)
    }

    private func addAudioClip(_ args: [String: Any]) async throws -> String {
        let path = try args.str("path")
        let at = try args.num("at")
        let duration = try args.num("duration")
        let sourceIn = args.optNum("sourceIn") ?? 0
        let project = try await mutate(args) { editor in
            await editor.addAudioClip(path: path, duration: duration, at: at, sourceIn: sourceIn)
        }
        return try summary("Added audio clip at \(at)s", project)
    }

    private func addColorClip(_ args: [String: Any]) async throws -> String {
        let at = try args.num("at")
        let duration = args.optNum("duration") ?? 3.0
        let hexColor = args.optStr("hexColor") ?? "#000000"
        let project = try await mutate(args) { editor in
            await editor.addColorClip(hexColor: hexColor, duration: duration, at: at)
        }
        return try summary("Added color clip at \(at)s", project)
    }

    private func addTextOverlay(_ args: [String: Any]) async throws -> String {
        let projectId = try args.uuid("projectId")
        let text = try args.str("text")
        let start = try args.num("start")
        let end = try args.num("end")
        let x = args.optNum("x") ?? 0.5
        let y = args.optNum("y") ?? 0.5
        let size = args.optNum("fontSize") ?? 36.0
        let color = args.optStr("color") ?? "#FFFFFF"
        _ = try await overlayEngine.addTextOverlay(
            projectId: projectId, start: start, end: end, x: x, y: y,
            text: text, size: size, color: color
        )
        return "Added text overlay \"\(text)\" from \(start)s to \(end)s"
    }

    // MARK: - Effects / adjustments

    private func addAdjustment(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let clipId = try args.str("clipId")
        let kind = Project.AdjustmentKind(rawValue: try args.str("kind"))
        let target = Project.AdjustmentTarget(rawValue: args.optStr("target") ?? "frame") ?? .frame
        let parameters = args.doubleDict("parameters")
        let adjustment = Project.Adjustment(
            kind: kind, target: target, parameters: parameters,
            start: args.optNum("start"), end: args.optNum("end")
        )
        let project = try await mutate(args) { editor in
            await editor.addAdjustment(adjustment, toClipId: clipId, inTrackId: trackId)
        }
        return try summary("Added \(kind.rawValue) adjustment (\(target.rawValue)) [id=\(adjustment.id)]", project)
    }

    private func removeAdjustment(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let clipId = try args.str("clipId")
        let adjustmentId = try args.uuid("adjustmentId")
        let project = try await mutate(args) { editor in
            await editor.removeAdjustment(adjustmentId, fromClipId: clipId, inTrackId: trackId)
        }
        return try summary("Removed adjustment \(adjustmentId)", project)
    }

    private func listAdjustments(_ args: [String: Any]) async throws -> String {
        let trackId = try args.uuid("trackId")
        let clipId = try args.str("clipId")
        let project = try await loadProject(args)
        guard let track = project.timeline.tracks.first(where: { $0.id == trackId }),
              let clip = track.clips.first(where: { $0.id == clipId }) else {
            throw MCPToolError("Clip \(clipId) not found on track \(trackId)")
        }
        return try jsonText(clip.adjustments ?? [])
    }

    // MARK: - Shared helpers

    /// Load → edit → persist, returning the updated project.
    private func mutate(_ args: [String: Any], _ op: (EditorModel) async -> EditorResult) async throws -> Project {
        let project = try await loadProject(args)
        let editor = EditorModel(project: project)
        let result = await op(editor)
        guard let updated = result.getProject() else {
            throw MCPToolError(describe(result))
        }
        try await ProjectLibrary.shared.updateProject(updated)
        return updated
    }

    private func loadProject(_ args: [String: Any]) async throws -> Project {
        let projectId = try args.uuid("projectId")
        return try await ProjectLibrary.shared.getProject(projectId: projectId)
    }

    private func describe(_ result: EditorResult) -> String {
        if case .failure(let error) = result {
            return error.localizedDescription
        }
        return "Editing operation failed"
    }

    /// A short confirmation plus a compact timeline snapshot so callers can chain
    /// follow-up edits without a separate get_project round-trip.
    private func summary(_ message: String, _ project: Project) throws -> String {
        let tracks: [[String: Any]] = project.timeline.tracks.map { track in
            [
                "id": track.id.uuidString,
                "type": track.type.rawValue,
                "name": track.name,
                "isMuted": track.isMuted,
                "clips": track.clips.map { clip -> [String: Any] in
                    [
                        "id": clip.id,
                        "timelineIn": clip.timelineIn,
                        "timelineOut": clip.timelineOut,
                        "adjustments": (clip.adjustments ?? []).count
                    ]
                }
            ]
        }
        let payload: [String: Any] = [
            "message": message,
            "projectId": project.projectId.uuidString,
            "duration": project.timeline.duration,
            "tracks": tracks
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? message
    }

    private func jsonText<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Argument parsing

private extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) throws -> String {
        guard let value = self[key] as? String else { throw MCPToolError("Missing string argument '\(key)'") }
        return value
    }

    func optStr(_ key: String) -> String? { self[key] as? String }

    func num(_ key: String) throws -> Double {
        if let d = self[key] as? Double { return d }
        if let i = self[key] as? Int { return Double(i) }
        if let s = self[key] as? String, let d = Double(s) { return d }
        throw MCPToolError("Missing number argument '\(key)'")
    }

    func optNum(_ key: String) -> Double? {
        if let d = self[key] as? Double { return d }
        if let i = self[key] as? Int { return Double(i) }
        if let s = self[key] as? String, let d = Double(s) { return d }
        return nil
    }

    func bool(_ key: String) throws -> Bool {
        if let b = self[key] as? Bool { return b }
        if let i = self[key] as? Int { return i != 0 }
        throw MCPToolError("Missing boolean argument '\(key)'")
    }

    func uuid(_ key: String) throws -> UUID {
        let raw = try str(key)
        guard let id = UUID(uuidString: raw) else { throw MCPToolError("Invalid UUID for '\(key)': \(raw)") }
        return id
    }

    /// Coerce a nested object into `[String: Double]` (effect parameters).
    func doubleDict(_ key: String) -> [String: Double] {
        guard let raw = self[key] as? [String: Any] else { return [:] }
        var out: [String: Double] = [:]
        for (k, v) in raw {
            if let d = v as? Double { out[k] = d }
            else if let i = v as? Int { out[k] = Double(i) }
            else if let s = v as? String, let d = Double(s) { out[k] = d }
        }
        return out
    }
}
