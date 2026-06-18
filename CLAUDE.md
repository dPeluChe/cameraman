# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Project Studio** (codename: labs-cameraman) is a macOS local-first screen recording and video editing application. It captures screen, camera, and audio as separate tracks, enables non-destructive editing, and exports to common video formats.

- **Platform:** macOS 13+ (Ventura required for ScreenCaptureKit system audio)
- **Language:** Swift 5.9+
- **Architecture:** EngineKit (Swift Package) + SwiftUI App

## Entry Points

- **Xcode app project:** `CameramanApp/CameramanApp.xcodeproj` (scheme: `CameramanApp`)
- **EngineKit package:** `EngineKit/` (Swift Package)
- **MCP server package:** `MCPServer/` (Swift Package, binary `cameraman-mcp`) — stdio JSON-RPC MCP server reusing EngineKit; see `MCPServer/README.md`

## Build & Test Commands

All commands run from the `EngineKit/` directory:

```bash
# Build
swift build                      # Debug build
swift build -c release           # Release build

# Test
swift test                       # Run all tests
swift test --filter <TestClass>  # Run specific test class
swift test --parallel            # Run tests in parallel
```

## Recording Output

When running the sandboxed app, recordings are saved under the app container:

`~/Library/Containers/dev.dpeluche.CameramanApp/Data/Documents/Recordings/recording_<ISO8601>/`

The recording produces separate track files:

- `screen.mov`
- `camera.mov`
- `system_audio.m4a`
- `mic_audio.m4a`

## Permissions / Entitlements

Because App Sandbox is enabled, camera and microphone access require entitlements:

- `CameramanApp/CameramanApp.entitlements`
  - `com.apple.security.device.camera`
  - `com.apple.security.device.audio-input`

## Architecture

### Module Structure (EngineKit/Sources/EngineKit/)

```
Capture/        - Screen/camera recording (CaptureEngine, CameraEngine, Recorder)
                - Permissions (PermissionManager), hotkeys (HotkeyManager)
                - Telemetry (TelemetryRecorder, TelemetryParser, TelemetrySync)
                - Recording quality presets (RecordingQuality)

Editor/         - Non-destructive editing model (EditorModel + EditorModel+SegmentOps)
                - Overlays: arrows, rectangles, text (OverlayEngine)
                - Canvas layouts: PiP, side-by-side (CanvasLayout)

Preview/        - Playback with edits applied (PreviewEngine)
                - Composition building (PreviewComposition + PreviewComposition+StaticClips)
                - Proxy generation for smooth preview (ProxyGenerator)
                - Thumbnail/waveform caching (ThumbnailCache, LRU eviction)
                - Zoom rendering (applyZoom, applyZoomTransform in PreviewRenderer)

Export/         - Async video rendering (ExportEngine, VideoExportSession)
                - GIF export (GIFExportSession via CGImageDestination)
                - Presets: web_1080_h264, portrait, HEVC, animated_gif
                - Per-track audio/video mute state in exports

Zoom/           - Auto-zoom pipeline:
                  DwellDetector → detects cursor pauses (>300ms) as zoom candidates
                  ZoomSuggestionEngine → combines click + dwell into suggestions
                  ZoomPlanGenerator → converts suggestions to keyframed zoom events
                  ZoomSectionController → per-segment zoom config management
                - Easing functions (ZoomEasing)
                - Types: ZoomKeyframe, ZoomEvent, ZoomPlan, ZoomSuggestion

Transcription/  - On-device STT via WhisperKit (CoreML/ANE, Apple Silicon only;
                  TranscriptionEngine + WhisperKitTranscriber, runtime-gated)
                - SRT/VTT caption generation

Intelligence/   - AI service interface (AIService actor)
                - Local analysis: silence detection, chapter suggestion

Shared/         - AudioMixBuilder (per-track volume/mute for preview + export, incl. video-clip audio)
                - CompositionBuilder+VideoOverlayTracks (imported video rows: frames + embedded audio)
                - CompositionBuilder (AVComposition from multi-track timeline)
                - MaskedVideoCompositor (custom AVVideoCompositing: PiP masks, zoom, overlays, per-layer adjustments)
                - CompositorRenderers (mask, background, static content, video effects)
                - AdjustmentRenderer (CoreImage filter chain for clip/layer effects: sepia, B&W, color, blur…)
                - AudioAdjustmentTap (MTAudioProcessingTap + AUNewTimePitch: voice pitch shift)
                - OverlayRenderer (arrow, rect, line, text overlay shapes)

Infrastructure/ - Logging (LoggingSystem), crash reporting (CrashReporter)

Store/          - Project persistence (ProjectStore, summary cache with mod-date invalidation)
                - Project merge (ProjectStore+Merge: B appended after A, media copied, times offset)
                - Portable bundles (ProjectStore+Bundle: export/import .cameramanproject folders)
                - Empty projects (createEmptyProject: import-only editing, no recording)
Queue/          - Background job orchestration (JobQueue)
Library/        - Project listing, search, tags (ProjectLibrary)
Models/         - Core types: Project, Job, Overlay, MediaItem, ZoomConfiguration
                - Timeline: TimelineTrack, TimelineClip, ClipContent (recording/image/video/audio/color)
                - Clip refs: RecordingClipRef, ImageClipRef, VideoClipRef, AudioClipRef, ColorClipRef
                - Effects: Adjustment/AdjustmentKind/AdjustmentTarget on TimelineClip (Project+Adjustment),
                  flattened to AdjustmentConfig (visual) / AudioAdjustmentSpec (audio) for rendering
                - Legacy compat: Timeline.Segment (computed from primary track clips)
```

### Key Design Patterns

1. **Non-destructive editing:** All edits stored in `project.json` metadata; source files never modified
2. **Multi-track timeline:** Typed tracks (primary/video/audio) contain universal clips; ClipContent enum supports recording, image, video, audio, color. Primary track holds recording segments; overlay tracks hold B-roll, images, music. Backward-compatible `segments` accessor on Timeline
3. **Job-based processing:** Export, transcription, proxy generation run as async background jobs
4. **Actor model:** `CaptureEngine`, `CameraEngine`, `PreviewEngine`, `ThumbnailCache` use Swift actors for thread-safe state
5. **Engine/UI separation:** EngineKit exposes stable API; UI layer is replaceable
6. **Zoom pipeline:** Telemetry → Parser (click windows) + DwellDetector (pauses) → ZoomSuggestionEngine (merge/dedup) → ZoomPlanGenerator (keyframes with easing) → PreviewRenderer (frame transform)
7. **Per-track audio:** AudioMixBuilder constructs AVMutableAudioMix with independent volume/mute per track (recording tracks + imported audio clip tracks); used in both preview and export

### Project File Structure

```
Projects/<project_id>/
├── project.json           # Metadata, timeline, overlays, canvas settings
├── sources/               # Raw recordings (screen.mov, camera.mov, audio)
├── telemetry/             # cursor.jsonl, keys.jsonl
├── proxies/               # Low-res versions for preview
├── cache/                 # Thumbnails, waveforms
├── renders/               # Export outputs
└── transcript/            # transcript.json, captions.srt/.vtt
```

### App-Side Key Components (App/Sources/Cameraman/)

```
CameramanApp.swift       - Entry point, Window scenes (single-instance via WindowID)
AppNavigation.swift      - Main split view: sidebar (project list) + detail (editor)
ProjectEditor.swift      - @MainActor wrapper around EditorModel with undo/redo stack
ProjectEditorView.swift  - 3-panel layout: left (settings) + center (preview+timeline) + right (inspector)
PreviewPlayerViewModel   - AVPlayer management, playback rate, per-track volume sliders
TimelineView.swift       - Timeline: tracks, clips with snap/trim/split, playhead, ruler
                           (TimelineRulerView), pinned label column, fit-based zoom
FeatureFlags.swift       - Hidden defaults-backed switches (e.g. feature.autoZoom, default off)
MergeProjectSheet.swift  - Picker for "Merge Into New Project…"
RecordingControlView     - Recording window: source selector, options, start/stop
ScreenAreaSelector.swift - Full-screen overlay for area selection (KeyablePanel + AreaHighlightController)
ExportView/ViewModel     - Export UI with preset selection, GIF options, progress monitoring
```

### Window Architecture

- `Window("Projects", id: WindowID.mainEditor)` — single-instance main editor
- `Window("Recording", id: WindowID.recordingControls)` — single-instance recording controls
- `WindowID` enum centralizes all window identifiers

## Concurrency Model

- Use `async/await` for all I/O operations
- `actor` for mutable shared state (see `AIService`)
- Engine code should be UI-free (no `@MainActor`)

## Error Handling

Use `EngineKitError` enum with context (file paths, timestamps, drift amounts). Distinguish recoverable vs fatal errors for job system.

## Related Documentation

Root-level (open-source basics):

- `README.md` - Public-facing overview, install, build, contribution pointers
- `CONTRIBUTING.md` - Contributor guide: setup, conventions, PR flow
- `LICENSE` - MIT

Inside `docs/`:

- `docs/DEV_ONBOARDING.md` - **Start here** — architecture, setup, key patterns
- `docs/PRD.md` - Product requirements, user flows, MVP scope
- `docs/TECH_SPEC.md` - API contracts, data schemas, sync strategy
- `docs/TASK_TODO.md` - Pending features and improvements
- `docs/TASK_COMPLETED/` - Completed work by session (YYMM.md format)
- `docs/CHANGELOG.md` - Version changelog (current: **v0.6.4**)
- `docs/ARCHIVED/` - Historical docs (recovery summaries, validation reports)
