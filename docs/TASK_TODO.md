# Task Backlog

> Updated: 2026-07-13
> Only unfinished work. Completed work lives in `TASK_COMPLETED/`.
> Ordered by impact and proximity to release, not chronology.

---

## Recently Closed

June 2026 (0.7.0 push): MCP automation server (42 tools), transcription + MCP integration settings (bundled/signed server), per-clip effects UI, live project refresh, import-only export + readable export errors, multi-track `delete_range`. Full write-up in `TASK_COMPLETED/2606.md` (§ 0.7.0).
June 2026 (0.6.4 push): merge projects, video import with full clip editing (snap/trim/split/PiP/reorder), empty projects, timeline ruler + fit zoom + pinned labels, rename fix, mixed-resolution rendering, preview-toggle audit. Full write-ups in `TASK_COMPLETED/2606.md`.
May 2026 (pre-publication push): ultrawide writer fix, mic overload, telemetry streaming, security audit, repo publication. Write-ups in `TASK_COMPLETED/2605.md`.

---

## Bugs & Stability

> Real defects to clear before / during pre-release. None block App Store submission today, but each adds friction.

- [ ] **Pure-static projects don't export** — a project with only image/color cards (no recording and no imported video) can't render: `AVAssetExportSession` (and the GIF frame extractor) need real video samples, so an all-synthetic composition yields "Operation Stopped". Today it's rejected up front with a clear message (`ExportError.noVideoFrames`). To support pure slideshows, synthesize a base video track (render the canvas background/cards to real frames via `AVAssetWriter`, or scale a 1-frame solid clip to the duration) instead of padding the primary with an empty range. ~100 LOC, gate to the no-real-video case. Low impact: any real video clip already makes the project exportable.
- [ ] **PiP camera overlay drag-to-reposition during playback** — historically only worked when paused. Likely resolved by the earlier `fix/pip-drag-playback-and-logs-cleanup` work (`draftCamera` @State pattern) and the throttle change in PR #15. Verify on a fresh build before closing.
- [ ] **Warning: "Publishing changes from within view updates is not allowed" on project load** — fires once when opening a project in the editor; benign at runtime, no crash. Three prior fix attempts (`80cfa4e`, `1102beb`, `a08fadf`) were insufficient or regressed. Candidates not yet ruled out: `ProjectEditorViewModel.loadProject`, the toast `Binding(get:set:)` in `ProjectEditorView` line 164, or some mutation in the `.task` chain of `AppNavigation`. Needs runtime instrumentation (breakpoints or `os_log` around the first `objectWillChange.send()`) to locate the real emitter.
- [ ] **`NSHostingView is being laid out reentrantly` / `AttributeGraph: cycle detected` (~150 entries)** — observed once when bumping the PiP throttle to 60Hz; that commit was reverted. Watch for recurrence; if it returns, investigate cyclic dependency between `PreviewPlayerView` (observing `viewModel.avPlayer`), `PiPCanvasEditor` (pushing to `engine.updateProject`), and SwiftUI's view-update graph. Symptom in the affected run: export took 14s vs. the usual 5.4s (~3× slowdown).
- [x] **Telemetry: count `-10877` errors per session, correlate with `writer.status`** `done: 2026-07-08` — `RecordingSession.errorCounts` tracks per-code errors; `CaptureEngine` logs `AVAssetWriter` error codes via `LogWarning`. PR #42.
- [ ] **UI debug: `Attempting to update all DD element frames, but bounds W:0 H:0`** — appears once during preview. Probably system Drag & Drop or RealityKit, not our code. Low priority; reproduce with the view debugger if it returns.
- [ ] **Noisy system logs in release builds** — Messages VFX entity remaps, `MLE5Engine disabled`, `ViewBridge to RemoteViewService Terminated`, `AddInstanceForFactory: No factory registered`, `AudioQueueObject Error -4 getting reporterIDs`. None are ours but they drown out useful signal. Audit `LoggingSystem` levels: anything at `info` / `notice` in `capture` / `preview` / `export` that should be `debug`.

---

## Direct Visual Editing in the Player — Priority 0

> Primary editor UX direction: visual elements should be selected and manipulated on the video itself, with the timeline and inspector kept in sync. Build this as one shared interaction system instead of separate ad-hoc canvases.

- [ ] **Unified direct-manipulation layer over the player** `added: 2026-07-13`:
    - Define stable selection and hit-testing for overlays, camera PiP, positioned image/video clips, subtitles, and future blur regions.
    - Use one normalized coordinate-space conversion shared by player interaction, project metadata, preview composition, and export.
    - Click an element in the player to select it; synchronize selection with its timeline row and inspector section.
    - Drag to move; handles resize, rotate, and crop where supported. Add aspect lock, alignment guides, snapping, safe areas, keyboard nudging, and clear selected/hover states.
    - Make edits responsive during playback without causing `AttributeGraph` cycles or rebuilding the complete composition for every pointer event; commit one undo/autosave entry when interaction ends.
    - Validate that player placement exactly matches paused preview, playback, thumbnails, and final export at every canvas aspect ratio.
- [ ] **Direct overlay editing in the player** `added: 2026-07-13` — first consumer of the unified layer:
    - Current baseline: select arrow/rect/line/text/image overlays on the real frame and synchronize selection with the timeline.
    - Current baseline: move, scale, and rotate with on-canvas handles; publish responsive preview drafts and commit one undo entry when interaction ends.
    - Current baseline: shared top-left normalized coordinates across player interaction, compositor preview, frame preview, and export.
    - Current baseline: snap to canvas center and 5% safe-area edges, show canvas/safe-area guides, keep rotated overlays in bounds, and nudge 1 px (10 px with Shift+arrow).
    - [ ] Add multi-element alignment/distribution, crop handles where supported, and contextual style access.
- [ ] **Direct PiP and positioned-media editing in the player** `added: 2026-07-13` — migrate the existing PiP drag behavior to the shared interaction layer, then expose move/resize/crop/mask for imported image/video clips.
- [ ] **Direct subtitle and blur-region editing in the player** `added: 2026-07-13` — select cues/regions on-canvas, move/resize their visual bounds, edit subtitle text/style, and preserve their time ranges.
- [ ] **Player interaction test matrix** `added: 2026-07-13`:
    - Current coverage: coordinate transforms for 16:9, 9:16, and 1:1 canvases; center/safe-area snapping and rotated canvas bounds.
    - [ ] Unit-test rotated hit-testing; integration-test undo/autosave, playback edits, mixed resolutions, and preview/export parity.

---

## MCP & Agent Editing Roadmap

> Audit from 2026-07-13. First make autonomous edits safe and recoverable; then improve agent context, feedback, and feature coverage.

### Priority 0 — Correctness and data safety

- [ ] **Cross-process project revision and conflict protection** `added: 2026-07-13` — make `project.json` writes atomic and introduce a monotonic revision / compare-and-swap precondition. App and MCP must detect stale state instead of silently overwriting each other; refresh open editors when an external revision changes.
- [ ] **Repair MCP AI suggestion paths and complete the result flow** `added: 2026-07-13` — make `AIService` use `ProjectStore.baseDirectory` / `CAMERAMAN_PROJECTS_DIR`; add `get_suggestions`, `apply_suggestions(ids)`, and `dismiss_suggestions`; include result metadata in completed jobs.
- [ ] **Enforce editing invariants through EngineKit** `added: 2026-07-13` — reject edits and moves on locked tracks; validate non-negative timeline positions, positive speed/duration, valid source windows, opacity/volume bounds, effect ranges, canvas positions, and overlay timing. The same validation must protect UI and MCP.
- [ ] **Make asset staging collision-safe and transactional** `added: 2026-07-13` — use content-addressed or unique filenames instead of replacing an existing same-name asset; clean staged files when the following edit fails; validate file type and size before copying.
- [ ] **Restore and expand the MCP test suite** `added: 2026-07-13` — update the stale 50→43 tool inventory test, then cover JSON-RPC lifecycle/errors, every mutating tool family, locks/validation, configured project directories, jobs, asset collisions, concurrent app/MCP revisions, and end-to-end edit→preview→export flows.

### Priority 1 — Agent-grade API

- [ ] **MCP protocol conformance hardening** `added: 2026-07-13` — negotiate only supported protocol versions; validate JSON-RPC and request params; return protocol errors for malformed calls/unknown tools; enforce initialization state; add strict schemas with bounds and `additionalProperties: false`.
- [ ] **Structured tool results and safety annotations** `added: 2026-07-13` — add `outputSchema`, `structuredContent`, stable IDs/revisions/warnings, and `readOnlyHint` / `destructiveHint` / `idempotentHint`. Preserve serialized text results for older clients.
- [ ] **Transactional agent editing with dry-run and diff** `added: 2026-07-13` — support `begin_edit`, batched operations, `preview_diff`, `commit_edit`, and `rollback_edit`; report affected clips, duration changes, validation warnings, and one undoable commit.
- [ ] **Checkpoints, undo, and recoverable deletion for agents** `added: 2026-07-13` — expose checkpoint/revert and move project deletion to Trash or a recoverable tombstone instead of immediate irreversible removal.
- [ ] **Compact, queryable project context** `added: 2026-07-13` — add timeline summaries plus track/time-range filters and pagination so agents do not need the complete project, transcript, subtitles, and overlays for every edit.
- [ ] **Visual feedback tools for agents** `added: 2026-07-13` — reuse `PreviewFrameExtractor` / `ThumbnailCache` to expose `render_frame`, contact sheets, thumbnails, and waveform summaries. Return resource links or image content so an agent can inspect the result before committing/exporting.
- [ ] **Persistent and observable jobs** `added: 2026-07-13` — persist export/transcription/AI job state across server restarts; return output paths/results; add progress events where supported and structured audit logs with client, tool, project, revision, duration, and sanitized result/error.

### Priority 2 — MCP feature parity

- [ ] **Expose remaining editor controls to agents** `added: 2026-07-13` — manual zoom keyframes, clip position/size/crop, subtitle cue/style editing, chapter CRUD/application, voiceover recording, screen/window/app/camera source selection, and recording pause/resume.
- [ ] **Evaluate MCP resources and prompts after the mutation API stabilizes** `added: 2026-07-13` — use resources for project/timeline/render artifacts and prompts for safe common workflows; defer experimental MCP Tasks until they materially improve the existing job model.

---

## UX Polish

> Small, low-risk improvements. None change product direction.

- [ ] **Rerun last export (`⌘⇧E`)** — needs feature work, not just a shortcut: persist the last export's preset/destination/options and re-trigger without opening the dialog. (`⌘E` opens export, `⌘↵` runs it in the dialog, `⌘N` opens recording — all exist.)

> Closed in `fix/ux-polish` (June 2026): clickable hit-area on custom selectors (Settings tabs, recording-source rows, teleprompter tabs, overlay list rows) via `.contentShape`; duplicate "Check for Updates" Help item removed; export preset picker `.menu` → `.radioGroup` (all options visible); `⌘↵` runs Export in the dialog. Already done earlier (TODO was stale): `startNewTake` projectId via userInfo, `AssetChip` min/max width, inline export filename extension, count badge on the collapsed asset bar. N/A: asset-bar skeletons (takes are part of the already-loaded project — the editor shows a `ProgressView` until load, so there's no async take-loading state to skeletonize).

---

## UX Roadmap (needs alignment)

> Larger UX changes worth a conversation before implementing.

- [ ] **Recent Exports memory** — remember the last 3–5 destination folders and surface them as quick suggestions (Final Cut / Premiere pattern).
- [ ] **Right inspector tabs** — replace the stacked `ScrollView` of `ConfigGroup`s (Background / PiP / Zoom / Overlays) with tabbed sections to reduce scroll depth.
- [ ] **Layout preset hover preview** — overlay the chosen layout on the current frame inside the picker on hover.
- [ ] **Configurable asset bar position** (top / left / right) in Settings → Layout.
- [ ] **Empty state for a newly opened editor** — inline onboarding ("Drag a take from the bar above to start editing") with an animated arrow pointing at the empty timeline.
- [ ] **Visible zoom curve in timeline** — replace flat markers with a height-proportional mini graph so zoom intensity is readable.

---

## Tester Feedback — 0.6.3 beta round (Diego/Jackie)

> Raised 2026-06-10 after the first public-link beta. Analysis done (see session notes); ordered by agreed priority.

- [x] **Merge projects** — shipped (see `TASK_COMPLETED/2606.md`).
- [x] **Export / Import project bundle** — shipped in the 0.6.4 round (see above).
- [x] **Import video (with audio) into timeline** — shipped, including chips with drag/snap/trim/split, PiP positioning, row colors/reorder, and empty projects (see `TASK_COMPLETED/2606.md`).

---

## Tester Feedback — 0.6.4 round (next branch)

> Raised 2026-06-10 during the import/merge validation run.

- [x] **Export presets: bitrate control + estimated file size** — shipped: session preset now honors the codec (HEVC presets really export HEVC), `fileLengthLimit` targets the preset bitrate (it was decorative — hence the 951MB export), quality picker (Smaller/Standard/Higher) scales it, and the size estimate uses the same formula.
- [x] **Split → drag UX on video chips** — shipped: trim handles only exist (and are visibly drawn) on the SELECTED chip; unselected chips always move on drag.
- [x] **Export/Import project bundle** — shipped: `.cameramanproject` folder bundles (essentials only), context-menu Export Bundle… + '+' menu Import Project… with fresh project id.

---

## Editor Features (planned)

> Next batch of editor work. Depends on a stable export pipeline and `TimelineView`.

- [ ] **Mixed-resolution timelines — residual edge** — screen and camera-PiP frames now refit per-frame, and mixed-res projects always route through the compositor (preview + export). Remaining: camera refit needs `cameraRect` in the instruction (the single-instruction overlay paths pass nil), and zoom focus mapping uses the first clip's transform — both only matter if a merged section with a different-resolution camera also uses those paths.
- [ ] **Preview visibility toggles (Overlays/Layout/Captions)** — removed from the bar under the preview because they were never wired (local @State, no effect on render). Implementing them for real means gating overlay/layout/caption rendering in the preview pipeline per toggle.
- [x] **Auto-zoom tuning** `done: 2026-07-08` — auto-zoom now enabled by default (`FeatureFlags.autoZoom = true`). Manual zoom keyframes added so users can override/supplement auto-zoom. PR #42.

- [ ] **Zoom animation tuning** — hold duration, in/out velocity, smoother transitions between adjacent zoom points. The zoom-out between two points currently feels abrupt; evaluate a blend or crossfade.
- [ ] **Overlay polish**:
    - **Timing**: overlays appear in the wrong range during preview — debug the `currentTime >= overlay.start && currentTime <= overlay.end` filter in `MaskedVideoCompositor`.
    - **Edits not reflected**: position / scale / rotation changes from the popover don't show in preview. Verify `rebuildVideoComposition` propagates updated overlays and the overlay layer cache invalidates on property change.
    - **Direct visual placement**: tracked as the Priority 0 player direct-manipulation system above; edit overlays on the real video frame instead of a separate thumbnail-only mini canvas.
    - **Stacking in timeline**: multiple overlays collapse onto a single row; needs visual stacking or per-overlay rows.
    - **Render quality**: arrow / rect sizes and positions don't match the configured values.
    - What works today: timeline track, drag to move, popover controls, basic shape rendering in compositor and export.
- [ ] **Visible captions in preview** (improve current rendering).
- [ ] **Mic noise gate / echo cancellation** — filter speaker bleed captured by the mic, voice-activity detection to suppress silence. Note: `attackCoef` was removed from `AudioProcessing.swift` (unused warning); the gate currently jumps straight to 1.0 with no attack smoothing. If a full noise gate ships, restore the original coefficient.

---

## Engine Work (planned)

> Replacing stubs and skeleton implementations with real ones.

- [ ] **Real Whisper.cpp integration** — `TranscriptionEngine` returns simulated text today. Integrate `whisper.cpp` (or `SwiftWhisper`) for true offline transcription. Depends on a consolidated `JobQueue`.
- [ ] **Live recording preview** — the source selector currently shows static captures. Stream a lightweight ScreenCaptureKit feed during selection. Depends on the in-flight `EngineContext` DI refactor.

---

## Overlay System — Phase 2

> Deferred from the `refactor/overlays-unified-system` branch.

- [ ] **`Style` bag-of-optionals → `OverlayContent` enum with associated values** — replace `Style { stroke, font?, size?, color?, bg?, text?, imagePath?, ... }` with a discriminated enum (`shape`, `text`, `image`, `video`). Requires a custom `Codable` with back-compat decoding for existing projects. Ties into adding video as an overlay type below.
- [ ] **Reusable per-project asset library** — `imagePath` is absolute today and breaks when the user moves the source. On drop, copy into the project's `assets/` and store a relative path. UI: a sidebar grid of project assets, drag onto the timeline / preview to create an overlay.
- [ ] **Animated GIF in export (not just first frame)** — `ExportOverlayRenderer.swift` adds a single-frame `CALayer.contents`. Switch to `CAKeyframeAnimation` over `.contents` with each frame as a keyframe and timing matching the source GIF.
- [ ] **Drag overlay clip edges in timeline to trim** — currently the overlay clip only supports horizontal move. Mirror the trim pattern from `TimelineView+DragDrop` for edge drag → start / end change.
- [ ] **Video overlay** (additional `AVMutableComposition` track) — enables B-roll / picture-in-picture from another video. Refactor `MaskedVideoCompositor` to read `request.sourceFrame(byTrackID:)` from the overlay track and composite. Audio mix needs updating.
- [ ] **Granular subscription in `OverlayPopover`** (perf, low priority) — the popover observes the whole `editor` and re-renders on every project mutation (autosave / undo). Real cost is low (~1Hz max, popover visible only during edit) and the work was scoped out in the unified-overlay session. If it becomes perceptible with many overlays, model as `OverlayPopoverModel: ObservableObject` with `editor.$project.map { ...overlay-by-id... }.removeDuplicates()`.

---

## Feature Exploration — Native Video & AI `added: 2026-07-04`

> From the July 2026 Swift-frameworks exploration. Ordered by agreed priority. The first item is groundwork the cursor/zoom features depend on.

- [x] **Telemetry coordinate-space normalization (prerequisite)** `done: 2026-07-07` — added `CaptureGeometry` (capture rect in global Cocoa points + display scale), persisted per-recording on `Project.Sources.MediaTrack.capture`, with `inferred(...)` fallback for legacy projects. `ZoomPlanGenerator`, `TimelineView+ZoomSuggestions`, and `TelemetryOverlayView` now rebase telemetry into capture-local space before parsing/normalizing instead of dividing by hardcoded 1920×1080. See `CaptureGeometryTests.swift`.
- [x] **Synthetic cursor rendering (cursor dot + click ripples)** `done: 2026-07-07` — re-rendered in `MaskedVideoCompositor` from telemetry via `CursorPlan`, with configurable scale/color and click ripples. Wired through preview (`PreviewEngine.cursorPlan`) and export (`ExportOptions.cursorPlan`). See `CursorPlan.swift`, `CursorRenderer.swift`, `MaskedVideoCompositor.swift`, `PreviewComposition.swift`, `VideoExportSession+Composition.swift`, and `CursorPlanTests.swift`.
- [x] **Hide real cursor at capture** `done: 2026-07-08` — `CaptureConfiguration.hideSystemCursor` + recording UI "Hide Cursor" toggle. `SCStreamConfiguration.showsCursor = !hideSystemCursor`. PR #42.
- [ ] **Keystroke overlay** — remaining synthetic-cursor work: add a Keycastr-style keystroke overlay from `keys.jsonl` for export.
- [ ] **Camera background removal (Vision person segmentation)** — `VNGeneratePersonSegmentationRequest` per camera frame (runs on ANE) → alpha mask in the compositor so the PiP bubble renders with transparent or blurred background, no green screen.
- [ ] **Blur regions in video** — user-defined blur areas (rect + time range) rendered via `AdjustmentRenderer`/compositor. Phase 2: auto-suggest regions with `VNRecognizeTextRequest` over the screen track detecting sensitive text (emails, tokens, API keys).
- [ ] **AI-generated assets from the editor** — request AI-generated images/videos (background art, B-roll, voiceover) directly from the editor and insert them into the timeline as image/video clips. Needs a cloud provider abstraction + job in `JobQueue`. (Absorbs the former "Cloud provider for generated assets" item.)
- [ ] **Auto reframe to vertical (9:16)** — smart crop for social exports: follow the cursor from telemetry (or `VNGenerateAttentionBasedSaliencyImageRequest`) to keep the action in frame. Builds on the existing portrait preset.
- [ ] **LUT support** — load standard `.cube` files via `CIColorCube` as a new adjustment kind in `AdjustmentRenderer`.
- [ ] **Audio mastering pass** — loudness normalization (EBU R128 target via offline `AVAudioEngine`) and noise reduction as additional units in the `AudioAdjustmentTap` chain.
- [ ] **Speed ramps** — `scaleTimeRange` on the composition; e.g. "speed up silences" as a softer alternative to cutting them (pairs with auto-cuts on silence).
- [ ] **macOS 15 ScreenCaptureKit upgrades (if target bumps)** — built-in microphone capture and HDR recording via SCK.
- [ ] **`SpeechAnalyzer` as STT alternative (macOS 26)** — Apple's new speech API: faster than Whisper, no bundled models. Evaluate as fallback/replacement for WhisperKit in `TranscriptionEngine`.

---

## Engine — Polish & Experimental

> Larger backend items; many are speculative or post-v1.

- [ ] **Motion blur on zoom transitions** — blur proportional to camera movement during zoom in/out via `CIMotionBlur` or a Metal shader. Applied in `MaskedVideoCompositor` / `PreviewComposition`.
- [ ] **Hide desktop icons during recording** — toggle in `RecordingControlView`. On start: `defaults write com.apple.finder CreateDesktop -bool false && killall Finder`. On stop: restore. Save the prior value in case the user had them hidden already. Note: Finder restart causes a brief visual flash.
- [ ] **Interactive crop with aspect-ratio presets** (16:9 / 9:16 / 4:3 / 1:1 / 21:9) — drag + numeric inputs + ratio lock. Applied to the source video before layout.
- [ ] **Reorder segments in timeline** (v1.1).
- [ ] **Hover thumbnails on preview scrubber**.
- [ ] **Distribution permissions and entitlements review** before public launch.
- [ ] **Auto-generate proxies on project creation**.
- [ ] **Regenerate proxies when sync offsets change**.
- [ ] **Refactor `ZoomSectionController` + `ZoomPlanGenerator`** — their tests are the largest in the suite (49KB / 48KB), which usually signals the code under test is overdue for simplification.
- [ ] **Evaluate `LoggingSystem`: actor → `nonisolated` with lock** — `os_log` is thread-safe by design; the actor wrapper adds `await` friction in every call site. Only worth doing if the `await` causes real friction.
- [ ] **Frame-by-frame stylization** (experimental).
- [ ] **Auto-cuts on silence** (PRD Phase 5).
- [ ] **Chapters / titles from transcript** (PRD Phase 5).

---

## Performance (deferred)

> Items with a real cost but acceptable defaults today.

- [ ] **Long-duration validation** — never tested with videos > 1 hour. Stress test the writer, mic queue, telemetry parser, and preview composition end-to-end at that length.
- [ ] **`TimelineView` body memoization** — `TimelineTrackBuilder.tracks(for:)` and `computeOverlayRows(...)` run on every body invalidation. During playback `currentTime` ticks constantly and triggers redundant recomputes. Requires extracting a sub-view or a derived `@StateObject`.
- [ ] **`ThumbnailCache` LRU O(N) → O(log N) or O(1)** — `thumbnailAccessOrder.removeAll { $0 == key }` is O(N) per insert; with `maxThumbnailCount = 500` each miss is 500 comparisons. Needs `swift-collections` `OrderedDictionary` or a manual hash + linked list.
- [ ] **`MaskedVideoCompositor` dynamic camera property** — proper fix for the PiP drag rebuild path. Updates would skip the `AVMutableVideoComposition` rebuild entirely. Touches every consumer of the custom compositor. The throttle bump in PR #15 is the interim mitigation.
- [ ] **`RecordingSession` snapshot refactor** — the interim `@unchecked Sendable` from PR #15 is fine for now. Long-term, replace with a `Sendable` `SessionState` snapshot consultable on demand (no shared mutable state crossing actor isolation).

---

## Distribution / Gatekeeper

- [ ] **Ad-hoc signing in `build-dmg.sh`** — `codesign --force --deep --sign - CameramanApp.app` before packaging. Does not bypass Gatekeeper on Tahoe but stabilizes the internal signature and avoids errors with embedded frameworks. Tester feedback recorded in `TASK_COMPLETED/2605.md`.
- [ ] **Developer ID + notarization** — the only real fix for the Gatekeeper warning on macOS Tahoe. Requires the Apple Developer Program subscription, the `Developer ID Application` certificate, and a `xcrun notarytool submit` + `stapler staple` pipeline.

---

## Tooling — Claude Code Skills

- [ ] **Create a `cameraman-engine` skill via `/skill-creator`** — gap identified during the skills baseline review: no public skill covers AVFoundation / ScreenCaptureKit / `AVMutableComposition` / the keyframed zoom pipeline. Package internal conventions: `CompositionBuilder`, `MaskedVideoCompositor`, `AudioMixBuilder`, the `DwellDetector → ZoomSuggestionEngine → ZoomPlanGenerator → PreviewRenderer` pipeline, the engine/UI actor split, the 400–500 LOC and zero-warnings rules. Validate against a real task (refactor of `ZoomSectionController` or a new overlay type). Decide whether to publish it or keep it under `.claude/skills/`.

---

## Compiler / SDK limitations (waiting on Apple)

- [ ] **2 irreducible warnings in `MaskedVideoCompositor`** — `sourcePixelBufferAttributes` and `requiredPixelBufferAttributesForRenderContext` don't accept the `@Sendable` getter that `AVVideoCompositing` requires via `NS_SWIFT_SENDABLE`. Standard workarounds all fail: `@preconcurrency import`, `@preconcurrency` on conformance, `nonisolated` computed property with `static let`, `[String: any Sendable]`. Waiting on an SDK fix from Apple; documented inline in the file.
