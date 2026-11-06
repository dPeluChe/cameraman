//
//  MCPCatalog.swift
//  cameraman-mcp
//
//  The `tools/list` catalog: name, description, and JSON-Schema for each tool.
//

import Foundation
import EngineKit

extension MCPTools {

    /// Tool definitions returned by `tools/list`.
    static let catalog: [[String: Any]] =
        projectTools + clipTools + motionTools + musicTools + trackTools + deliveryTools + canvasTools + overlayTools

    // MARK: - Projects / management

    private static var projectTools: [[String: Any]] {
        [
            tool("list_projects",
                 "List Project Studio projects with id, name, tags, duration and timestamps. Pass `query` to search by name and tags.",
                 properties: [
                    "query": str("Optional search text (name and tags)"),
                    "matchAllTerms": bool("With query: require every term to match (default false)")
                 ],
                 required: []),

            tool("get_project",
                 "Get the project: timeline tracks & clips (with ids), canvas, takes, overlays and per-clip adjustments, plus subtitleCount. Subtitle cues are omitted unless include has subtitles (they can be large); the transcript text is get_captions. Call this first to discover track/clip ids for editing.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "include": array("Optional extras: \"subtitles\" (omitted by default)")
                 ],
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

            tool("update_project",
                 "Rename a project and/or replace its tags (metadata only; not for timeline edits). Pass only what changes.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "name": str("New name"),
                    "tags": array("Replacement tag strings (replaces all existing tags)")
                 ],
                 required: ["projectId"]),

            tool("delete_project",
                 "Permanently delete a project and all its files. Irreversible.",
                 properties: ["projectId": str("Project UUID")],
                 required: ["projectId"]),

            tool("merge_projects",
                 "Merge two projects into a new one (second appended after first). Returns the new project id.",
                 properties: [
                    "firstId": str("First project UUID"),
                    "secondId": str("Second project UUID"),
                    "name": str("Optional name for the merged project")
                 ],
                 required: ["firstId", "secondId"]),

            tool("export_bundle",
                 "Export a portable, editable project package (.cameramanproject) into a folder. Returns the bundle path. For a final video use export_project.",
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
                 "Add a clip as a NEW track (video/image/color on a video track, audio on an audio track) at timeline time `at`. type=image|video|audio need an absolute `path` (copied into the project); color uses hexColor. video/audio need `duration`; image defaults to 5s, color to 3s (hexColor default #000000). Returns the timeline with the new clip id.",
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
                 "Remove ONE clip from its track, leaving a gap; other clips do not move. To cut a time span across all tracks and close the gap, use delete_range.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "clipId": str("Clip id")
                 ],
                 required: ["projectId", "trackId", "clipId"]),

            tool("edit_clip",
                 "Edit a clip in one call: reposition (timelineIn), move to another track (toTrackId), retime (speed/volume/opacity), mute (audioMuted) and/or trim its source window (sourceIn/sourceOut). Pass only what changes. For video/recording, sourceIn/sourceOut are source-relative seconds; for audio sourceOut sets duration; for image/color sourceOut sets on-screen duration.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Current track UUID"),
                    "clipId": str("Clip id"),
                    "timelineIn": num("New timeline start in seconds"),
                    "toTrackId": str("Destination track UUID (to move across tracks)"),
                    "speed": num("Playback speed multiplier, greater than 0 (e.g. 0.5, 2.0)"),
                    "volume": num("Clip volume 0.0–1.0"),
                    "opacity": num("Clip opacity 0.0–1.0 (video)"),
                    "x": num("Canvas placement, left edge from -1 to 1. Pass x, y, w and h together. A clip with no placement fills the canvas (0, 0, 1, 1); a negative x or y slides it off canvas"),
                    "y": num("Canvas placement, top edge from -1 to 1"),
                    "w": num("Canvas placement, width up to 1"),
                    "h": num("Canvas placement, height up to 1"),
                    "sourceIn": num("New source in-point (seconds)"),
                    "sourceOut": num("New source out-point (seconds), must be greater than sourceIn"),
                    "audioMuted": bool("Mute or unmute the clip's own audio (recording clips)")
                 ],
                 required: ["projectId", "trackId", "clipId"]),

            tool("delete_range",
                 "Ripple-delete the span from..to on every unlocked track: clips are trimmed or split and later clips shift left. To remove a single clip, use delete_clip.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "from": num("Range start in seconds"),
                    "to": num("Range end in seconds")
                 ],
                 required: ["projectId", "from", "to"]),

            tool("add_adjustment",
                 "Attach an extensible effect to a clip. Visual kinds: sepia, monochrome, brightness, contrast, saturation, colorControls, vibrance, hue, invert, vignette, gaussianBlur. To hide something on screen (an API key, an email), use gaussianBlur with a region: parameters radius plus x, y, w, h, all four together, as fractions of the frame (0 to 1) with the origin at the top-left, and start/end to limit it in time; without a region the whole layer is blurred. Audio kinds: audioPitch (params: cents or semitones), audioGain. Target a layer to e.g. sepia the camera while the background is black & white.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "clipId": str("Clip id"),
                    "kind": str("Effect kind (e.g. sepia, monochrome, audioPitch)"),
                    "target": strEnum("Layer the effect applies to", ["frame", "screen", "camera", "background", "audio"]),
                    "parameters": object("Effect parameters, e.g. {\"intensity\": 0.8}, {\"semitones\": -3} or a blur region {\"radius\": 20, \"x\": 0.1, \"y\": 0.2, \"w\": 0.4, \"h\": 0.1}"),
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
                    "adjustmentId": str("Adjustment UUID (from add_adjustment's [id=...] or get_project)")
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
                    "locked": bool("true to lock (locked tracks reject edits)"),
                    "belowCamera": bool("Video tracks: true draws under the camera, false over it. Motion tracks start under it"),
                    "ducking": num("Audio tracks: multiplier for its clips while someone speaks, 0-1. 1 turns it off. Needs a transcript")
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
                                      presetIds),
                    "burnCaptions": bool("Burn captions into the video (default false; ignored for GIF)"),
                    "filename": str("Optional output filename")
                 ],
                 required: ["projectId"]),

            tool("get_job_status",
                 "Poll an export/transcription/AI job by jobId, or pass projectId to list every job for that project. Jobs are in memory and lost when the server restarts. Returns status (queued/running/success/failed/canceled), progress 0-1, any error, and for a finished suggest_* job its `suggestions`.",
                 properties: [
                    "jobId": str("Job UUID returned by export_project / transcribe_project / suggest_*"),
                    "projectId": str("Instead of jobId: list every job for this project")
                 ],
                 required: []),

            tool("cancel_job",
                 "Cancel a running or queued job.",
                 properties: ["jobId": str("Job UUID")],
                 required: ["jobId"]),

            tool("transcribe_project",
                 "Transcribe the project's audio on-device (Apple Silicon only). Async: returns a jobId. Writes transcript/caption files but does NOT change the timeline; next use get_captions to read, or add_subtitles to place cues on the timeline.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "model": strEnum("Whisper model (bigger = slower/more accurate; default base)", ["base", "small", "medium", "large"]),
                    "language": str("Optional ISO language code (e.g. en, es); omit to auto-detect"),
                    "translate": bool("Translate to English instead of keeping the spoken language (default false)")
                 ],
                 required: ["projectId"]),

            tool("get_captions",
                 "Read the raw text produced by transcribe_project (srt, vtt, or json = full transcript with segments). Read-only; does not touch the timeline.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "format": strEnum("Caption format (default srt)", ["srt", "vtt", "json"])
                 ],
                 required: ["projectId"]),

            tool("add_subtitles",
                 "Generate editable subtitle cues on the timeline from the project's transcript (run transcribe_project first). Replaces existing subtitles; they render over the video and burn into exports when burnCaptions is set.",
                 properties: ["projectId": str("Project UUID")],
                 required: ["projectId"]),

            tool("suggest_silence_edits",
                 "Analyze the project audio on-device for silent ranges worth cutting. Async: returns a jobId; poll get_job_status, whose success reply includes `suggestions`.",
                 properties: ["projectId": str("Project UUID")],
                 required: ["projectId"]),

            tool("suggest_chapters",
                 "Suggest chapter markers from the project's transcript on-device (run transcribe_project first). Async: returns a jobId; poll get_job_status, whose success reply includes `suggestions`.",
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
                    "cameraSide": strEnum("side_by_side only: the column for the camera; the screen takes the other", ["left", "right"]),
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
                 "Add an overlay: arrow, rect, line or text. Shapes use stroke/strokeWidth; text needs text (and optional fontSize/color). Optional drawOn (arrow/line only) or fadeIn (text) animation. Returns the new overlayId.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "type": strEnum("Overlay type", ["arrow", "rect", "line", "text"]),
                    "start": num("Start time in seconds"),
                    "end": num("End time in seconds (must not exceed the project duration; see get_project)"),
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

            tool("update_overlay",
                 "Update an overlay. Pass only the fields to change (position x/y, scale, rotation, start/end, stroke, strokeWidth, color, fontSize, text).",
                 properties: [
                    "projectId": str("Project UUID"),
                    "overlayId": str("Overlay UUID (from add_overlay or get_project)"),
                    "x": num("Normalized x 0–1"),
                    "y": num("Normalized y 0–1"),
                    "scale": num("Scale"),
                    "rotation": num("Rotation in degrees"),
                    "start": num("Start time in seconds"),
                    "end": num("End time in seconds (must not exceed the project duration; see get_project)"),
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

    // MARK: - Motion graphics

    private static var motionTools: [[String: Any]] {
        [
            tool("preview_frame",
                 "Look at the finished picture: the timeline composited at time `at` (screen, camera, motions, overlays) as a JPEG. Zoom and cursor effects are left out. Use it after add_motion or a placement change. Read-only.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "at": num("Timeline time in seconds"),
                    "maxWidth": num("Longest side of the image in pixels (default 1280, 320-1920)")
                 ],
                 required: ["projectId", "at"]),

            tool("add_motion",
                 "Render a motion graphic to a transparent video and add it over the footage as a clip at timeline time `at`, on the Motion track (a second one only when motions overlap). The reply has clipId, trackId and visibleArea (where it draws, as canvas fractions); check it with preview_frame. Use it to reinforce what is said: read get_captions for the words and their times, then add a name card where someone is introduced, a stat where a number is quoted, a chart where values are compared. Pick a `template` (lower_third: title+subtitle; title: title+subtitle; stat: value like 42, 42% or $1.2M counts up, title is the caption; bar_chart: title, labels[] and values[] of equal length, up to 12). Templates take color and duration (default 4s, minimum 1.5s) and animate in, hold and animate out. Or pass `html` for anything custom: it renders at the canvas size on a TRANSPARENT page (leave html/body background unset), size text in vh/vw, and it must be seekable and deterministic: define window.__hf = { duration: seconds, seek(t) { set the whole scene for time t } }, or use only finite CSS animations / WAAPI / a GSAP timeline in window.__timelines. No Date.now, unseeded Math.random or network. Takes a few seconds. It draws under the camera; set_track belowCamera=false puts it on top. Change or remove the result with edit_clip / delete_clip.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "at": num("Timeline start time in seconds"),
                    "template": strEnum("Built-in motion", MotionTemplate.allCases.map(\.rawValue)),
                    "title": str("Template text: main line / chart title / stat caption"),
                    "subtitle": str("Template text: second line"),
                    "value": str("stat: the number, optionally with prefix/suffix (42, 42%, $1.2M)"),
                    "labels": array("bar_chart: one label per bar"),
                    "values": ["type": "array", "description": "bar_chart: one non-negative number per bar", "items": ["type": "number"]],
                    "color": str("Accent color #RRGGBB (default #0A84FF)"),
                    "html": str("Custom page instead of a template (see the contract above)"),
                    "duration": num("Seconds (0.5-120). Template length; for custom html, overrides the page's own duration"),
                    "x": num("Placement: left edge as a 0-1 fraction of the canvas (give x, y, w, h together; omit all for full screen)"),
                    "y": num("Placement: top edge, 0-1"),
                    "w": num("Placement: width, 0-1"),
                    "h": num("Placement: height, 0-1")
                 ],
                 required: ["projectId", "at"]),

            tool("update_motion",
                 "Change a motion in place: re-renders it and keeps its time and placement. Pass only what changes (text, color, duration, html or template); the rest comes from how it was made. Motions from older versions have no saved source, so they need the full html or a template. Takes a few seconds.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "clipId": str("Clip id"),
                    "template": strEnum("Switch to a built-in motion", MotionTemplate.allCases.map(\.rawValue)),
                    "title": str("Template text: main line"),
                    "subtitle": str("Template text: second line"),
                    "value": str("stat: the number"),
                    "labels": array("bar_chart: one label per bar"),
                    "values": ["type": "array", "description": "bar_chart: one number per bar", "items": ["type": "number"]],
                    "color": str("Accent color #RRGGBB"),
                    "html": str("Custom page replacing the current one"),
                    "duration": num("Seconds (0.5-120)")
                 ],
                 required: ["projectId", "trackId", "clipId"])
        ]
    }

    // MARK: - Music

    private static var musicTools: [[String: Any]] {
        [
            tool("add_music",
                 "Compose instrumental background music and add it as an audio clip on the Music track at `at` (default 0). It is rendered on this Mac: no vocals, no licensing, same score and seed give the same sound. Without `duration` it runs to the end of the timeline. Read get_captions to choose the mood. Pass a `style`, optionally with key, bpm, intensity and seed; another seed gives another piece. Or pass `code`: the body of a function (m, options) written with the score kit, documented in docs/FEATURES/MUSIC.md: m.tempo(bpm), m.key('A minor'), m.bars(fn), m.steps(t, count, beats, fn), m.triad(degree, octave, size), m.voiced(chord), m.bus({gain, pan, lowpass, highpass, reverb, delay}), m.active(t, level), and the instruments m.pad, m.strings, m.keys, m.pluck, m.bass, m.bell, m.kick, m.snare, m.hat, m.shaker, m.impact, m.riser, m.vinyl. Reuse a style with Score.styles.lofi(m, options) and add to it. It drops under speech in preview and export while the project has a transcript (run transcribe_project); the reply's speechDucking says if it does, and set_track ducking changes it. Takes a few seconds. Change it with update_music, its level with edit_clip volume.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "at": num("Timeline start in seconds (default 0)"),
                    "duration": num("Seconds, 1-600 (default: to the end of the timeline)"),
                    "style": strEnum("Built-in score", MusicStyle.allCases.map(\.rawValue)),
                    "code": str("Custom score instead of a style"),
                    "key": str("Key such as 'A minor', 'D dorian', 'C major'"),
                    "bpm": num("Tempo, 40-200"),
                    "intensity": num("How much plays at once, 0-1 (default 0.5)"),
                    "seed": num("Variation number (default 1)"),
                    "volume": num("Clip volume, 0-1 (default 0.25, a bed under a voice)"),
                    "ducking": num("Multiplier under speech, 0-1 (default 0.5). 1 turns it off. Applies to a new Music track")
                 ],
                 required: ["projectId"]),

            tool("update_music",
                 "Change a piece of music in place: renders it again and keeps its time and volume. Pass only what changes; a new seed gives a new take of the same style. Takes a few seconds.",
                 properties: [
                    "projectId": str("Project UUID"),
                    "trackId": str("Track UUID"),
                    "clipId": str("Clip id"),
                    "duration": num("Seconds, 1-600"),
                    "style": strEnum("Switch to a built-in score", MusicStyle.allCases.map(\.rawValue)),
                    "code": str("Custom score replacing the current one"),
                    "key": str("Key such as 'A minor'"),
                    "bpm": num("Tempo, 40-200"),
                    "intensity": num("How much plays at once, 0-1"),
                    "seed": num("Variation number")
                 ],
                 required: ["projectId", "trackId", "clipId"])
        ]
    }

    // MARK: - Schema builders

    /// MCP annotations (spec 2025-03-26+), sent minimally because every byte is tokens on each
    /// session: readOnlyHint for reads, destructiveHint true for removals, and destructiveHint
    /// false for other writes (the spec default is true, so it must be stated).
    private static let readOnlyTools: Set<String> = [
        "preview_frame",
        "list_projects", "get_project", "get_job_status", "get_captions",
    ]
    private static let destructiveTools: Set<String> = [
        "delete_project", "delete_clip", "delete_range", "remove_track", "remove_adjustment",
        "clear_adjustments", "delete_overlay", "cancel_job",
    ]

    private static func annotations(for name: String) -> [String: Bool] {
        if readOnlyTools.contains(name) { return ["readOnlyHint": true] }
        return ["destructiveHint": destructiveTools.contains(name)]
    }

    private static func tool(_ name: String, _ description: String,
                             properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "annotations": annotations(for: name),
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
