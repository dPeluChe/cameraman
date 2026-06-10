# Task Backlog

> Updated: 2026-05-19
> Only unfinished work. Completed work lives in `TASK_COMPLETED/`.
> Ordered by impact and proximity to release, not chronology.

---

## Recently Closed

Resolved during the May 2026 pre-publication push. Full per-item write-ups in `TASK_COMPLETED/2605.md`.

- Ultrawide `AVAssetWriter` error `-10877` (3440×1440 → corrupt `screen.mov`) — PR #15 (HEVC fallback for any output > 1920×1080).
- `HALC_ProxyIOContext: skipping cycle due to overload` warnings + mic glitches — PR #15 (mic writes hopped off the real-time tap thread).
- `TelemetryParser` memory peak ≈ `file_size × 3` on long sessions — PR #15 (`FileHandle.bytes.lines` streaming).
- `RecordingSession` non-Sendable under Swift 6 strict concurrency — PR #15 (interim `@unchecked Sendable`; snapshot refactor still listed below).
- Pre-publication security audit (4 critical + 3 recommended findings) — PR #14.
- Repo rename `labs-cameraman` → `cameraman`, brand consolidation, `LICENSE`/`CONTRIBUTING`/`AppLinks` email unification — PR #14.

---

## Bugs & Stability

> Real defects to clear before / during pre-release. None block App Store submission today, but each adds friction.

- [ ] **PiP camera overlay drag-to-reposition during playback** — historically only worked when paused. Likely resolved by the earlier `fix/pip-drag-playback-and-logs-cleanup` work (`draftCamera` @State pattern) and the throttle change in PR #15. Verify on a fresh build before closing.
- [ ] **Warning: "Publishing changes from within view updates is not allowed" on project load** — fires once when opening a project in the editor; benign at runtime, no crash. Three prior fix attempts (`80cfa4e`, `1102beb`, `a08fadf`) were insufficient or regressed. Candidates not yet ruled out: `ProjectEditorViewModel.loadProject`, the toast `Binding(get:set:)` in `ProjectEditorView` line 164, or some mutation in the `.task` chain of `AppNavigation`. Needs runtime instrumentation (breakpoints or `os_log` around the first `objectWillChange.send()`) to locate the real emitter.
- [ ] **`NSHostingView is being laid out reentrantly` / `AttributeGraph: cycle detected` (~150 entries)** — observed once when bumping the PiP throttle to 60Hz; that commit was reverted. Watch for recurrence; if it returns, investigate cyclic dependency between `PreviewPlayerView` (observing `viewModel.avPlayer`), `PiPCanvasEditor` (pushing to `engine.updateProject`), and SwiftUI's view-update graph. Symptom in the affected run: export took 14s vs. the usual 5.4s (~3× slowdown).
- [ ] **Telemetry: count `-10877` errors per session, correlate with `writer.status`** — root cause was H.264 on ultrawide and is fixed, but instrumentation would catch any future writer pre-failure regressions and confirm the cause of the original B1 incident (Messages VFX vs. codec mismatch).
- [ ] **UI debug: `Attempting to update all DD element frames, but bounds W:0 H:0`** — appears once during preview. Probably system Drag & Drop or RealityKit, not our code. Low priority; reproduce with the view debugger if it returns.
- [ ] **Noisy system logs in release builds** — Messages VFX entity remaps, `MLE5Engine disabled`, `ViewBridge to RemoteViewService Terminated`, `AddInstanceForFactory: No factory registered`, `AudioQueueObject Error -4 getting reporterIDs`. None are ours but they drown out useful signal. Audit `LoggingSystem` levels: anything at `info` / `notice` in `capture` / `preview` / `export` that should be `debug`.

---

## UX Polish

> Small, low-risk improvements. None change product direction.

- [ ] **Latent race in `startNewTake()`** — `ProjectEditorLeftPanel.swift:103-107` assigns `recViewModel.targetProjectId` before posting `.openRecordingWindow`. Works today because the observer is synchronous; if it ever becomes async, the window may read `nil`. Pass `projectId` via `Notification.userInfo` to make the contract explicit.
- [ ] **Count badge on collapsed `ProjectAssetsBar`** — at 38pt height there's no signal of how many takes/segments exist. Add `(\(count))` next to the title when collapsed.
- [ ] **`AssetChip` fixed width truncates long names** — replace `frame(width: 118)` with `minWidth: 100, maxWidth: 180` + `fixedSize(horizontal: false)`.
- [ ] **Export preset picker context** — `.menu` style hides the options; consider `Picker` with per-option icon labels (HEVC, GIF, H.264) to preserve affordance.
- [ ] **Keyboard shortcuts** — `⌘E` open export panel, `⌘⇧E` rerun the last export, `⌘R` open recording window.
- [ ] **Skeletons on `ProjectAssetsBar`** — distinguish "loading" from "empty" while takes are still being read.
- [ ] **Inline filename extension in `ExportView`** — show `.mp4` / `.gif` as a grey inline suffix on the field instead of a separate caption.

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

- [ ] **Merge projects** *(in progress — branch `feat/merge-projects`)* — combine project A + B into a new project C whose timeline is A's blocks followed by B's (sources copied, takes appended, clip times/chapters offset by A's duration). Risk: takeId/path remapping and time-offsetting all metadata (chapters, captions, overlays).
- [ ] **Export / Import project bundle** — export a whole project (project.json + sources/ all channels + telemetry + thumbnail; skip cache/proxies/renders) to a user-chosen folder/zip, plus an Import counterpart that re-assigns the projectId. Context-menu entry + NSSavePanel (same sandbox pattern as Diagnostics). Enables sharing projects between machines.
- [x] **Import video (with audio) into timeline** — shipped on `feat/import-video-track`: Import button accepts movies; each import gets its own `.video` track row; frames composited (aspect-fit, post-zoom) and **embedded audio extracted** for preview + export. Follow-ups: clip drag/trim UI for these chips (engine split/trim APIs exist, chips are static), per-clip position/size on canvas (MediaPosition is modeled but compositor renders fullscreen-fit only).

---

## Editor Features (planned)

> Next batch of editor work. Depends on a stable export pipeline and `TimelineView`.

- [ ] **Mixed-resolution timelines — residual edge** — screen and camera-PiP frames now refit per-frame, and mixed-res projects always route through the compositor (preview + export). Remaining: camera refit needs `cameraRect` in the instruction (the single-instruction overlay paths pass nil), and zoom focus mapping uses the first clip's transform — both only matter if a merged section with a different-resolution camera also uses those paths.
- [ ] **Auto-zoom tuning** — hidden behind `FeatureFlags.autoZoom` (default off): suggestion timing/intensity confused testers; auto-apply-on-open removed. Tune dwell thresholds, zoom-out blending and intensity before re-enabling by default.

- [ ] **Zoom animation tuning** — hold duration, in/out velocity, smoother transitions between adjacent zoom points. The zoom-out between two points currently feels abrupt; evaluate a blend or crossfade.
- [ ] **Overlay polish**:
    - **Timing**: overlays appear in the wrong range during preview — debug the `currentTime >= overlay.start && currentTime <= overlay.end` filter in `MaskedVideoCompositor`.
    - **Edits not reflected**: position / scale / rotation changes from the popover don't show in preview. Verify `rebuildVideoComposition` propagates updated overlays and the overlay layer cache invalidates on property change.
    - **Visual placement canvas**: the 9-position presets are limited. Implement a mini canvas (like the PiP editor) where the user drags the overlay over a thumbnail of the frame.
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
- [ ] **Cloud provider for generated assets** (background art, voiceover, etc.).
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
