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
        projectTools + clipTools + trackTools + deliveryTools + canvasTools + overlayTools
    }

    // MARK: - Projects / management

    private static var projectTools: [[String: Any]] {
        [
            tool("list_projects",
                 "List all Project Studio projects with their id, name, tags, duration and timestamps.",
                 properties: [:], required: []),

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

            tool("duplicate_project",
                 "Clone a project (timeline, media and all) into a new project. Returns the new project id — handy for safe experiments on a copy.",
                 properties: ["projectId": str("Project UUID to clone")],
                 required: ["projectId"]),

            tool("delete_project",
                 "Permanently delete a project and all its files. Irreversible.",
                 properties: ["projectId": str("Project UUID")],
                 required: ["projectId"]),

            tool("rename_project",
                 "Rename a project.",
                 properties: ["projectId": str("Project UUID"), "name": str("New name")],
                 required: ["projectId", "name"]),

            tool("set_tags",
                 "Replace a project's tags.",
                 properties: ["projectId": str("Project UUID"), "tags": array("Tag strings")],
                 required: ["projectId", "tags"]),

            tool("search_projects",
                 "Search projects by name and tags.",
                 properties: [
                    "query": str("Search text"),
                    "matchAllTerms": bool("Require all terms to match (default false)")
                 ],
                 required: ["query"]),

            tool("merge_projects",
                 "Merge two projects into a new one (second appended after first). Returns the new project id.",
                 properties: [
                    "firstId": str("First project UUID"),
                    "secondId": str("Second project UUID"),
                    "name": str("Optional name for the merged project")
                 ],
                 required: ["firstId", "secondId"]),

            tool("export_bundle",
                 "Export a project as a portable .cameramanproject bundle into a folder. Returns the bundle path.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "destinationFolder": str("Absolute path to an existing destination folder")
                 ],
                 required: ["projectId", "destinationFolder"]),

            tool("import_bundle",
                 "Import a .cameramanproject bundle as a new project. Returns the new project id.",
                 properties: ["bundlePath": str("Absolute path to a .cameramanproject bundle")],
                 required: ["bundlePath"]),

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
                 required: [])
        ]
    }

    // MARK: - Clips & adjustments

    private static var clipTools: [[String: Any]] {
        [
            tool("add_clip",
                 "Add a clip to the timeline. type=image|video|audio (need an absolute `path`, copied into the project) or color (uses hexColor). video/audio need `duration`; image defaults 5s, color 3s.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "type": strEnum("Clip type", ["image", "video", "audio", "color"]),
                    "at": num("Timeline start time in seconds"),
                    "path": str("Absolute path to an existing media file (image/video/audio)"),
                    "duration": num("Duration in seconds (required for video/audio)"),
                    "sourceIn": num("Start offset inside the source (audio, default 0)"),
                    "hexColor": str("Color card hex like #000000 (color)")
                 ],
                 required: ["projectId", "type", "at"]),

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

            tool("edit_clip",
                 "Edit a clip in one call: reposition (timelineIn), move to another track (toTrackId), retime (speed/volume/opacity) and/or trim its source window (sourceIn/sourceOut). Pass only what changes. For video/recording, sourceIn/sourceOut are source-relative seconds; for audio sourceOut sets duration; for image/color sourceOut sets on-screen duration.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Current track UUID"),
                    "clipId": str("Clip id"),
                    "timelineIn": num("New timeline start in seconds"),
                    "toTrackId": str("Destination track UUID (to move across tracks)"),
                    "speed": num("Playback speed multiplier (e.g. 0.5, 2.0)"),
                    "volume": num("Clip volume 0.0–1.0"),
                    "opacity": num("Clip opacity 0.0–1.0 (video)"),
                    "sourceIn": num("New source in-point (seconds)"),
                    "sourceOut": num("New source out-point (seconds)")
                 ],
                 required: ["projectId", "trackId", "clipId"]),

            tool("delete_range",
                 "Ripple-delete a time range from the timeline: remove everything between two times and close the gap.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "from": num("Range start in seconds"),
                    "to": num("Range end in seconds")
                 ],
                 required: ["projectId", "from", "to"]),

            tool("set_clip_audio_muted",
                 "Mute/unmute the audio of a single recording clip.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "clipId": str("Recording clip id"),
                    "muted": bool("true to mute the clip's audio")
                 ],
                 required: ["projectId", "trackId", "clipId", "muted"]),

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

            tool("update_adjustment",
                 "Update an existing effect on a clip. Pass only the fields to change (parameters, enabled, kind, target, start, end).",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "clipId": str("Clip id"),
                    "adjustmentId": str("Adjustment UUID"),
                    "parameters": object("New effect parameters"),
                    "enabled": bool("Enable/disable the effect"),
                    "kind": str("New effect kind"),
                    "target": strEnum("Layer", ["frame", "screen", "camera", "background", "audio"]),
                    "start": num("Clip-relative start (seconds)"),
                    "end": num("Clip-relative end (seconds)")
                 ],
                 required: ["projectId", "trackId", "clipId", "adjustmentId"]),

            tool("remove_adjustment",
                 "Remove an effect from a clip by its adjustment id.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "clipId": str("Clip id"),
                    "adjustmentId": str("Adjustment UUID (from list_adjustments / add_adjustment)")
                 ],
                 required: ["projectId", "trackId", "clipId", "adjustmentId"]),

            tool("clear_adjustments",
                 "Remove all effects from a clip.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "clipId": str("Clip id")
                 ],
                 required: ["projectId", "trackId", "clipId"]),

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

    // MARK: - Tracks

    private static var trackTools: [[String: Any]] {
        [
            tool("add_track",
                 "Add a new empty track.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "type": strEnum("Track type", ["primary", "video", "audio"]),
                    "name": str("Optional track name")
                 ],
                 required: ["projectId", "type"]),

            tool("remove_track",
                 "Remove a track and its clips.",
                 properties: ["projectId": str("Project UUID"), "trackId": str("Track UUID")],
                 required: ["projectId", "trackId"]),

            tool("move_video_track",
                 "Reorder a video track in the compositing stack (z-order).",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "up": bool("true to move up (front), false to move down")
                 ],
                 required: ["projectId", "trackId", "up"]),

            tool("set_track",
                 "Set a track's properties in one call: muted (audio: silence / video: hide), volume (0.0–1.0) and/or locked. Pass only what changes.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "muted": bool("true to mute/hide the track"),
                    "volume": num("Track volume 0.0–1.0"),
                    "locked": bool("true to lock (locked tracks reject edits)")
                 ],
                 required: ["projectId", "trackId"])
        ]
    }

    // MARK: - Delivery (export, jobs, transcription)

    private static var deliveryTools: [[String: Any]] {
        [
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
                 "Get the status of an export/transcription/AI job: status (queued/running/success/failed/canceled), progress (0–1), and any error.",
                 properties: ["jobId": str("Job UUID returned by export_project / transcribe_project / suggest_*")],
                 required: ["jobId"]),

            tool("list_jobs",
                 "List all jobs (export, transcription, …) for a project in this server session.",
                 properties: ["projectId": str("Project UUID")],
                 required: ["projectId"]),

            tool("cancel_job",
                 "Cancel a running or queued job.",
                 properties: ["jobId": str("Job UUID")],
                 required: ["jobId"]),

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

            tool("suggest_silence_edits",
                 "Analyze the project audio on-device and suggest silent ranges to cut. Async: returns a jobId; poll get_job_status.",
                 properties: ["projectId": str("Project UUID")],
                 required: ["projectId"]),

            tool("suggest_chapters",
                 "Suggest chapter markers from the project's transcript on-device (run transcribe_project first). Async: returns a jobId; poll get_job_status.",
                 properties: ["projectId": str("Project UUID")],
                 required: ["projectId"])
        ]
    }

    // MARK: - Canvas

    private static var canvasTools: [[String: Any]] {
        [
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

    // MARK: - Overlays

    private static var overlayTools: [[String: Any]] {
        [
            tool("add_overlay",
                 "Add an overlay: arrow, rect, line or text. Shapes use stroke/strokeWidth; text needs text (and optional fontSize/color). Optional drawOn (shapes) or fadeIn (text) animation. Returns the new overlayId.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "type": strEnum("Overlay type", ["arrow", "rect", "line", "text"]),
                    "start": num("Start time in seconds"),
                    "end": num("End time in seconds"),
                    "x": num("Normalized x 0–1 (default 0.5)"),
                    "y": num("Normalized y 0–1 (default 0.5)"),
                    "scale": num("Scale (default 1.0)"),
                    "rotation": num("Rotation in degrees (default 0)"),
                    "stroke": str("Shape stroke hex color (default #FFFFFF)"),
                    "strokeWidth": num("Shape stroke width"),
                    "text": str("Text content (text overlays)"),
                    "fontSize": num("Font size (text, default 36)"),
                    "color": str("Text hex color (default #FFFFFF)"),
                    "drawOn": bool("Animate arrow/line drawing on (default false)"),
                    "fadeIn": bool("Fade text in (default false)")
                 ],
                 required: ["projectId", "type", "start", "end"]),

            tool("list_overlays",
                 "List all overlays on a project with their ids, types, times, transform and style.",
                 properties: ["projectId": str("Project UUID")],
                 required: ["projectId"]),

            tool("update_overlay",
                 "Update an overlay. Pass only the fields to change (position x/y, scale, rotation, start/end, stroke, strokeWidth, color, fontSize, text).",
                 properties: [
                    "projectId": str("Project UUID"),
                    "overlayId": str("Overlay UUID (from list_overlays / add_overlay)"),
                    "x": num("Normalized x 0–1"),
                    "y": num("Normalized y 0–1"),
                    "scale": num("Scale"),
                    "rotation": num("Rotation in degrees"),
                    "start": num("Start time in seconds"),
                    "end": num("End time in seconds"),
                    "stroke": str("Shape stroke hex color"),
                    "strokeWidth": num("Shape stroke width"),
                    "color": str("Text hex color"),
                    "fontSize": num("Text font size"),
                    "text": str("Text content")
                 ],
                 required: ["projectId", "overlayId"]),

            tool("delete_overlay",
                 "Delete an overlay by id.",
                 properties: ["projectId": str("Project UUID"), "overlayId": str("Overlay UUID")],
                 required: ["projectId", "overlayId"])
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
