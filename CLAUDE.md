# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Project Studio** (codename: labs-cameraman) is a macOS local-first screen recording and video editing application. It captures screen, camera, and audio as separate tracks, enables non-destructive editing, and exports to common video formats.

- **Platform:** macOS 13+ (Ventura required for ScreenCaptureKit system audio)
- **Language:** Swift 5.9+
- **Architecture:** EngineKit (Swift Package) + SwiftUI App

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

## Architecture

### Module Structure (EngineKit/Sources/EngineKit/)

```
Capture/        - Screen/camera recording (CaptureEngine, CameraEngine, Recorder)
                - Permissions (PermissionManager), hotkeys (HotkeyManager)
                - Telemetry (TelemetryRecorder, TelemetryParser, TelemetrySync)

Editor/         - Non-destructive editing model (EditorModel)
                - Overlays: arrows, rectangles, text (OverlayEngine)
                - Canvas layouts: PiP, side-by-side (CanvasLayout)

Preview/        - Playback with edits applied (PreviewEngine)
                - Proxy generation for smooth preview (ProxyGenerator)
                - Thumbnail/waveform caching (ThumbnailCache)

Export/         - Async video rendering (ExportEngine)
                - Presets: web_1080_h264, portrait, HEVC

Transcription/  - Offline STT via Whisper.cpp (TranscriptionEngine)
                - SRT/VTT caption generation

Intelligence/   - AI service interface (AIService actor)
                - Local analysis: silence detection, chapter suggestion

Infrastructure/ - Logging (LoggingSystem), crash reporting (CrashReporter)

Store/          - Project persistence (ProjectStore)
Queue/          - Background job orchestration (JobQueue)
Library/        - Project listing, search, tags (ProjectLibrary)
Models/         - Core types: Project, Job, Segment, Overlay
```

### Key Design Patterns

1. **Non-destructive editing:** All edits stored in `project.json` metadata; source files never modified
2. **Segment-based timeline:** Edits represented as segments with `source_in/out` and `timeline_in`
3. **Job-based processing:** Export, transcription, proxy generation run as async background jobs
4. **Actor model:** `AIService` uses Swift actors for thread-safe state
5. **Engine/UI separation:** EngineKit exposes stable API; UI layer is replaceable

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

## Concurrency Model

- Use `async/await` for all I/O operations
- `actor` for mutable shared state (see `AIService`)
- Engine code should be UI-free (no `@MainActor`)

## Error Handling

Use `EngineKitError` enum with context (file paths, timestamps, drift amounts). Distinguish recoverable vs fatal errors for job system.

## Related Documentation

- `prd.md` - Product requirements, user flows, MVP scope
- `tech-spec.md` - API contracts, data schemas, sync strategy
- `tasks.md` - Development backlog organized by épicas (A-L)
