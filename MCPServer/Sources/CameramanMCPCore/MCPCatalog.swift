//
//  MCPCatalog.swift
//  cameraman-mcp
//
//  The `tools/list` catalog: name, description, and JSON-Schema for each tool.
//

import Foundation

extension MCPTools {

    /// Tool definitions returned by `tools/list`.
    static var catalog: [[String: Any]] {
        [
            tool("list_projects",
                 "List all Project Studio projects with their id, name, tags, duration and timestamps.",
                 properties: [:], required: []),

            tool("delete_project",
                 "Permanently delete a project and all its files. Irreversible.",
                 properties: [
                    "projectId": str("Project UUID")
                 ],
                 required: ["projectId"]),

            tool("get_project",
                 "Get the full project: timeline tracks & clips (with ids), canvas, takes, overlays and per-clip adjustments. Call this first to discover track/clip ids for editing.",
                 properties: ["projectId": str("Project UUID")],
                 required: ["projectId"]),

            tool("create_empty_project",
                 "Create a new empty project (no recording) ready for importing media and editing. Returns the new project id.",
                 properties: [
                    "name": str("Optional project name"),
                    "tags": array("Optional list of tag strings")
                 ],
                 required: []),

            tool("start_recording",
                 "Start a screen recording of the main display. Returns immediately; call stop_recording to finalize it into a project. The host process needs Screen Recording permission (and Microphone, if captureMicAudio is true).",
                 properties: [
                    "captureSystemAudio": bool("Capture system audio (default true)"),
                    "captureMicAudio": bool("Capture microphone (default false)")
                 ],
                 required: []),

            tool("stop_recording",
                 "Stop the in-flight recording and create a project from it. Returns the new project id.",
                 properties: [
                    "name": str("Optional project name"),
                    "tags": array("Optional list of tag strings")
                 ],
                 required: []),

            tool("split_clip",
                 "Cut a clip into two at a timeline time (seconds). Works on any clip type.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID (from get_project)"),
                    "clipId": str("Clip id (from get_project)"),
                    "atTime": num("Timeline time in seconds, strictly inside the clip")
                 ],
                 required: ["projectId", "trackId", "clipId", "atTime"]),

            tool("delete_clip",
                 "Remove a clip from a track.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "clipId": str("Clip id")
                 ],
                 required: ["projectId", "trackId", "clipId"]),

            tool("set_track_muted",
                 "Mute or unmute an entire track (audio tracks: silence; video tracks: hide).",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "muted": bool("true to mute/hide")
                 ],
                 required: ["projectId", "trackId", "muted"]),

            tool("set_track_volume",
                 "Set a track's volume (0.0–1.0).",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "volume": num("0.0 (silent) to 1.0 (full)")
                 ],
                 required: ["projectId", "trackId", "volume"]),

            tool("set_clip_audio_muted",
                 "Mute/unmute the audio of a single recording clip.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "clipId": str("Recording clip id"),
                    "muted": bool("true to mute the clip's audio")
                 ],
                 required: ["projectId", "trackId", "clipId", "muted"]),

            tool("add_image_clip",
                 "Add a still image as a clip on a new video track at a given time.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "path": str("Absolute path to an existing image file; copied into the project."),
                    "at": num("Timeline start time in seconds"),
                    "duration": num("How long to show the image (seconds, default 5)")
                 ],
                 required: ["projectId", "path", "at"]),

            tool("add_video_clip",
                 "Add an imported video as a clip on a new video track at a given time.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "path": str("Absolute path to an existing video file; copied into the project."),
                    "at": num("Timeline start time in seconds"),
                    "duration": num("Source duration to use (seconds)")
                 ],
                 required: ["projectId", "path", "at", "duration"]),

            tool("add_audio_clip",
                 "Add an audio file (music / voiceover) as a clip on a new audio track.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "path": str("Absolute path to an existing audio file; copied into the project."),
                    "at": num("Timeline start time in seconds"),
                    "duration": num("Duration to play (seconds)"),
                    "sourceIn": num("Start offset inside the source audio (seconds, default 0)")
                 ],
                 required: ["projectId", "path", "at", "duration"]),

            tool("add_color_clip",
                 "Add a solid color card (title/transition) on a new video track.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "at": num("Timeline start time in seconds"),
                    "duration": num("Duration in seconds (default 3)"),
                    "hexColor": str("Hex color like #000000 (default black)")
                 ],
                 required: ["projectId", "at"]),

            tool("add_text_overlay",
                 "Add a text overlay (e.g. a caption or a date) visible for a time range.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "text": str("Text to display"),
                    "start": num("Start time in seconds"),
                    "end": num("End time in seconds"),
                    "x": num("Normalized x position 0–1 (default 0.5)"),
                    "y": num("Normalized y position 0–1 (default 0.5)"),
                    "fontSize": num("Font size (default 36)"),
                    "color": str("Hex text color (default #FFFFFF)")
                 ],
                 required: ["projectId", "text", "start", "end"]),

            tool("add_adjustment",
                 "Attach an extensible effect to a clip. Visual kinds: sepia, monochrome, brightness, contrast, saturation, colorControls, vibrance, hue, invert, vignette, gaussianBlur. Audio kinds: audioPitch (params: cents or semitones), audioGain. Target a layer to e.g. sepia the camera while the background is black & white.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "clipId": str("Clip id"),
                    "kind": str("Effect kind (e.g. sepia, monochrome, audioPitch)"),
                    "target": strEnum("Layer the effect applies to", ["frame", "screen", "camera", "background", "audio"]),
                    "parameters": object("Effect parameters, e.g. {\"intensity\": 0.8} or {\"semitones\": -3}"),
                    "start": num("Clip-relative start in seconds (optional, default whole clip)"),
                    "end": num("Clip-relative end in seconds (optional)")
                 ],
                 required: ["projectId", "trackId", "clipId", "kind"]),

            tool("remove_adjustment",
                 "Remove an effect from a clip by its adjustment id.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "clipId": str("Clip id"),
                    "adjustmentId": str("Adjustment UUID (from list_adjustments / add_adjustment)")
                 ],
                 required: ["projectId", "trackId", "clipId", "adjustmentId"]),

            tool("list_adjustments",
                 "List the effects attached to a clip.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "clipId": str("Clip id")
                 ],
                 required: ["projectId", "trackId", "clipId"])
        ]
    }

    // MARK: - Schema builders

    private static func tool(_ name: String, _ description: String,
                             properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": required
            ]
        ]
    }

    private static func str(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static func strEnum(_ description: String, _ values: [String]) -> [String: Any] {
        ["type": "string", "description": description, "enum": values]
    }

    private static func num(_ description: String) -> [String: Any] {
        ["type": "number", "description": description]
    }

    private static func bool(_ description: String) -> [String: Any] {
        ["type": "boolean", "description": description]
    }

    private static func object(_ description: String) -> [String: Any] {
        ["type": "object", "description": description]
    }

    private static func array(_ description: String) -> [String: Any] {
        ["type": "array", "description": description, "items": ["type": "string"]]
    }
}
