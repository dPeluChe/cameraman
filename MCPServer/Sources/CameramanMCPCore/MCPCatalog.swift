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
                 required: ["projectId", "trackId", "clipId"]),

            // MARK: Delivery — export & jobs

            tool("export_project",
                 "Render a project to a video (or GIF) file. Async: returns a jobId immediately; poll get_job_status until status is success, then the file is in the project's renders/ folder.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "preset": strEnum("Output preset (default web_1080_h264)",
                                      ["web_1080_h264", "high_1080_hevc", "portrait_1080_h264", "ultra_4k_hevc", "animated_gif"]),
                    "burnCaptions": bool("Burn captions into the video (default false; ignored for GIF)"),
                    "filename": str("Optional output filename")
                 ],
                 required: ["projectId"]),

            tool("get_job_status",
                 "Get the status of an export/transcription job: status (queued/running/success/failed/canceled), progress (0–1), and any error.",
                 properties: ["jobId": str("Job UUID returned by export_project / transcribe_project")],
                 required: ["jobId"]),

            tool("list_jobs",
                 "List all jobs (export, transcription, …) for a project in this server session.",
                 properties: ["projectId": str("Project UUID")],
                 required: ["projectId"]),

            tool("cancel_job",
                 "Cancel a running or queued job.",
                 properties: ["jobId": str("Job UUID")],
                 required: ["jobId"]),

            // MARK: Transcription

            tool("transcribe_project",
                 "Transcribe the project's audio on-device (Apple Silicon only). Async: returns a jobId; on success captions are written and readable via get_captions.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "model": strEnum("Whisper model (bigger = slower/more accurate; default base)", ["base", "small", "medium", "large"]),
                    "language": str("Optional ISO language code (e.g. en, es); omit to auto-detect")
                 ],
                 required: ["projectId"]),

            tool("get_captions",
                 "Read the generated captions for a project (run transcribe_project first).",
                 properties: [
                    "projectId": str("Project UUID"),
                    "format": strEnum("Caption format (default srt)", ["srt", "vtt", "json"])
                 ],
                 required: ["projectId"]),

            // MARK: Canvas composition

            tool("set_canvas_layout",
                 "Set how screen and camera are composed. type=fullscreen (screen only), pip (camera as a floating inset), or side_by_side. For pip/side_by_side pass an optional camera placement. Also tunes padding, corner radius and shadow.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "type": strEnum("Layout type", ["fullscreen", "pip", "side_by_side"]),
                    "camera": object("Camera placement (normalized 0–1): {x,y,w,h,cornerRadius,maskShape(none|circle|roundedRect|capsule),borderWidth,borderColor}"),
                    "padding": num("Canvas padding as a fraction of size (0–0.3)"),
                    "videoCornerRadius": num("Video corner radius in px (>=0)"),
                    "videoShadowIntensity": num("Video shadow intensity (0–1)")
                 ],
                 required: ["projectId"]),

            tool("set_background",
                 "Set the canvas background. type=color (value=hex like #101014), image (value=absolute path to an image, copied into the project), or blur (value=hex tint).",
                 properties: [
                    "projectId": str("Project UUID"),
                    "type": strEnum("Background type", ["color", "image", "blur"]),
                    "value": str("Hex color (#RRGGBB) or, for image, an absolute file path"),
                    "fitMode": strEnum("Image fit mode", ["fit", "fill"])
                 ],
                 required: ["projectId", "type", "value"])
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
