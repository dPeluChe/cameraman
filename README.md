# Cameraman

Open source screen recorder & editor for macOS. Swift native. Local-first. Free.

**Version**: 0.5.1 (dev) | **Platform**: macOS 13+ (Ventura) | **License**: Open Source

## What it does

Record your screen, camera, and audio as separate tracks. Edit with a timeline editor. Export with per-segment effects and smart auto-zoom.

### Recording
- Screen capture via ScreenCaptureKit
- Camera (webcam) overlay
- System audio + microphone (separate tracks)
- Cursor/click telemetry for auto-zoom

### Editing
- Timeline with trim, split, delete, drag-and-drop
- Per-segment speed control (0.25x-4x)
- Per-segment camera PiP positioning with borders (circle, rounded rect, capsule)
- Per-segment audio volume (0-300%) and mute
- Overlays: arrows, rectangles, lines, text with timing controls
- Canvas effects: background gradients, blur, padding, corner radius
- Auto-zoom suggestions from cursor telemetry (click + dwell detection)
- Undo/redo with autosave
- Non-destructive editing (source files never modified)

### Export
- **Web 1080p (H.264)** — optimized for web sharing
- **High 1080p (HEVC)** — smaller files, better quality
- **4K (HEVC)** — 3840x2160, 60fps
- **Portrait 1080p (H.264)** — vertical format
- **Animated GIF** — configurable fps, size, loop
- Per-segment camera positions, visual effects, and audio included in export

## Build & Run

```bash
# Clone
git clone https://github.com/anthropics/labs-cameraman.git
cd labs-cameraman

# Open in Xcode
open CameramanApp/CameramanApp.xcodeproj
# Select scheme "CameramanApp" → Run on "My Mac"

# Or build EngineKit standalone
cd EngineKit && swift build
```

**Requirements**: macOS 13+, Xcode 15+. Grant Screen Recording, Camera, and Microphone permissions when prompted.

## Architecture

```
App/Sources/Cameraman/     — SwiftUI app layer (~16K LOC)
EngineKit/Sources/          — Modular engine (~22K LOC)
  Capture/                  — Screen/camera/mic recording, telemetry
  Editor/                   — Non-destructive editing model
  Preview/                  — Playback with edits, proxy generation
  Export/                   — Video/GIF export with presets
  Zoom/                     — Auto-zoom pipeline (dwell + click detection)
  Shared/                   — Compositor, audio mix builder
```

Total: ~38.6K LOC implementation, ~32.2K LOC tests.

## Permissions

App Sandbox is enabled. Required entitlements:
- `com.apple.security.device.camera`
- `com.apple.security.device.audio-input`
- `com.apple.security.files.user-selected.read-write`
- `com.apple.security.files.downloads.read-write`

Info.plist usage strings: `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSScreenCaptureUsageDescription`.

## Status

**Beta**. Core recording, editing, and export workflows are functional. Overlay system, auto-zoom, and per-segment editing are working. Actively developed.

See [CHANGELOG](dev-docs/CHANGELOG.md) for version history. See [TASK_TODO](dev-docs/TASK_TODO.md) for planned work.

## Built by

[Iteris](https://iteris.tech)
