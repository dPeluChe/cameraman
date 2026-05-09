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

## Beta packaging (`.dmg`)

Single command to produce a universal (arm64 + x86_64) `.dmg` ready to ship to testers:

```bash
make release
```

This runs **build → verify → dmg** in one pass:
1. Compiles a universal Release build
2. Validates the binary contains both architectures (aborts otherwise)
3. Packages `dist/Cameraman-beta-X.Y.Z.B.dmg` with the branded background and an *Applications* drop link

### Other targets

| Command | When to use |
|---------|-------------|
| `make release` | Default — full beta pipeline (build + verify + dmg) |
| `make build` | Universal Release build only (no DMG) |
| `make build-arm` | Native arm64-only build for fast local iteration |
| `make verify` | Confirm an existing build is universal |
| `make dmg` | Re-package the existing build (e.g. after editing the DMG background) |
| `make clean` | Remove `dist/` and `CameramanApp/build/` |
| `make help` | List all targets |

### Distribution caveats

The `.dmg` is **not signed with a Developer ID nor notarized**, so testers will hit a Gatekeeper warning on first launch:

- **macOS 14 and earlier:** right-click the app in `/Applications` → **Open** → confirm.
- **macOS 15 (Sequoia) and later:** double-click → System Settings → **Privacy & Security** → **Open Anyway**.

After the first authorized open, the app launches normally. To remove the warning entirely, the app needs an Apple Developer Program subscription, code signing with a Developer ID Application certificate, and notarization via `xcrun notarytool`.

### Requirements

- `create-dmg` — install with `brew install create-dmg`

## Status

**Beta**. Core recording, editing, and export workflows are functional. Overlay system, auto-zoom, and per-segment editing are working. Actively developed.

See [CHANGELOG](docs/CHANGELOG.md) for version history. See [TASK_TODO](docs/TASK_TODO.md) for planned work.

## Built by

[Iteris](https://iteris.tech)
