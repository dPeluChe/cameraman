# Cameraman

> Open-source screen recorder and video editor for macOS. Swift native. Local-first. Free.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](https://www.apple.com/macos/)
[![Swift 5.9+](https://img.shields.io/badge/swift-5.9%2B-orange.svg)](https://swift.org)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)
[![Landing](https://img.shields.io/badge/landing-cameraman.dev-blue.svg)](https://cameraman.dev)

**Version**: 0.7.0 (beta) · **Platform**: macOS 13+ (Ventura)

> **Landing page:** the marketing site lives in a separate repo —
> [`dPeluChe/cameraman-landing`](https://github.com/dPeluChe/cameraman-landing)
> (React 19 + Tailwind 4 + framer-motion, deployed to [cameraman.dev](https://cameraman.dev) via Vercel).
> Features an animated editor mockup, bento feature grid with honest status badges
> (shipped / being tuned / improving), MCP agent chat mock, and comparison table.
> The static `docs/index.html` previously used for GitHub Pages is superseded
> but kept for backwards compatibility.

---

## What it does

Cameraman captures your screen, camera, and audio as **separate tracks**, gives you a non-destructive timeline editor on top, and exports to standard video formats. Everything happens locally — nothing leaves your machine.

### Recording
- Screen capture via ScreenCaptureKit
- Camera (webcam) overlay
- System audio + microphone (separate tracks)
- Cursor/click telemetry for auto-zoom

### Editing
- Multi-track timeline (trim, split, delete, drag-and-drop)
- Per-segment speed control (0.25× – 4×)
- Per-segment camera PiP positioning with borders (circle, rounded rect, capsule)
- Per-segment audio volume (0–300%) and mute
- Overlays: arrows, rectangles, lines, text with timing controls
- Per-clip effects: extensible, non-destructive adjustments (sepia, B&W, brightness/contrast/saturation, vibrance, hue, invert, vignette, blur; audio pitch) targetable to a layer (screen / camera / background) over a time range — applied in preview and export
- Canvas effects: background gradients, blur, padding, corner radius
- Auto-zoom suggestions from cursor telemetry (click + dwell detection)
- Import external videos (with their audio) onto their own timeline rows — magnetic snap, trim, split, PiP positioning, row reorder
- Merge two projects into a new one (B appended after A)
- Empty projects: edit imported clips without recording anything
- Undo/redo with autosave
- Non-destructive — source files are never modified

### Export
- **Web 1080p (H.264)** — optimized for web sharing
- **High 1080p (HEVC)** — smaller files, better quality
- **4K (HEVC)** — 3840×2160, 60fps
- **Portrait 1080p (H.264)** — vertical format
- **Animated GIF** — configurable fps, size, loop
- Quality control (smaller file / standard / higher quality) with a live size estimate
- Per-segment camera positions, visual effects and audio are all preserved in export
- Share whole projects between machines as portable `.cameramanproject` bundles

### Transcription
- On-device speech-to-text (WhisperKit, Apple Silicon) with a model picker, generating SRT/VTT captions

### Automate (MCP server)
- A built-in **MCP server** (`cameraman-mcp`, bundled and signed inside the app) exposes Cameraman to AI assistants (Claude Desktop/Code, Codex) over stdio JSON-RPC — **42 tools** to create/edit/record projects, add and edit clips/tracks/overlays/effects, set the canvas, transcribe, and **export** (with job polling). Register it from Settings → Integrations. See [`MCPServer/README.md`](MCPServer/README.md).

---

## Install (beta)

Pre-built `.dmg` releases are published to [GitHub Releases](https://github.com/dPeluChe/cameraman/releases) (when available).

The beta `.dmg` is **not signed with a Developer ID nor notarized** — testers will hit a Gatekeeper warning on first launch:

- **macOS 14 and earlier:** right-click the app in `/Applications` → **Open** → confirm.
- **macOS 15 (Sequoia) and later:** double-click → System Settings → **Privacy & Security** → **Open Anyway**.
- **macOS 26 (Tahoe):** the dialogs above don't bypass quarantine on Tahoe; run once in Terminal:
  ```bash
  xattr -dr com.apple.quarantine /Applications/CameramanApp.app
  ```

After the first authorized open, the app launches normally.

---

## Build from source

Requirements: macOS 13+, Xcode 15+, Swift 5.9+.

```bash
git clone https://github.com/dPeluChe/cameraman.git
cd cameraman
open CameramanApp/CameramanApp.xcodeproj
# Scheme: CameramanApp → My Mac → Cmd+R
```

For full setup, architecture and patterns see [`docs/DEV_ONBOARDING.md`](docs/DEV_ONBOARDING.md).

### Beta packaging (`.dmg`)

One command produces a universal (arm64 + x86_64) `.dmg` ready to ship:

```bash
make release
```

This runs **build → verify → dmg** in one pass:
1. Compiles a universal Release build
2. Validates that the binary contains both architectures (aborts otherwise)
3. Packages `dist/Cameraman-beta-X.Y.Z.B.dmg` with the branded background and an *Applications* drop link

| Command | When to use |
|---------|-------------|
| `make release` | Default — full beta pipeline (build + verify + dmg) |
| `make build` | Universal Release build only (no DMG) |
| `make build-arm` | Native arm64-only build for fast local iteration |
| `make verify` | Confirm an existing build is universal |
| `make dmg` | Re-package the existing build (e.g. after editing the DMG background) |
| `make clean` | Remove `dist/` and `CameramanApp/build/` |
| `make help` | List all targets |

Requirement: `brew install create-dmg`.

To remove the Gatekeeper warning entirely the app would need an Apple Developer Program subscription, a Developer ID Application certificate, and notarization via `xcrun notarytool`.

---

## Architecture (at a glance)

```
cameraman/                         # this repo — the macOS app + engine
├── App/                           # SwiftUI app (CameramanApp scheme)
├── CameramanApp/                  # Xcode project, entitlements, assets
├── EngineKit/                     # Pure Swift package — engine code (UI-free)
│   ├── Capture/                   # Recording, permissions, telemetry
│   ├── Editor/                    # Non-destructive editing model + overlays
│   ├── Preview/                   # Playback with edits applied
│   ├── Export/                    # Async rendering pipeline + presets
│   ├── Zoom/                      # Auto-zoom from cursor telemetry
│   ├── Transcription/             # Offline STT (WhisperKit)
│   └── Shared/Models/Store/       # Cross-cutting code + persistence
├── MCPServer/                     # MCP server (cameraman-mcp, 42 tools)
├── docs/                          # CHANGELOG, PRD, TECH_SPEC, DEV_ONBOARDING, TASK_*
│   ├── index.html                 # Legacy static landing (superseded by cameraman-landing)
│   └── branding/                  # App icon, wordmark, DMG background
├── scripts/build-dmg.sh
└── Makefile

cameraman-landing/                 # separate repo — cameraman.dev
└── (React 19 + Tailwind 4 + framer-motion, deployed via Vercel)
```

Key design choices:

- **Non-destructive editing** — all edits live in `project.json`; source media is read-only.
- **Multi-track timeline** — typed tracks (primary/video/audio) holding universal clips (`recording`, `image`, `video`, `audio`, `color`).
- **Engine/UI separation** — `EngineKit` exposes a stable API; the SwiftUI layer is replaceable.
- **Actor model** — `CaptureEngine`, `CameraEngine`, `PreviewEngine`, `ThumbnailCache` use Swift actors for thread-safe state.
- **Job-based processing** — export, transcription and proxy generation run as async background jobs.

For details see [`docs/DEV_ONBOARDING.md`](docs/DEV_ONBOARDING.md) and [`docs/TECH_SPEC.md`](docs/TECH_SPEC.md).

---

## Contributing

We welcome contributions! Bug reports, feature requests, docs improvements, code — all are appreciated. Read [`CONTRIBUTING.md`](CONTRIBUTING.md) to get set up and learn the conventions. The current backlog lives in [`docs/TASK_TODO.md`](docs/TASK_TODO.md).

Quick tips:

- **Pick a `fix/`, `feat/`, `perf/`, `refactor/`, `docs/` or `chore/` branch prefix.**
- **Keep PRs focused** — one logical unit of work each.
- **Engine code is UI-free.** Don't add SwiftUI / AppKit dependencies inside `EngineKit/`.
- **Files cap at ~400–500 LOC.** Split with extensions when growing.
- **Write the `why`, not the `what`** in comments and commit bodies.

---

## Status

**Beta**. Core recording, editing, and export workflows are functional. Overlay system, auto-zoom and per-segment editing are working. Actively developed.

See [`docs/CHANGELOG.md`](docs/CHANGELOG.md) for version history. See [`docs/TASK_TODO.md`](docs/TASK_TODO.md) for planned work.

---

## License

[MIT](LICENSE) — © 2026 Antonio Martinez Quintero (dPeluChe).

---

## Built by

[dPeluChe](https://github.com/dPeluChe) — independent developer building tools at [dpeluche.dev](https://dpeluche.dev).
