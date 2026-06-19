# App Store Metadata — Cameraman

Copy-paste ready for App Store Connect.
Fields marked ⚠️ need a URL before submitting.

---

## Identity

| Field | Value |
|---|---|
| **App Name** | Cameraman |
| **Subtitle** | Screen recorder for macOS |
| **Bundle ID** | dev.dpeluche.CameramanApp |
| **SKU** | cameraman-macos-2026 |
| **Primary Category** | Video |
| **Secondary Category** | Productivity |
| **Copyright** | © 2026 dPeluChe |

---

## Description (4000 chars max)

```
Cameraman is a native macOS screen recorder built for developers,
designers, and creators who want full control over their recordings
— without subscriptions, cloud uploads, or black boxes.

Record your screen, webcam, and audio simultaneously as independent
tracks. Edit non-destructively on a multi-track timeline: trim,
split, reorder, apply effects, and import your own footage — without
ever touching the original files. Annotate with arrows, text, and
images. Transcribe on-device, and export to MP4, HEVC, or GIF.

Everything stays on your Mac. No account required.

──────────────────────────
CAPTURE
──────────────────────────
• Record screen, camera, and microphone simultaneously
• System audio capture (macOS 13+)
• Select a specific area or record full screen
• Separate tracks for each source — edit them independently

──────────────────────────
EDIT
──────────────────────────
• Non-destructive timeline — original files are never modified
• Trim, split, cut, and reorder clips with magnetic snapping
• Import your own videos, images, and music onto their own tracks
• Picture-in-picture and side-by-side camera layouts
• Per-track volume control and mute
• Zoom effects with auto-detection of cursor dwell and clicks
• Merge projects and share them as portable bundles

──────────────────────────
EFFECTS
──────────────────────────
• Per-clip color filters: sepia, black & white, brightness,
  contrast, saturation, vibrance, hue, invert, vignette, blur
• Audio pitch shift for voice
• Target a single layer (screen / camera / background) over a range

──────────────────────────
ANNOTATE
──────────────────────────
• Add arrows, rectangles, lines, and text overlays
• Import images and animated GIFs as overlays
• Drag overlays directly on the preview to reposition
• Fade in / fade out animations per overlay
• Full style control: color, stroke, size, shadow

──────────────────────────
EXPORT
──────────────────────────
• MP4 (H.264), HEVC (H.265), and animated GIF
• Choose resolution, quality, and destination folder
• GIF export with custom frame rate and palette

──────────────────────────
TRANSCRIBE
──────────────────────────
• On-device speech-to-text (Apple Silicon) — nothing is uploaded
• Generate SRT / VTT captions from your recording's audio

──────────────────────────
AUTOMATE (FOR DEVELOPERS)
──────────────────────────
• Built-in MCP server lets AI assistants (Claude, Codex) create,
  edit, and export your projects — all locally on your Mac

──────────────────────────
OPEN SOURCE
──────────────────────────
Cameraman is open source under the MIT license.
Inspect the code, contribute, or extend it for your own workflow.
github.com/dPeluChe/cameraman

Built with Swift and SwiftUI. Runs entirely on your Mac.
```

**Char count:** ~2,100 — well within the 4,000 limit.

---

## Promotional Text (170 chars — updatable without new build)

```
Native macOS screen recorder. Record, annotate, and export — no subscriptions, no cloud. Open source and built to stay on your Mac.
```

---

## Keywords (100 chars max, comma-separated)

```
screen recorder,screencast,video editor,webcam,transcription,captions,annotation,effects,tutorial
```

**Char count:** 97 ✓

---

## What's New — v0.7.0

```
• Per-clip effects: color filters (sepia, B&W, brightness, contrast,
  saturation, blur…) and audio pitch, applied per layer
• On-device transcription with SRT/VTT captions (Apple Silicon)
• Import videos, images, and music onto their own timeline tracks;
  merge projects and share them as portable bundles
• Built-in MCP server: drive Cameraman from AI assistants (Claude,
  Codex) to create, edit, and export projects — all locally
• Faster, cleaner UI: live project refresh, more discoverable export
  presets, and more reliable clicks throughout Settings
```

### What's New — v0.6.1 (previous)

```
• Security hardening: stricter URL validation when checking for
  updates, private logging by default, and minimum-needed sandbox
  entitlements
• Internal cleanup and documentation polish ahead of public release
```

### What's New — v0.6.0 (previous)

```
• New overlay system: drag arrows, text, and images directly on the
  video preview to reposition them
• Animated GIF overlays with automatic frame sync
• Fade in / fade out animations per overlay
• Help menu with GitHub, bug reports, and support links
• Check for Updates from the menu bar
• Settings redesigned with About tab and donation links
```

---

## URLs

| Field | URL | Status |
|---|---|---|
| **Support URL** | https://github.com/dPeluChe/cameraman | ✅ Ready |
| **Marketing URL** | *(leave blank until landing is live)* | ⏳ Pending |
| **Privacy Policy URL** | ⚠️ Needs a hosted page | ⚠️ Required |

---

## Privacy Policy (minimum viable — host this before submitting)

Host this at a public URL (GitHub Pages, Notion, or the landing site):

> The full, hostable version lives at [`docs/PRIVACY_POLICY.md`](PRIVACY_POLICY.md).

```
Privacy Policy — Cameraman

Last updated: June 2026

Cameraman does not collect, transmit, or share any personal data.

All recordings, projects, and files are stored locally on your Mac.
No account is required to use the app.

The app accesses your camera, microphone, and screen solely to
perform screen recording as requested by you. This data is never
uploaded or shared.

Speech-to-text transcription runs entirely on-device; audio is
never sent to any server.

Cameraman checks for software updates by querying the public
GitHub releases API (github.com/dPeluChe/cameraman/releases).
No personal information is included in this request.

Contact: antonio@dpeluche.dev
```

---

## Reviewer Notes (paste in App Store Connect → Review Notes)

```
Cameraman requires Screen Recording, Camera, and Microphone
permissions to function. These permissions are requested on first
use via macOS system dialogs.

To test the core flow:
1. Click "New Recording" in the toolbar
2. Grant screen recording permission when prompted
3. Start a short recording and stop it
4. The recording will appear in the project library

No login or account is required. The app works fully offline.
```

---

## App Store Screenshots (macOS)

Required sizes: **1280×800** or **1440×900** (at least 1, up to 10)

Suggested shots:
1. Project library with a project loaded
2. Timeline with overlays visible
3. Overlay being dragged on the preview
4. Export modal with settings
5. About / Settings panel

*(Generate these once the Apple Developer account is confirmed.)*
