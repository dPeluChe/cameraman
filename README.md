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
open CameramanApp/CameramanApp.xcodeproj
# Scheme: CameramanApp → My Mac → Cmd+R
```

Requirements: macOS 13+, Xcode 15+. See [DEV_ONBOARDING](docs/DEV_ONBOARDING.md) for full setup, architecture, and known issues.

## Status

**Beta**. Core recording, editing, and export workflows are functional. Overlay system, auto-zoom, and per-segment editing are working. Actively developed.

See [CHANGELOG](docs/CHANGELOG.md) for version history. See [TASK_TODO](docs/TASK_TODO.md) for planned work.

## Built by

[Iteris](https://iteris.tech)
