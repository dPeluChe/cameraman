# Task Backlog

> Updated: 2026-10-04
> Only unfinished work. Completed work lives in `TASK_COMPLETED/`.
> Ordered by impact and proximity to release, not chronology.

---

## Recently Closed

October 2026: MCP server hosted inside the app (loopback HTTP, opt-in, token in Keychain), editor freezes while an agent edits, MCP tools consolidated 43→37 with annotations, real global hotkeys (were stubs), crash-handler and atomic-write fixes, competitor analysis. Write-up in `TASK_COMPLETED/2610.md`.
June 2026 (0.7.0 push): MCP automation server (42 tools), transcription + MCP integration settings (bundled/signed server), per-clip effects UI, live project refresh, import-only export + readable export errors, multi-track `delete_range`. Full write-up in `TASK_COMPLETED/2606.md` (§ 0.7.0).
June 2026 (0.6.4 push): merge projects, video import with full clip editing (snap/trim/split/PiP/reorder), empty projects, timeline ruler + fit zoom + pinned labels, rename fix, mixed-resolution rendering, preview-toggle audit. Full write-ups in `TASK_COMPLETED/2606.md`.
May 2026 (pre-publication push): ultrawide writer fix, mic overload, telemetry streaming, security audit, repo publication. Write-ups in `TASK_COMPLETED/2605.md`.

---

## Release plan — 0.7.x series `added: 2026-10-04`

> Decided 2026-10-04. Base is **0.7.1**; we ship short increments (0.7.2, 0.7.3, ...) and move to **0.8** only when things are stable and complete. Mobile is on hold; the focus is the desktop app. The last published release is **v0.6.3 (June)**.
>
> **Build, sign, notarize and tag happen once, at the end of a batch, after validating everything together**, not per PR or per version. Until then we merge to `main` and test locally. Principle: ship what works and is verified, close the cheap gaps against competitors (see `RESEARCH/COMPETITOR_SMOOTH_RECORDER.md`), do not chase a different product (screenshots, 3D angles). Sizes are relative guesses (S/M/L), not estimates. PRs get the multi-agent simplify pass only when the code change is heavy.

### 0.7.1 — what already exists, made reliable

- [x] **Version alignment** — `MARKETING_VERSION` is `0.7.0` in the Xcode project, `App/Info.plist` and the README say `0.8.0` (and `GENERATE_INFOPLIST_FILE = YES` means the plist is unused), `docs/README.md` and `APP_STORE_METADATA.md` say `0.7.0`. No `0.8.0` tag or release exists, so the unpublished `[0.8.0]` changelog section folds into 0.7.1. (S) `done 2026-10-04` (#62)
- [x] **CHANGELOG** — `[Unreleased]` is empty. Add as we go: in-app MCP server, agent-edit freeze, tool consolidation (**breaking tool names**, 43→37), real global hotkeys, crash-handler fix, atomic project writes. (S) `updated 2026-10-04` as the batch lands; rename the header at release.
- [x] **Surface capture errors** — `SCStream` is created with `delegate: nil` and `StreamDelegate` is never passed in, so if the display disconnects, permission is revoked or the system stops the stream the app keeps showing "recording" and writes a truncated or empty file. Deliver `didStopWithError` through `recordingFailed`. (M) `done 2026-10-04` (#63). Not seen to happen on screen: revoke Screen Recording mid-recording or unplug a monitor to check.
- [x] **Flush edits on quit** — autosave is a 1 s debounce held by `[weak self]`; quitting or closing inside that second loses the edit, and `applicationWillTerminate` does not flush. (S) `done 2026-10-04` (#64). Check by hand: edit, then Cmd+Q at once.
- [x] **Helper signing** — sign `cameraman-mcp` with `--timestamp` and build it universal (arm64 only today); needed before notarization. (S) `done 2026-10-04` (#65). The `--timestamp` path with the Developer ID certificate first runs in the release build.
- [ ] **Manual validation** (nothing here has run on screen): global hotkeys fire with the app in the background (PR #53 has unit tests only); the agent-freeze notice shows and releases (#57); Claude Code connects over the in-app HTTP server (#55); one 30-60 minute recording and export (nothing has run past an hour). (S, waiting)
- [ ] **At the end of the batch**: `make release`, signed with the installed Developer ID certificate, notarize, staple, open on a clean user. The notary profile `cameraman-notary` is **not** in this machine's keychain yet (`xcrun notarytool store-credentials cameraman-notary`).
- [ ] **Public pieces** — privacy policy at a public URL (text in `docs/PRIVACY_POLICY.md`; GitHub Pages is not enabled and the landing is undecided), a minimal landing with the download link, and a decision on price and license (open source plus a signed build, amount open; the competitor is $9 one-time).

### 0.7.2 — cheap gaps against competitors

- [ ] **Keystroke overlay** (M, needs a decision) `corrected 2026-10-04` — earlier notes said `keys.jsonl` was already captured; it is not. `KeystrokeRecorder` exists but is **never instantiated** (`Recorder` only starts `TelemetryRecorder`, the mouse), so nothing records keys. Building the overlay means capturing the keyboard globally: a new Accessibility or Input Monitoring permission, a privacy-policy change, and likely a problem in a sandboxed build. Proposal if we do it: record only shortcut chords (with ⌘ ⌃ ⌥) and special keys, never plain typed text, so a password is never captured. Decide before building.
- [x] **Reframe presets 1:1 and 4:5** (S) — today there is 9:16. Keep the MCP preset list in sync. `done 2026-10-04` (#66). Check an export of each by eye.
- [x] **Self-timer** (S). `done 2026-10-04` (#67).

### 0.7.3 — manual region blur

- [x] **Region blur** (M) — add `x, y, w, h` parameters to the existing `gaussianBlur` adjustment (time-ranged and whole-layer today) and an inspector control. Detection comes later. `done 2026-10-04` (#68 engine and MCP, #69 UI). Verified on a real export. Region sliders only: dragging the region on the preview belongs to Direct Visual Editing.

### 0.7.4 and after — the headline feature

- [ ] **Cut by transcript** (L) — the transcript stores **segments only, no word-level timestamps**. Order: enable word timestamps in `WhisperKitTranscriber` and persist them; map a word range to `delete_range`; UI to delete words; filler-word and long-pause detection as a reviewable list, not blind deletion; an MCP tool so an agent can remove fillers.
- [ ] **Smart Redact detection** (M, after region blur) — Vision text boxes plus regex (emails, keys, cards) that emit blur adjustments.

### Not now

Screenshots, scrolling capture, OCR copy-text, 3D zoom angles, AI-generated assets, LUTs, motion blur, frame stylization. The Mac App Store variant is a separate track: it needs the embedded helper excluded, no GitHub self-updater and PayPal links, and a sandbox test of the Accessibility-dependent cursor telemetry.

### Decision needed

- **Direct Visual Editing (Priority 0, below)** is flagged as the primary UX direction, but only its baseline shipped (overlay select/move/scale/rotate/snap). The rest is large. Proposal: keep it out of the 0.7.x series and treat it as the theme for 0.8.

---

## Timeline review findings `added: 2026-10-05`

> Two read-through reviews (engine and UI) found 37 issues; the full ranked list with how each was verified is `RESEARCH/TIMELINE_REVIEW_2026-10.md` (IDs E1-E17, U1-U20). The timeline is a core strength, so these come before new features. Order: (1) engine data loss and wrong output: E1 segments setter drops effects, E2 split-at-playhead drops effects, E6/U4 undo and several edits never autosave, E5 ripple does not move overlays/subtitles/chapters/zoom keyframes, E4 speed change does not ripple, E10 volume above 1 blocks later trims; (2) preview correctness: U1 preview plays the old cut after a trim, U2 playhead jumps to 0 after an edit, U3 reload wipes undo; (3) selection and keyboard: U6, U7, U8, U5; (4) composition: E3 primary track ignores clip start times, E7, E8, E9, E12, E13; (5) performance and polish: U10, U11, U12, U9.

## Follow-ups from the 2026-10-05 test run and simplify reviews `added: 2026-10-05`

- [ ] Camera shape change (circle to pill) does not repaint until the camera is dragged. Not reproduced by reading; `[PREVIEW] updateProject` logs added, capture them while toggling the shape.
- [ ] Elements lane: one `ElementSelection` enum on the view model instead of three ids (`selectedOverlayId`, `selectedMediaItemId`, `selectedBlurRegionId` on `ProjectEditor`); shared `TimelineChip` view for the three chip rows; per-kind select/move into editor methods when a 4th kind (clip effects, arrows) lands.
- [ ] Preview canvas: `OverlayInteractionLayer` and `BlurRegionCanvasEditor` reimplement drag/resize; one generic rect editor.
- [ ] Blur: trim start/end by dragging chip edges (today: panel steppers); live preview while dragging on the canvas (commits on release).
- [ ] Perf (see `PERF_MEMORY_AUDIT_2026-10.md`): playhead out of `TimelineView`, 1-byte masks, pause that really pauses.
- [ ] Synthetic cursor: existing recordings keep the old offset (no stored value); new ones anchor to the video start. Verify on a fresh recording.

## Camera background follow-ups `added: 2026-10-09`

- [ ] MCP: expose `cameraBackground` (set_layout or a new tool + catalog test) so agents can use it.
- [ ] Per-segment override (like `cameraPosition`) or model it as an `AdjustmentKind` on the camera target to get time ranges, validation and MCP for free (altitude review).
- [ ] Persist the matte per source (computed once, reused by export and scrubbing) instead of the 8-frame in-memory cache; also enables person-over-screen effects.
- [ ] Idea: accessories on the person (glasses, hat, ears) anchored with Vision face landmarks (`VNDetectFaceLandmarksRequest`: eyes, nose, face rect, roll/yaw/pitch), reusing the image overlay renderer; needs per-frame tracking and smoothing.
- [ ] Image background; measure on other Macs and cluttered backgrounds (spike used one indoor clip on an M1 Max).
- [ ] Skip segmentation when the camera layer is off canvas; negative-cache failed frames.

## Preview refresh follow-ups (round 1 simplify) `added: 2026-10-09`

- [ ] Move the `editor.$project` subscription out of `PreviewPlayerView.body` into the view model (one subscription, `dropFirst().removeDuplicates().debounce`), then drop the `viewModel.project != project` guard. `onReceive` re-subscribes on every body pass and replays the current value.
- [ ] Pause/seek/resume on every composition swap hitches playing previews; the principled fix is for the compositor to read mutable state (lock-protected config box) at render time so layout/shape edits need no AVFoundation invalidation.
- [ ] Serialize refresh in one cancel-and-replace task (or in the engine); `refreshGeneration` covers the view model path only (Voiceover and OverlayInteractionLayer call `refreshPreview` too).
- [ ] REC indicator: screen from the capture source for window/app modes (today only display sources pick the recorded screen); apply `excludedWindowIDs` in one filter helper.
- [ ] A selected overlay still shows at zero opacity at its exact start while paused; an edit-mode rule (show fade-in at full opacity while selected) would also cover selecting existing overlays.
- [ ] Subtitle editor still uses the raw system `ColorPicker`.

## Camera accessories follow-ups `added: 2026-10-10`

- [x] Custom images (SVG/PNG/JPG) as accessories with face or frame anchors (`CustomAccessory`, 2026-10-10). Still open: optional time range per accessory, offsets in the UI, built-ins as data presets (keep raw values `glasses`, `sunglasses`, `partyHat`, `crown` as preset ids), MCP exposure.
- [ ] One shared per-frame analysis (matte + landmarks in one Vision pass, later an analysis timeline cached per source) with smoothing: landmarks jitter a few pixels and a frame with no face makes the prop pop off. Random-access scrubbing needs smoothing computed offline, not per frame state.
- [ ] `CameraEffects` model (background + accessories) in the persisted schema, and one MCP tool for it; today only the render side is unified (`CameraLayerRender`).
- [ ] Move the camera effect sections out of the PiP-only panel so they are reachable in every layout; extract the shared chip style used by Shape and Accessories.
- [ ] Measured and rejected: landmarks on a 640 px copy cost the same as full 1080p (15.2 ms vs 15.2 ms), so downscaling does not help. Remaining levers are every-2nd-frame sampling or a sequence handler.

## Custom accessories follow-ups (PR #92 simplify) `added: 2026-10-10`

- [ ] Decide before more accessory features land: frame-pinned logos as an image `Overlay` anchored to the camera rect (time ranges, fades, selection, Elements lane, MCP overlay tools for free) vs the camera-layer `CustomAccessory`. Face-following stickers stay camera-layer either way.
- [ ] Resolve accessory asset paths in one place (export rewrites a Project copy, preview passes the directory); `CameraLayerRender.export` has a silently empty directory default.
- [ ] One `needsCompositor` predicate shared by the preview and export builders instead of `hasCameraEffects` patched into five lists (and a test that both agree).
- [ ] Mark the row in the UI when an accessory file is missing (today: one log line); share the bitmap draw with `OverlayImageRenderer.staticCGImage`.
- [ ] Merge: second project's assets are copied by name and can collide with the first's; accessory names stay unique only within one project.

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

- [ ] **Cross-process project revision and conflict protection** `updated: 2026-10-04` — `project.json` writes are now atomic (#52) and the in-app MCP server freezes the open editor and flushes it first (#57). Remaining: a monotonic revision / compare-and-swap in `ProjectLibrary.updateProject`, which also protects the stdio helper (a separate process that cannot signal the app).
- [ ] **Finish the AI suggestion flow** `updated: 2026-10-04` — paths fixed and results readable (`get_job_status` returns `suggestions`, one file per job, #58). Remaining: `apply_suggestions(ids)` and `dismiss_suggestions`, and a way for the app UI to share the same per-job results.
- [ ] **Enforce editing invariants through EngineKit** `added: 2026-07-13` — reject edits and moves on locked tracks; validate non-negative timeline positions, positive speed/duration, valid source windows, opacity/volume bounds, effect ranges, canvas positions, and overlay timing. The same validation must protect UI and MCP.
- [ ] **Make asset staging collision-safe and transactional** `added: 2026-07-13` — use content-addressed or unique filenames instead of replacing an existing same-name asset; clean staged files when the following edit fails; validate file type and size before copying.
- [ ] **Expand the MCP test suite** `updated: 2026-10-04` — inventory test fixed; 23 tests cover protocol, HTTP transport and security, catalog/dispatcher sync, annotations. Remaining: every mutating tool family, locks/validation, jobs, asset collisions, concurrent app/MCP edits, end-to-end edit→preview→export. Never execute tools against the real library in tests (a test once created a real project).

### Priority 1 — Agent-grade API

- [ ] **MCP protocol conformance hardening** `updated: 2026-10-04` — protocol-version negotiation done. Remaining: validate JSON-RPC and request params, protocol errors for malformed calls and unknown tools, enforce initialization state, strict schemas with `additionalProperties: false`.
- [ ] **Structured tool results** `updated: 2026-10-04` — `readOnlyHint`/`destructiveHint` annotations done (#56). Remaining: `outputSchema`, `structuredContent`, stable IDs/revisions/warnings, keeping the serialized text for older clients.
- [ ] **Transactional agent editing with dry-run and diff** `added: 2026-07-13` — support `begin_edit`, batched operations, `preview_diff`, `commit_edit`, and `rollback_edit`; report affected clips, duration changes, validation warnings, and one undoable commit.
- [ ] **Checkpoints, undo, and recoverable deletion for agents** `added: 2026-07-13` — expose checkpoint/revert and move project deletion to Trash or a recoverable tombstone instead of immediate irreversible removal.
- [ ] **Compact, queryable project context** `updated: 2026-10-04` — `get_project` omits subtitle cues by default and reports `subtitleCount` (#58); real projects measure 430-900 tokens, so this only matters for long subtitled videos. Remaining: track/time-range filters and pagination.
- [ ] **Visual feedback tools for agents** `added: 2026-07-13` — reuse `PreviewFrameExtractor` / `ThumbnailCache` to expose `render_frame`, contact sheets, thumbnails, and waveform summaries. Return resource links or image content so an agent can inspect the result before committing/exporting.
- [ ] **Persistent and observable jobs** `added: 2026-07-13` — persist export/transcription/AI job state across server restarts; return output paths/results; add progress events where supported and structured audit logs with client, tool, project, revision, duration, and sanitized result/error.

### Priority 2 — MCP feature parity

- [ ] **Expose remaining editor controls to agents** `added: 2026-07-13` — manual zoom keyframes, clip position/size/crop, subtitle cue/style editing, chapter CRUD/application, voiceover recording, screen/window/app/camera source selection, and recording pause/resume.
- [ ] **Evaluate MCP resources and prompts after the mutation API stabilizes** `added: 2026-07-13` — use resources for project/timeline/render artifacts and prompts for safe common workflows; defer experimental MCP Tasks until they materially improve the existing job model.

---

## Competitor-informed (Smooth Recorder, 2026-10-04)

> Analysis in `RESEARCH/COMPETITOR_SMOOTH_RECORDER.md`; landing plan in `RESEARCH/LANDING_CONTENT_BASE.md`. Candidates, not commitments.

- [ ] **Cut by transcript + filler/pause removal** `added: 2026-10-04` — delete words in the transcript to ripple-delete the matching range (builds on transcription, `delete_range`, silence detection). Expose as an MCP tool so an agent can "remove every um". Their headline feature.
- [ ] **Smart Redact** `added: 2026-10-04` — extends "Blur regions in video" (Feature Exploration). Starting point: the existing `gaussianBlur` adjustment is time-ranged but whole-layer, so add region params and a detector that emits adjustments. Detect emails, card numbers, API keys, faces on-device (Vision text boxes plus regex) and blur them. Raise priority: developers record secrets.
- [ ] **Reframe presets 1:1 and 4:5** `added: 2026-10-04` — small step toward auto reframe; today there is a 9:16 preset.
- [ ] **Curated background pack** `added: 2026-10-04` — backgrounds are color/image/blur only; content work, not engine work.
- [ ] **Self-timer and menu bar item** `added: 2026-10-04`.
- [ ] **App Intents (Shortcuts): start/stop recording** `added: 2026-10-04` — automation, fits the agent story.
- [ ] **Landing: alternatives pages, blog, per-page SEO** `added: 2026-10-04` — see the checklist in `LANDING_CONTENT_BASE.md` (repo `cameraman-landing`).

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
- [x] **Auto-cuts on silence** `done` — `suggest_silence_edits` + `AISuggestionsView` produce reviewable suggestions. Applying them in one click is covered by the cut-by-transcript work.
- [x] **Chapters / titles from transcript** `done` — `suggest_chapters` + `AISuggestionsView`.

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

- [ ] **Developer ID + notarization** `updated: 2026-10-04` — a `Developer ID Application` certificate is installed and `scripts/notarize-dmg.sh` exists (profile `cameraman-notary`, not verified). Remaining: sign the embedded `cameraman-mcp` with `--timestamp` and build it universal (arm64 only today), run the full `make release`, staple, and open the DMG on a clean user to confirm Gatekeeper.

---

## Tooling — Claude Code Skills

- [ ] **Create a `cameraman-engine` skill via `/skill-creator`** — gap identified during the skills baseline review: no public skill covers AVFoundation / ScreenCaptureKit / `AVMutableComposition` / the keyframed zoom pipeline. Package internal conventions: `CompositionBuilder`, `MaskedVideoCompositor`, `AudioMixBuilder`, the `DwellDetector → ZoomSuggestionEngine → ZoomPlanGenerator → PreviewRenderer` pipeline, the engine/UI actor split, the 400–500 LOC and zero-warnings rules. Validate against a real task (refactor of `ZoomSectionController` or a new overlay type). Decide whether to publish it or keep it under `.claude/skills/`.

---

## Compiler / SDK limitations (waiting on Apple)

- [ ] **2 irreducible warnings in `MaskedVideoCompositor`** — `sourcePixelBufferAttributes` and `requiredPixelBufferAttributesForRenderContext` don't accept the `@Sendable` getter that `AVVideoCompositing` requires via `NS_SWIFT_SENDABLE`. Standard workarounds all fail: `@preconcurrency import`, `@preconcurrency` on conformance, `nonisolated` computed property with `static let`, `[String: any Sendable]`. Waiting on an SDK fix from Apple; documented inline in the file.
