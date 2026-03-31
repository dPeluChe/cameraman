# Changelog

All notable changes to Cameraman will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-03-31

### Added
- **Auto-zoom from cursor telemetry** — `DwellDetector` detects cursor pauses (>450ms stationary), `ZoomSuggestionEngine` combines click windows + dwell candidates into unified suggestions. Timeline shows yellow markers for each suggestion; click markers to accept/reject individually. "Apply" creates zoom keyframes and persists zoom config on segments.
- **GIF export options** — when "Animated GIF" preset is selected, ExportView shows GIF-specific controls: frame rate (10/15/24 fps), max size (480/800/1200), loop toggle. Options flow through `GIFExportOptions` to the existing `GIFExportSession` engine.
- New EngineKit files: `DwellDetector.swift`, `ZoomSuggestionEngine.swift`
- `PreviewEngine.setZoomPlan()` public setter for external zoom plan application

### Technical
- `ZoomSuggestionEngine` is a stateless enum with static methods (no actor overhead)
- `ZoomSuggestion.toClickWindow()` unifies coordinate conversion in one place
- Individual suggestion accept/reject via `dismissedSuggestionIds` state set

## [0.3.1] - 2026-03-30

### Performance
- **Fix Task leak in CameraEngine/CaptureEngine** — duration timer now stores a cancellable `Task` handle with `!Task.isCancelled` guard; cancelled explicitly on `stopRecording()`
- **Fix AVPlayer observer leak in PreviewEngine** — `stopPeriodicTimeObservation()` now called before nilling player in `unloadProject()`
- **ThumbnailCache LRU eviction** — enforces `maxThumbnailCount` via access-order tracking; evicts oldest entries when limit exceeded
- **Waveform rendering: GeometryReader+Path → Canvas** — renders directly into graphics context, no SwiftUI view tree; uses `ArraySlice` instead of array copy
- **Thumbnail lookup O(n log n) → O(n)** — replaced `sorted()` + `min(by:)` per render with single linear scan
- **Lazy project list loading** — summary cache with file modification date invalidation; skips re-decoding unchanged `project.json` files. `loadProjects()` debounced (500ms)
- **Deferred thumbnail/waveform generation** — initial open generates 15 thumbnails (was 50); remaining thumbnails + waveforms generated at `.utility` priority in background

## [0.3.0] - 2026-03-25

### Added
- **Per-track volume sliders** in timeline label area (system audio + mic audio), range 0–3x, with live preview update
- **Area selector highlight** — persistent dashed overlay shows selected capture area; hidden when recording stops or source changes
- **Area selector UX** — double-click to confirm selection; instruction bar adapts text based on state; Escape cancels

### Fixed
- **Mic audio error -50** — `AVAudioFile` settings now match `AVAudioEngine` input node native format (channel count + sample rate), eliminating `ExtAudioFileWrite paramErr`
- **Duplicate editor window** — changed main editor from `WindowGroup` (multi-instance) to `Window` (single-instance) so `openWindow` brings existing window to front
- **Project not auto-selected after recording** — removed async yield before `selectedItem` assignment, eliminating race condition
- **Playback speed change required stop/play** — `playbackRate` now has `didSet` that updates `avPlayer.rate` immediately when playing
- **Area highlight visible in recorded video** — added `sharingType = .none` to `AreaHighlightController` overlay window
- **Area highlight persisting after recording stops** — `hide()` now called at start of `stopAndCleanup()`
- **NSPanel keyboard shortcuts broken** — `KeyablePanel: NSPanel` subclass with `canBecomeKey = true` enables Escape and other shortcuts in area selector
- **Timeline segments not filling available width** — `pixelsPerSecond` now scales dynamically to fill the ScrollView viewport

### Changed
- **Mic audio default volume** boosted from 1.0x to 2.5x to compensate for lower mic input levels vs system audio
- **Timeline label width** expanded from 120 to 160px to accommodate volume sliders
- **Track mute icons** differentiated: speaker for audio tracks, eye for video tracks

### Technical
- `WindowID` enum centralizes window ID constants (eliminates string literals)
- `TimelineTrackKind.isAudioTrack` computed property replaces inline checks in 3 places
- `reapplyAudioMix()` reconstructs state from `lastMuteState` (audio only), avoiding unnecessary `applyVideoMutes` calls on volume changes
- GeometryReader state writes deferred with `Task { @MainActor in }` to avoid "Publishing during view update" warning

## [0.2.0] - 2026-01-22

### Added
- **Complete export system** with user-selected save location
- **Export presets**: Web 1080p (H.264), High 1080p (HEVC), Portrait 1080p (H.264), Animated GIF
- **Timeline editor** with drag-and-drop clip management
- **Trim and cut operations** for screen and audio tracks
- **Zoom controls** for timeline navigation
- **Progress tracking** with detailed export stages (validation, loading, composition, export, verification)
- **NSSavePanel integration** for user-controlled file destination
- **Play button** to preview exported video within app
- **Hotkey manager** for recording controls (ExportEngine/HotkeyManager)
- **Recording state manager** with Combine support (RecordingStateManager)

### Fixed
- **Sandbox entitlements** - Added `com.apple.security.files.user-selected.read-write` and `com.apple.security.files.downloads.read-write` for file access
- **Export engine errors** - Improved error logging with domain, code, and userInfo details
- **AVAsset deprecation** - Changed `AVAsset(url:)` to `AVURLAsset(url:)` for macOS 15 compatibility
- **Telemetry controls** - Fixed optional unwrapping issues (TelemetryControlsView)
- **Overlay editor** - Changed file-private access to internal for extensions
- **App delegate imports** - Added missing `EngineKit` import for hotkey registration
- **Recording notifications** - Removed duplicate `openRecordingWindow` declaration
- **Recording control view model** - Added missing imports (Combine, AppKit, CoreVideo)
- **Export view model** - Fixed `temporaryExportURL` path construction to use correct project directory
- **Export view** - Fixed cancel button to properly close modal
- **Video export session** - Added detailed directory and file permission verification
- **Save panel** - Ensured .mp4 extension is added to user-selected files
- **Progress monitoring** - Fixed state updates to prevent UI freezing

### Changed
- **Export workflow** - Files are now exported to temporary location within sandbox, then user saves to desired location via save panel
- **Export logging** - Added comprehensive logging with emojis (🎬) for easier debugging
- **UI behavior** - Export completion now shows "Done" button instead of "Cancel Export"
- **File management** - Improved handling of existing files before export

### Technical Improvements
- **VideoExportSession**:
  - Added `shouldOptimizeForNetworkUse = true` for better export performance
  - Added detailed error reporting with AVAssetExportSession status descriptions
  - Added verification of output directory existence and write permissions
  - Added immediate file existence check after export completion
  - Improved error messages with domain, code, and userInfo details

- **ExportViewModel**:
  - Added `temporaryExportURL` and `showSavePanel` state management
  - Implemented `saveExportToFile()` with NSSavePanel integration
  - Fixed `projectDirectory` parameter passing from ExportView
  - Added delay before showing save panel for proper UI updates

- **ExportView**:
  - Added "Play Video (Temporary)" button for immediate preview
  - Fixed cancel button behavior to change to "Done" after completion
  - Improved user feedback with detailed progress messages
  - Added comprehensive logging for debugging

### Known Issues
- Exported videos may show black bars/letterboxing (aspect ratio issue)
- Frame counter warnings during recording startup (non-critical)

## [0.1.0] - Previous Release

### Added
- Basic screen recording with ScreenCaptureKit
- System audio capture
- Camera video capture
- Microphone audio capture
- Separate track recording (screen, system audio, camera, mic audio)
- Sandbox-compatible file storage
