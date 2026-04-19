# Changelog

All notable changes to Cameraman will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Nota (2026-04-18):** Las versiones fueron renumeradas hacia abajo para reflejar el estado real del producto (aún incompleto). El mapeo aplicado:
> `0.8.0 → 0.5.0` · `0.7.0 → 0.4.1` · `0.6.0 → 0.4.0` · `0.5.0 → 0.3.1` · `0.4.0 → 0.3.0` · `0.3.1 → 0.2.1` · `0.3.0 → 0.2.0` · `0.2.0 → 0.1.1` · `0.1.0 → 0.1.0`.
> Las fechas y el contenido técnico se preservaron.

## [0.5.1] - Unreleased

### Branch
- `refactor/phase1-architecture` — Fase 1: descomposición de `TimelineView` y extracción del export pipeline.

### Added
- `RecordingSession.videoWriterFailed` / `audioWriterFailed` flags + `markVideoWriterFailed(_:)` / `markAudioWriterFailed(_:)` (idempotentes) para detectar escrituras abortadas sin spam de logs.

### Changed
- **TimelineView descompuesto** — `TimelineView.swift` de 864 → 413 LOC. Nuevas extensiones: `TimelineView+Thumbnails.swift` (106 LOC), `TimelineView+DragDrop.swift` (180 LOC), `TimelineView+EditActions.swift` (96 LOC). Métodos de zoom movidos a `TimelineView+ZoomSuggestions.swift`.
- **Export pipeline dividido** — `VideoExportSession.performExport()` de ~480 LOC monolíticas → orquestador de 125 LOC que encadena stages aislados en `VideoExportSession+Stages.swift` (prepare/validate/build/configure/run/verify) y `VideoExportSession+Composition.swift` (rutas fullscreen-camera / standard / per-segment masked separadas).
- `CaptureSessionManager` loguea el `NSError` completo (domain/code/userInfo) del writer en el primer fallo en vez de solo `localizedDescription`.
- Al fallar `AVAssetWriter` durante grabación, se para el stream inmediatamente y no se reintentan más frames (evita spam de 1000+ logs por grabación corrupta).

### Fixed
- **Versionado reescalado** a 0.5.1 — refleja estado real del producto; historia del CHANGELOG renumerada al esquema más conservador.
- **Telemetría de cursor no llegaba al proyecto** — `TelemetryRecorder` anidaba `telemetry/telemetry/cursor.jsonl` dentro del directorio que ya era `/telemetry/`, el `Recorder` buscaba un nivel arriba y nunca encontraba el archivo; `moveRecordingFiles` fallaba silencioso. Consecuencia: **cero sugerencias de zoom** en cualquier proyecto grabado con el flujo actual.
- **Rebuild excesivo de `videoComposition` al abrir un proyecto** — `PreviewEngine.updateProject` ahora corta temprano si el project es idéntico al ya cargado; `PreviewPlayerView` disparaba 10+ rebuilds en cascada por cambios de state no relacionados con la composición visual.
- Warning "Initialization of immutable value 'oldBackground' was never used" en `ProjectEditor.setBackgroundType` — variable sin uso eliminada.
- Dead code removido: `TimelineView.getThumbnailForTime` y `zoomSuggestionGenerator` (nunca referenciados).

## [0.5.0] - 2026-04-12

### Added
- **Multi-track timeline architecture** — replaced flat `segments[]` with typed tracks (`primary`/`video`/`audio`) each containing universal clips
- **Universal clip model** — `ClipContent` enum supporting 5 content types: `.recording`, `.image`, `.video`, `.audio`, `.color`; each with its own ref type (`RecordingClipRef`, `ImageClipRef`, `VideoClipRef`, `AudioClipRef`, `ColorClipRef`)
- **Track-level controls** — per-track `isMuted`, `isLocked`, `volume`, `opacity`
- **EditorModel track/clip operations** — `addTrack`, `removeTrack`, `addClip`, `removeClip`, `updateClip`, `moveClip`, `splitClip` (works on any clip type in any track)
- **Static content rendering** — MaskedVideoCompositor renders images and solid colors for non-recording clips in the primary track (with image cache)
- **Audio clip tracks** — CompositionBuilder creates dedicated audio tracks from timeline audio tracks with per-clip volume
- **Schema v2** — `project.json` now uses `tracks[]` format; auto-migration from v1 `segments[]` on load

### Changed
- **Timeline model** — `Project.Timeline` stores `tracks: [TimelineTrack]` instead of flat `segments: [Segment]`
- **CompositionBuilder** — reads clips from primary track; handles recording, imported video, image/color gaps, and audio clip tracks
- **PreviewComposition** — generates per-clip compositor instructions with `staticContent` for image/color rendering
- **Export pipeline** — ExportEngine, VideoExportSession, GIFExportSession, ExportValidator all use tracks/clips model
- **Project schema version** — bumped to 2

### Fixed
- **`deleteRange` partial overlap** — clips partially overlapping the delete range at either edge are now trimmed correctly (not silently ignored)
- **`deleteRange` for spanning clips** — properly splits any clip type using generic `splitContent`, fixes double-counting of offset adjustment
- **Timeline duration with muted tracks** — muted tracks now contribute to duration (muting hides playback, not timeline extent)
- **Legacy segment ops respect `isLocked`** — trimIn, trimOut, split, delete, addSegment, deleteRange now check primary track lock state
- **Camera instructions for mixed clips** — PreviewComposition iterates all primary track clips (not just recording segments) for per-clip camera overrides
- **Hex color alpha support** — MaskedVideoCompositor now parses 8-character hex colors (e.g. `#FF5500AA`)
- **Stable clip ordering** — segments setter uses deterministic sort (by timelineIn, then by id) to prevent ordering flips
- **Audio clip sync** — clips with volume=0 no longer skipped from composition, preserving timeline alignment

## [0.4.1] - 2026-04-02

### Added
- **Camera border** — configurable width (0–8px) and color (10 presets) on PiP camera overlay
- **Per-segment audio** — volume slider (0–300%) and mute toggle per segment in inspector bar
- **Telemetry recording** — cursor/click telemetry always captured during recording (captureTelemetry=true default)
- **Autosave** — 1s debounced save after every edit via ProjectLibrary
- **Auto-zoom rendering** — zoom plan applied per-frame in MaskedVideoCompositor (scale around focus point)
- **Auto-show zoom suggestions** — markers appear automatically when project has telemetry data
- **Auto-apply zoom plan** — zoom effect active immediately without manual "Apply" button
- **Per-segment export** — export now renders per-segment camera positions, visual effects, and audio

### Fixed
- **Black video after splits** — compositor instructions now guaranteed contiguous (prev.end = next.start)
- **Export ignored per-segment edits** — was using single global instruction; now uses per-segment instructions
- **Audio mute state lost on rebuild** — lastAudioMuteState preserved across light composition rebuilds
- **Camera position reset on move/resize/shape** — PiPLayoutHelper now preserves borderWidth/borderColor
- **Missing undo on volume/mute** — all segment mutations now record undo via generic mutateSegment()
- **Auto-create camera override** — dragging camera with segment selected auto-creates override (no "Custom" button needed)

### Changed
- Zoom suggestion thresholds tuned for lighter recordings (minClicksPerWindow: 2→1, minMovementDistance: 50→20px)
- DwellDetector more sensitive (minDwellDuration: 0.45→0.3s, maxDwellDuration: 2.6→4.0s)
- 11 onChange(of:) calls migrated to macOS 14+ API
- TimelineView body split into extracted sub-views (fixes Swift type-checker timeout)

## [0.4.0] - 2026-04-01

### Added
- **Per-segment camera position** — each segment can override the project camera PiP position; "Customize"/"Reset" controls in segment inspector bar
- **Per-segment speed presets** — speed picker (0.25x–4x) in segment inspector bar; orange speed badge on segments
- **Segment inspector bar** — appears below timeline toolbar when a segment is selected; shows speed + camera controls
- **Media item drag to reposition** — drag gesture with live visual feedback; updates timelineIn on drop
- **Audio drift detection** — `AudioDriftDetector` compares video/audio durations, warns if drift >100ms
- **Compositor visual effects rendering** — gradient backgrounds (CILinearGradient), blur backgrounds (CIGaussianBlur), video corner radius (CIBlendWithMask), video padding (scale+translate)
- **Per-segment composition instructions** — PreviewComposition creates separate instructions per segment when camera positions differ

### Fixed
- **Split bug** — `takeId`, `zoom`, and `cameraPosition` now propagate correctly to both segments on split (were lost before)
- **Blur background layer ordering** — blurred screen now renders behind padded/rounded video content (was on top)
- **`contains(where:)` syntax** in AudioDriftDetector

### Technical
- `PreviewEngine.cameraTransform()` extracted as static helper for reuse between preview and export
- `MaskedVideoCompositionInstruction` now carries visual effect properties (cornerRadius, shadow, padding, background)
- 6 new unit tests for split propagation and segment model backward compatibility

## [0.3.1] - 2026-03-31

### Added
- **4K HEVC export preset** (3840x2160, 60fps, 30Mbps) in export options
- **Duplicate project** — deep copy via context menu, auto-opens the clone
- **Export transcript as TXT/SRT/VTT** — full caption export with NSSavePanel
- **Video effects sidebar** — corner radius (0–16px), shadow intensity (0–100%), padding (0–30%) controls
- **Background gradients** — 8 presets (Sunset, Ocean, Forest, Midnight, Lavender, Ember, Arctic, Slate) in new "Gradient" tab
- **Project thumbnails** — auto-generated JPEG from first frame of screen video on project creation; shown in project list

### Fixed
- **Mic audio race condition** — validates AVAudioEngine format before recording; auto-retry with 300ms delay if format invalid (0 Hz / 0 channels)
- **"Publishing changes from within view updates"** — BackgroundControlsView state mutation deferred with Task
- **onChange macOS 13 compatibility** — 12 instances of macOS 14+ API converted to macOS 13 single-parameter syntax
- **SHA256 placeholders** — replaced 8 "placeholder" values with real CryptoKit SHA256 streaming hashes (64KB chunks, constant memory)
- **Hardcoded video dimensions** — screen and camera tracks now use `detectVideoDimensions()` for actual recorded resolution
- **Timer intervals** — export/keystroke polling reduced to 0.25s; recording elapsed display kept at 0.1s for smooth UX
- **ExportViewModel timer leak** — deinit now invalidates progressUpdateTimer if view dismissed during export

### Technical
- EngineKit passes `-strict-concurrency=complete` with zero warnings
- `ProjectStore.sha256(of:)` uses streaming FileHandle (constant memory for 1GB+ files)
- `ProjectStore.generateThumbnail()` uses AVAssetImageGenerator + CGImageDestination (pure CoreGraphics)

## [0.3.0] - 2026-03-31

### Added
- **Auto-zoom from cursor telemetry** — `DwellDetector` detects cursor pauses (>450ms stationary), `ZoomSuggestionEngine` combines click windows + dwell candidates into unified suggestions. Timeline shows yellow markers for each suggestion; click markers to accept/reject individually. "Apply" creates zoom keyframes and persists zoom config on segments.
- **GIF export options** — when "Animated GIF" preset is selected, ExportView shows GIF-specific controls: frame rate (10/15/24 fps), max size (480/800/1200), loop toggle. Options flow through `GIFExportOptions` to the existing `GIFExportSession` engine.
- New EngineKit files: `DwellDetector.swift`, `ZoomSuggestionEngine.swift`
- `PreviewEngine.setZoomPlan()` public setter for external zoom plan application

### Technical
- `ZoomSuggestionEngine` is a stateless enum with static methods (no actor overhead)
- `ZoomSuggestion.toClickWindow()` unifies coordinate conversion in one place
- Individual suggestion accept/reject via `dismissedSuggestionIds` state set

## [0.2.1] - 2026-03-30

### Performance
- **Fix Task leak in CameraEngine/CaptureEngine** — duration timer now stores a cancellable `Task` handle with `!Task.isCancelled` guard; cancelled explicitly on `stopRecording()`
- **Fix AVPlayer observer leak in PreviewEngine** — `stopPeriodicTimeObservation()` now called before nilling player in `unloadProject()`
- **ThumbnailCache LRU eviction** — enforces `maxThumbnailCount` via access-order tracking; evicts oldest entries when limit exceeded
- **Waveform rendering: GeometryReader+Path → Canvas** — renders directly into graphics context, no SwiftUI view tree; uses `ArraySlice` instead of array copy
- **Thumbnail lookup O(n log n) → O(n)** — replaced `sorted()` + `min(by:)` per render with single linear scan
- **Lazy project list loading** — summary cache with file modification date invalidation; skips re-decoding unchanged `project.json` files. `loadProjects()` debounced (500ms)
- **Deferred thumbnail/waveform generation** — initial open generates 15 thumbnails (was 50); remaining thumbnails + waveforms generated at `.utility` priority in background

## [0.2.0] - 2026-03-25

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

## [0.1.1] - 2026-01-22

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
- **Export logging** - Added comprehensive logging with emojis for easier debugging
- **UI behavior** - Export completion now shows "Done" button instead of "Cancel Export"
- **File management** - Improved handling of existing files before export

### Known Issues
- Exported videos may show black bars/letterboxing (aspect ratio issue)
- Frame counter warnings during recording startup (non-critical)

## [0.1.0] - Initial Release

### Added
- Basic screen recording with ScreenCaptureKit
- System audio capture
- Camera video capture
- Microphone audio capture
- Separate track recording (screen, system audio, camera, mic audio)
- Sandbox-compatible file storage
